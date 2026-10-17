-- Co-op client state (docs/coop-contract.md): whose formations are whose, the vote label, and
-- that a solo or older server leaves everything as it was.
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local BattleState = require(Client.BattleState)

local function setup(msg: any)
	BattleState.reset()
	BattleState.userId = 11
	BattleState.applyMatchState(msg)
	BattleState.formations[1] = { id = 1, faction = "france" } :: any
	BattleState.formations[2] = { id = 2, faction = "france" } :: any
	BattleState.formations[3] = { id = 3, faction = "prussia" } :: any
	BattleState.formations[4] = { id = 4, faction = "france" } :: any -- unassigned
end

test("Co-op client: solo and old servers keep every own formation yours", function()
	setup({ matchId = "m", state = "running", viewerFaction = "france", isCommander = true })
	assertEq(BattleState.role, "commander", "role falls back to isCommander")
	assertTrue(not BattleState.coop(), "no player list: solo")
	assertTrue(BattleState.isMine(1) and BattleState.isMine(2) and BattleState.isMine(4), "all own formations")
	assertTrue(not BattleState.isMine(3), "never the enemy")
	assertEq(BattleState.pauseLabel(), nil, "plain pause button solo")
	assertEq(BattleState.allyOf(2), nil, "no allies solo")
	-- one player in the list, wings sent: still solo
	setup({ matchId = "m", state = "running", viewerFaction = "france", isCommander = true, role = "commander", players = { { userId = 11, name = "A", role = "commander", slot = 1 } }, controllers = { ["1"] = 11 } })
	assertTrue(BattleState.isMine(2), "solo ignores wings")
	assertEq(BattleState.pauseLabel(), nil)
end)

test("Co-op client: wings, commander reach and the vote label", function()
	local players = { { userId = 11, name = "A", role = "officer", slot = 2 }, { userId = 22, name = "B", role = "commander", slot = 1 }, { userId = 33, name = "C", role = "spectator" } }
	setup({ matchId = "m", state = "running", viewerFaction = "france", isCommander = false, role = "officer", players = players, controllers = { ["1"] = 11, ["2"] = 22 }, pauseVotes = 1, pauseNeeded = 1 })
	assertTrue(BattleState.coop() and BattleState.canOrder())
	assertTrue(BattleState.isMine(1) and BattleState.canCommand(1), "own wing")
	assertTrue(not BattleState.isMine(2) and not BattleState.canCommand(2), "ally's wing")
	assertTrue(not BattleState.canCommand(4), "unassigned stays with the commander")
	assertEq(BattleState.allyOf(2).name, "B")
	assertEq(BattleState.pauseLabel(), "Vote pause (1/1)", "spectators hold no vote")
	-- the commander may command every own formation, but only their wing is "mine"
	BattleState.userId = 22
	BattleState.role = "commander"
	BattleState.state = "paused"
	assertTrue(BattleState.canCommand(1) and not BattleState.isMine(1), "commander reaches an ally's wing")
	assertTrue(BattleState.isMine(4), "unassigned is the commander's")
	assertTrue(not BattleState.canCommand(3), "never the enemy")
	BattleState.pauseNeeded = 0
	BattleState.pauseVotes = 0
	assertEq(BattleState.pauseLabel(), "Vote resume (0/1)", "need falls back to ceil(n/2)")
	BattleState.reset()
	BattleState.applyMatchState({ matchId = "", state = "menu" })
end)
