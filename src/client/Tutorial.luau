--!strict
-- Interactive tutorial on the "tutorial" scenario: eleven lessons voiced by the aide-de-camp.
-- Each step names an objective, points at a HUD element or a spot on the ground, and completes
-- from real client state (selection, accepted orders in snapshots, formation shapes, events).
-- Entering step n sends Control "tutorialStep" n; the server releases the scripted enemy for
-- that lesson (MatchService). Finishing the last step sends the final step, which ends the
-- battle with the victory screen once Ebersdorf is held.

local Players = game:GetService("Players") :: Players
local RunService = game:GetService("RunService") :: RunService
local BattleState = require(script.Parent.BattleState)
local Selection = require(script.Parent.Selection)
local Camera = require(script.Parent.Camera)
local Net = require(script.Parent.Net)
local TutorialPanel = require(script.Parent.UI.TutorialPanel)

local Tutorial = {}

local SCENARIO = "tutorial"
local FINISH = 12 -- server step that ends the battle (MatchService TUTORIAL_FINAL)
local RELEASE = 11 -- server step that frees the enemy brigade (also sent by Skip tutorial)
local ADVANCE_DELAY = 1.6

type Vec = { x: number, z: number }
type Ctx = { t: number, seen: { [string]: boolean }, cam: { x: number, z: number, yaw: number, h: number }?, shapes: { [string]: boolean } }
type Step = {
	title: string,
	text: string,
	ui: ((ctx: Ctx?) -> GuiObject?)?,
	spot: (() -> (Vec?, number?))?,
	done: (ctx: Ctx) -> boolean,
}

-- ------------------------------------------------------------------ lookups

local function hud(): Instance?
	local pg = (Players.LocalPlayer :: Player):FindFirstChild("PlayerGui")
	return if pg then pg:FindFirstChild("EoEHUD") else nil
end

