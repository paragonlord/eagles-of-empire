-- Grand campaign client logic against a real server view: string army ids, routes that obey the
-- server's movement, reachable provinces, readable reasons, offer terms and the turn summary.
local Shared = game:GetService("ReplicatedStorage").EoE
local Server = game:GetService("ServerScriptService").EoE
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.EoEClient
local EuropeData = require(Shared.EuropeData)
local GrandCampaign = require(Server.GrandCampaign)
local Movement = GrandCampaign.Movement
local Logic = require(Client.Campaign.Logic)

test("Grand client: routes from a real view match what the server accepts", function()
	local s = GrandCampaign.new(7, "france")
	local view = GrandCampaign.view(s)
	assertTrue(Logic.canAct(view), "player phase at the start")
	local tried = 0
	for id, a in view.armies do
		assertEq(type(id), "string", "army ids are strings")
		assertTrue(Logic.army(view, id) == a, "army lookup by id")
		if a.nation == "france" then
			for goal in Logic.reachable(view, a) do
				local r = Logic.route(view, a, goal) :: any
				assertEq(r[#r].id, goal, "route ends at the goal")
				local path = {}
				for _, step in r do
					table.insert(path, step.id)
				end
				local copy = GrandCampaign.deserialize(GrandCampaign.serialize(s))
				local ok, why, entered = Movement.move(copy, "france", a.id, path)
				assertTrue(ok, "server accepts " .. a.id .. " -> " .. goal .. ": " .. tostring(why))
				assertEq((entered :: any)[#(entered :: any)], goal, "reached this turn: " .. goal)
				tried += 1
			end
		end
	end
	assertTrue(tried > 0, "some French army can march")
end)

test("Grand client: reasons, terms, summary and phase gating read well", function()
	assertEq(Logic.reason("truce"), Logic.REASONS.truce)
	assertEq(Logic.reason("somethingNew"), "somethingNew")
	for _, code in { "refused", "truce", "notAtWar", "alreadyAtWar", "noCampaign" } do
		assertTrue(Logic.REASONS[code] ~= nil, "readable " .. code)
	end
	local text = Logic.offerText({ from = "austria", kind = "peace", terms = { winner = "france", loser = "austria", score = 45, provinces = { "venetia" }, dictated = false } })
	assertTrue(string.find(text, "French Empire prevails", 1, true) ~= nil, text)
	assertTrue(string.find(Logic.offerText({ from = "russia", kind = "peace", terms = { winner = "" } }), "white peace", 1, true) ~= nil)
	local lines = Logic.turnLines({ log = { EuropeData.dateOf(1) .. ": old", EuropeData.dateOf(2) .. ": Ulm falls" } }, 2)
	assertEq(#lines, 1)
	assertEq(lines[1], "Ulm falls")
	assertTrue(not Logic.canAct({ phase = "battle" }), "no orders during a battle")
	assertTrue(not Logic.canAct({ phase = "player", victory = { outcome = "draw" } }), "no orders after the end")
end)

test("Grand client: the battle prompt lists every army and takes odds from the totals", function()
	local view = {
		playerNation = "france",
		armies = {
			a1 = { id = "a1", nation = "france", name = "Grande Armée", men = 6040 },
			a2 = { id = "a2", nation = "france", name = "II Corps", men = 3560 },
			a3 = { id = "a3", nation = "austria", name = "Army of Italy", men = 13623 },
		},
	}
	local pb = { attacker = "a1", defender = "a3", attackerNation = "france", defenderNation = "austria", attackers = { "france" }, defenders = { "austria" }, odds = "even" }
	local att, def, odds = Logic.battleSides(view, pb)
	assertEq(#att.armies, 1, "lead army only without pb.armies")
	assertEq(odds, "poor", "6,040 v 13,623")
	pb.armies = { attacker = { "a1", "a2" }, defender = { "a3" } }
	att, def, odds = Logic.battleSides(view, pb)
	assertEq(#att.armies, 2)
	assertEq(att.men, 9600)
	assertEq(def.nation, "austria")
	assertEq(odds, "poor", "9,600 v 13,623 is still poor")
	pb.attackerMen, pb.defenderMen = 14000, 10000
	_, _, odds = Logic.battleSides(view, pb)
	assertEq(odds, "favourable", "server totals win")
	view.playerNation = "austria"
	_, _, odds = Logic.battleSides(view, pb)
	assertEq(odds, "poor", "odds from the player's side")
end)
