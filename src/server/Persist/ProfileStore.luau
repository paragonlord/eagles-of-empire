--!strict
-- Versioned profile store on top of DataStoreService.UpdateAsync. Pure Luau; the DataStore
-- service is injected so tests run in the CLI with the memory adapter.
--
-- Contract:
--   * `load` never returns a default on failure: status "error" means "do not touch this user".
--   * `update` runs a pure, retry-safe mutate inside UpdateAsync (the callback may run more than
--     once); it rejects when the stored revision differs from `expectedRevision` ("stale") and
--     bumps `revision` on every successful write.
--   * `claimSession`/`releaseSession` implement single-writer ownership with a timeout so a crashed
--     server never locks a profile forever. `now` is injected (no wall clock here).
--   * The memory adapter marks the store `sessionOnly = true`: data lives for this server only.
--     Callers must surface that, never claim durability.

export type Profile = { [string]: any }
export type Mutate = (Profile?) -> (Profile?, string?)

export type Store = {
	name: string,
	scope: string,
	sessionOnly: boolean,
	sleep: (number) -> (),
	maxRetries: number,
	backoff: number,
	sessionTimeout: number,
	ds: any,
	load: (Store, number) -> (Profile?, string),
	update: (Store, number, number?, Mutate) -> (boolean, Profile?, string?),
	claimSession: (Store, number, string, number) -> (boolean, string?),
	releaseSession: (Store, number, string) -> (boolean, string?),
}

local ProfileStore = {}
ProfileStore.__index = ProfileStore

-- Deep copy that only accepts what a DataStore can hold (plain tables, strings, finite numbers,
-- booleans). Used by the memory adapter so in-memory behaviour matches serialisation.
local function clone(v: any, depth: number?): any
	local t = type(v)
	if t == "table" then
		local d = (depth or 0) + 1
		if d > 32 or getmetatable(v) ~= nil then
			error("unserialisable value")
		end
		local out = {}
		for k, x in v do
			local kt = type(k)
			if kt ~= "string" and kt ~= "number" then
				error("unserialisable key")
			end
			out[k] = clone(x, d)
		end
		return out
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("non-finite number")
		end
		return v
	elseif t == "string" or t == "boolean" or t == "nil" then
		return v
	end
	error("unserialisable value of type " .. t)
end
ProfileStore.clone = clone

local function memoryAdapter()
	local data: { [string]: any } = {}
	return {
		GetAsync = function(_, key: string)
			return clone(data[key])
		end,
		UpdateAsync = function(_, key: string, fn: (any) -> any)
			local new = fn(clone(data[key]))
			if new ~= nil then
				data[key] = clone(new)
			end
			return clone(new)
		end,
	}
end

local function isProfile(v: any): boolean
	return type(v) == "table" and type(v.version) == "number" and type(v.revision) == "number"
end

function ProfileStore.new(opts: { name: string, scope: "live" | "dev", dataStoreService: any?, sleep: ((number) -> ())?, maxRetries: number?, backoff: number?, sessionTimeout: number? }): Store
	local self: any = setmetatable({}, ProfileStore)
	self.name = opts.name
	self.scope = opts.scope
	self.sleep = opts.sleep or task.wait
	self.maxRetries = opts.maxRetries or 3
	self.backoff = opts.backoff or 1
	self.sessionTimeout = opts.sessionTimeout or 300
	self.sessionOnly = false
	local svc = opts.dataStoreService
	local ok, ds = false, nil
	if svc ~= nil then
		ok, ds = pcall(function()
			return svc:GetDataStore(opts.name .. "/" .. opts.scope)
		end)
	end
	if ok and ds ~= nil then
		self.ds = ds
	else
		self.ds = memoryAdapter()
		self.sessionOnly = true
	end
	return self
end

local function key(userId: number): string
	return "u" .. tostring(userId)
end

-- Retries fn (which may throw) with exponential backoff. Returns (ok, result).
local function withRetry(self: Store, fn: () -> any): (boolean, any)
	local lastErr: any = nil
	for attempt = 0, self.maxRetries do
		if attempt > 0 then
			self.sleep(self.backoff * 2 ^ (attempt - 1))
		end
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
	end
	return false, lastErr
end

function ProfileStore.load(self: Store, userId: number): (Profile?, string)
	local ok, res = withRetry(self, function()
		return self.ds:GetAsync(key(userId))
	end)
	if not ok then
		return nil, "error"
	end
	if res == nil then
		return nil, "empty"
	end
	if not isProfile(res) then
		return nil, "error" -- corrupt: refuse rather than overwrite
	end
	return res, "ok"
end

function ProfileStore.update(self: Store, userId: number, expectedRevision: number?, mutate: Mutate): (boolean, Profile?, string?)
	local reason: string? = nil
	local seen: any = nil
	local ok, res = withRetry(self, function()
		reason = nil
		return self.ds:UpdateAsync(key(userId), function(old: any): any
			-- Pure section: no side effects, may run several times.
			if old ~= nil and not isProfile(old) then
				reason = "corrupt"
				return nil
			end
			seen = old
			local stored = if old then old.revision else 0
			if expectedRevision ~= nil and stored ~= expectedRevision then
				reason = "stale"
				return nil
			end
			local new, why = mutate(old)
			if new == nil then
				reason = why or "cancelled"
				return nil
			end
			new.version = new.version or 1
			new.revision = stored + 1
			return new
		end)
	end)
	if not ok then
		return false, nil, "error"
	end
	if res == nil then
		return false, seen, reason or "cancelled"
	end
	return true, res, nil
end

function ProfileStore.claimSession(self: Store, userId: number, sessionId: string, now: number): (boolean, string?)
	local ok, _, reason = ProfileStore.update(self, userId, nil, function(old: Profile?): (Profile?, string?)
		local p: Profile = old or { version = 1, revision = 0 }
		local s = p.session
		if type(s) == "table" and s.id ~= sessionId and type(s.expires) == "number" and s.expires > now then
			return nil, "locked"
		end
		p.session = { id = sessionId, expires = now + self.sessionTimeout }
		return p, nil
	end)
	return ok, reason
end

function ProfileStore.releaseSession(self: Store, userId: number, sessionId: string): (boolean, string?)
	local ok, _, reason = ProfileStore.update(self, userId, nil, function(old: Profile?): (Profile?, string?)
		if old == nil or type(old.session) ~= "table" or old.session.id ~= sessionId then
			return nil, "notOwner"
		end
		old.session = nil
		return old, nil
	end)
	return ok, reason
end

return ProfileStore