-- Command panel button by its caption (HUD upper-cases captions).
local function command(caption: string): (Ctx?) -> GuiObject?
	local want = string.upper(caption)
	return function(_: Ctx?): GuiObject?
		local h = hud()
		if not h then
			return nil
		end
		for _, d in h:GetDescendants() do
			if d:IsA("TextButton") and string.sub((d :: TextButton).Text, 1, #want) == want then
				return d :: TextButton
			end
		end
		return nil
	end
end

local function cards(_: Ctx?): GuiObject?
	local h = hud()
	local c = if h then h:FindFirstChild("CardBar", true) else nil
	return if c and c:IsA("GuiObject") then c :: GuiObject else nil
end

local function own(): { BattleState.Formation }
	return BattleState.ownFormations()
end

local function findNamed(name: string): Vec?
	for _, f in BattleState.formations do
		if f.name == name then
			return { x = f.x, z = f.z }
		end
	end
	for _, lk in BattleState.lastKnown do
		if lk.name == name then
			return { x = lk.x, z = lk.z }
		end
	end
	return nil
end

local function at(x: number, z: number, r: number): () -> (Vec?, number?)
	return function()
		return { x = x, z = z }, r
	end
end

local function near(name: string, fallback: Vec, r: number): () -> (Vec?, number?)
	return function()
		return findNamed(name) or fallback, r
	end
end

local function enemyCavalryNear(f: BattleState.Formation, radius: number): boolean
	for _, e in BattleState.formations do
		if e.faction ~= BattleState.viewerFaction and e.class == "cavalry" and (e.x - f.x) ^ 2 + (e.z - f.z) ^ 2 < radius * radius then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------------ the lessons

local STEPS: { Step } = {
	{
		title = "The field",
		text = "Mon général, survey the ground before committing a man. Pan with W A S D, turn the view with Q and E or the middle mouse, and zoom with the wheel.",
		spot = at(420, 330, 40),
		done = function(ctx: Ctx): boolean
			local c = ctx.cam
			if not c then
				return false
			end
			local x, z = Camera.getFocus()
			if (x - c.x) ^ 2 + (z - c.z) ^ 2 > 40 * 40 then
				ctx.seen.pan = true
			end
			if math.abs(Camera.getYaw() - c.yaw) > 0.3 then
				ctx.seen.rotate = true
			end
			if math.abs(Camera.height() - c.h) > 25 then
				ctx.seen.zoom = true
			end
			return ctx.seen.pan == true and ctx.seen.rotate == true and ctx.seen.zoom == true
		end,
	},
	{
		title = "Take command",
		text = "Each card below is a unit of the brigade. Left-click a battalion on the field, or its card, to select it.",
		ui = cards,
		done = function(): boolean
			return Selection.count() >= 1
		end,
	},
	{
		title = "March",
		text = "Right-click the ground to march the selection there. Right-drag instead to set its facing and the width of its front: the line forms along your stroke.",
		spot = at(320, 270, 30),
		done = function(): boolean
			for _, f in own() do
				-- a plain right-click marches without a facing (destHeading stays nil); the text
				-- offers right-drag only as an option, so a march order of either kind counts
				if f.dest then
					return true
				end
			end
			return false
		end,
	},
	{
		title = "The brigade moves as one",
		text = "Drag a box around several battalions, or shift-click them, then give a single order. Each keeps its place in the line as they march.",
		ui = cards,
		done = function(): boolean
			if Selection.count() < 2 then
				return false
			end
			local n = 0
			for _, id in Selection.ids() do
				local f = BattleState.formations[id]
				if f and f.dest then
					n += 1
				end
			end
			return n >= 2
		end,
	},
	{
		title = "Line, column, square",
		text = "The line gives every musket but marches slowly; the column is quick and strong with the bayonet, yet suffers under fire. The square stops cavalry dead and is a gift to the enemy guns: form a battalion into column, then into square.",
		ui = function(c: Ctx?): GuiObject?
			return command(if c and c.shapes.column then "Square" else "Column")(c)
		end,
		done = function(ctx: Ctx): boolean
			for _, f in own() do
				if f.class == "infantry" then
					ctx.shapes[f.shape] = true
				end
			end
			return ctx.shapes.column == true and ctx.shapes.square == true
		end,
	},
	{
		title = "Fire",
		text = "Grenzers hold the far side of the ridge: from its foot you cannot see them, nor they you. Advance a battalion in line to the crest; with fire at will it volleys once in range, then needs fifteen seconds to reload.",
		ui = command("Fire at will"),
		spot = at(420, 345, 45),
		done = function(ctx: Ctx): boolean
			return ctx.seen.volley == true
		end,
	},
	{
		title = "The guns",
		text = "Limber the battery, bring it up to the ridge and unlimber it there: guns fire only when deployed. Round shot carries 450 paces across the stream; canister, inside 120, sweeps a front like a scythe.",
		ui = command("Limber"),
		spot = at(480, 330, 35),
		done = function(ctx: Ctx): boolean
			return ctx.seen.cannon == true
		end,
	},
	{
		title = "The charge",
		text = "The Deutschmeister face west and show us their flank. Select the hussars, press Charge and right-click the battalion: a blow in the flank counts nearly double.",
		ui = command("Charge"),
		spot = near("IR 4 Hoch- und Deutschmeister", { x = 800, z = 430 }, 45),
		done = function(ctx: Ctx): boolean
			return ctx.seen.cavalryCharge == true
		end,
	},
	{
		title = "Cavalry!",
		text = "Austrian chevaulegers are crossing the Mühlbach at the gallop. Form square with the battalion they ride for: horsemen break on a square but cut a line to pieces.",
		ui = command("Square"),
		spot = near("Chevaulegers Nr. 3", { x = 620, z = 540 }, 40),
		done = function(): boolean
			for _, f in own() do
				if f.class == "infantry" and f.shape == "square" and enemyCavalryNear(f, 320) then
					return true
				end
			end
			return false
		end,
	},
	{
		title = "Steady the conscripts",
		text = "The conscripts have broken and run for the rear, and a routing unit takes no orders. Bring the general within 100 paces, select him and press Rally.",
		ui = command("Rally"),
		spot = near("Conscrits de 1809", { x = 270, z = 110 }, 35),
		done = function(ctx: Ctx): boolean
			return ctx.seen.rally == true
		end,
	},
	{
		title = "Ebersdorf",
		text = "Mon général, the enemy holds the village beyond the bridge, and the brigade is yours to command. Take Ebersdorf and keep it until the colours fly.",
		spot = at(620, 690, 60),
		done = function(): boolean
			for _, o in BattleState.objectives do
				if o.owner ~= BattleState.viewerFaction then
					return false
				end
			end
			return #BattleState.objectives > 0
		end,
	},
}

-- ------------------------------------------------------------------ progress

-- ponytail: progress lives for the session only (Roblox clients have no local disk); move it
-- to the server profile if players should resume across visits.
local furthest = 1
Tutorial.completed = false

local active = false
local matchId = ""
local index = 1
local ctx: Ctx = { t = 0, seen = {}, cam = nil, shapes = {} }
local doneAt: number? = nil
local uiTimer = 0
local conns: { any } = {}

local function enter(i: number)
	index = i
	furthest = math.max(furthest, i)
	ctx = { t = 0, seen = {}, cam = nil, shapes = {} }
	doneAt = nil
	uiTimer = 0
	local s = STEPS[i]
	TutorialPanel.setStep(i, #STEPS, s.title, s.text)
	TutorialPanel.highlight(nil)
	TutorialPanel.ring(nil, nil, nil, nil)
	Net.control("tutorialStep", i)
end

local function stop()
	if not active then
		return
	end
	active = false
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	TutorialPanel.hide()
end

local function advance()
	if index < #STEPS then
		enter(index + 1)
	else
		-- the server checks the village itself; resend later if it was not yet convinced
		Net.control("tutorialStep", FINISH)
		Tutorial.completed = true
		furthest = 1
		doneAt = os.clock() + 2
	end
end

local function skipAll()
	if index < RELEASE then
		Net.control("tutorialStep", RELEASE)
	end
	Tutorial.completed = true
	furthest = 1
	stop()
end

local function onEvent(ev: any)
	if ev.faction ~= BattleState.viewerFaction then
		return
	end
	ctx.seen[ev.kind] = true
	local f = if ev.id then BattleState.formations[ev.id] else nil
	if ev.kind == "charge" and f and f.class == "cavalry" then
		ctx.seen.cavalryCharge = true
	end
end

local function update(dt: number)
	if not active or BattleState.state ~= "running" then
		return
	end
	ctx.t += dt
	local s = STEPS[index]
	if not ctx.cam and ctx.t > 1 then
		local x, z = Camera.getFocus()
		ctx.cam = { x = x, z = z, yaw = Camera.getYaw(), h = Camera.height() }
	end
	if doneAt == nil and s.done(ctx) then
		doneAt = os.clock()
		TutorialPanel.setDone(if index == #STEPS then "Well done, mon général." else nil)
	elseif doneAt and os.clock() - doneAt > ADVANCE_DELAY then
		advance()
	end
	-- pointers: resolved twice a second (HUD lookups walk the tree)
	uiTimer -= dt
	if uiTimer <= 0 then
		uiTimer = 0.5
		local cur = STEPS[index]
		TutorialPanel.highlight(if cur.ui then cur.ui(ctx) else nil)
		if cur.spot then
			local p, r = cur.spot()
			if p then
				TutorialPanel.ring(p.x, Camera.groundHeight(p.x, p.z), p.z, r)
			end
		end
	end
	TutorialPanel.update(os.clock())
end

local function start()
	active = true
	matchId = BattleState.matchId
	TutorialPanel.show({
		skipStep = function()
			if index < #STEPS then
				advance()
			else
				skipAll()
			end
		end,
		skipAll = skipAll,
	})
	table.insert(conns, BattleState.event:Connect(onEvent))
	table.insert(conns, RunService.RenderStepped:Connect(update))
	enter(if furthest < RELEASE then furthest else 1)
end

-- Main calls this on every MatchState. The tutorial runs while a tutorial battle is in the
-- field (running or paused) and stands down on anything else; once finished or skipped it is
-- not forced again (e.g. on Restart) until the menu entry asks for it.
function Tutorial.onMatchState(state: string, scenarioId: string?)
	local inField = scenarioId == SCENARIO and (state == "running" or state == "paused")
	if active and (not inField or BattleState.matchId ~= matchId) then
		stop()
	end
	if inField and not active and not Tutorial.completed then
		start()
	end
end

-- The menu's Tutorial entry: an explicit request always runs the lessons, even after a skip.
function Tutorial.begin()
	Tutorial.completed = false
end

return Tutorial
