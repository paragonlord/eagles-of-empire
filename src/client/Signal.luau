--!strict
-- Minimal synchronous signal. Handlers run in order; a handler error is reported, not fatal.

export type Connection = { Disconnect: (self: Connection) -> () }
export type Handler = (...any) -> ()

local Signal = {}
Signal.__index = Signal

export type Signal = typeof(setmetatable({} :: { _handlers: { Handler } }, Signal))

function Signal.new(): Signal
	return setmetatable({ _handlers = {} :: { Handler } }, Signal)
end

-- `fn` is loosely typed on purpose: handlers declare only the arguments they use.
function Signal.Connect(self: Signal, fn: any): Connection
	local handlers = self._handlers
	table.insert(handlers, fn :: Handler)
	return {
		Disconnect = function(_self: Connection)
			local i = table.find(handlers, fn)
			if i then
				table.remove(handlers, i)
			end
		end,
	}
end

function Signal.Fire(self: Signal, ...: any)
	-- copy so handlers may disconnect while firing
	for _, fn in table.clone(self._handlers) do
		local ok, err = (pcall :: any)(fn, ...)
		if not ok then
			warn("[EoE] signal handler error: " .. tostring(err))
		end
	end
end

function Signal.DisconnectAll(self: Signal)
	table.clear(self._handlers)
end

return Signal
