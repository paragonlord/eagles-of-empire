--!strict
-- Historical commanders: two traits (small, always-on number changes) and one active ability.
-- Pure data plus name lookups; the sim applies it in src/server/Sim/Abilities.luau and
-- docs/rules.md ("Generals") is the contract. Every effect is described in its `text`, which the
-- client shows verbatim, so nothing a general does is hidden from the player.
--
-- Trait scope: "local" = friendly formations within Generals.TraitRadius of the HQ when he commands
-- it, or the formations of his corps when the corps name names him (e.g. "V Corps · Lannes");
-- "army" = every formation of the faction (an HQ general's HQ must be in the field; a corps
-- general's army trait only reaches his corps).
-- Trait mods: multipliers speed / chargeImpact / chargeRecovery / accuracy / melee; additive
-- cover / recovery (morale per second); shockFloor (casualty shock cannot push morale below it);
-- hideBeyond (enemies cannot spot it from further away); steadyRetreat (no cohesion loss on Retreat).
-- `when`: "advancing" (moving toward the enemy) or "crest" (infantry halted behind a crest).

export type Mods = { [string]: number | boolean }
export type Trait = { id: string, name: string, text: string, scope: "local" | "army", classes: { [string]: boolean }?, when: string?, mods: Mods }
export type Ability = { id: string, name: string, kind: string, text: string, cooldown: number, radius: number, duration: number? }
export type General = { id: string, name: string, nation: string, rank: string, match: { string }, traits: { Trait }, ability: Ability }

local Generals = {}

Generals.TraitRadius = 200 -- influence traits reach this far from the HQ
Generals.CrestLook = { 30, 60 } -- studs ahead sampled for a crest
Generals.CrestRise = 1.5 -- ground ahead must be at least this much higher
Generals.HiddenRange = 120 -- reverse-slope infantry is only spotted inside this distance

local INF = { infantry = true }
local CAV = { cavalry = true }
local GUNS = { artillery = true }

local function t(id: string, name: string, scope: "local" | "army", mods: Mods, text: string, classes: { [string]: boolean }?, when: string?): Trait
	return { id = id, name = name, text = text, scope = scope, classes = classes, when = when, mods = mods }
end

local INSPIRE: Ability = { id = "inspire", name = "Inspire", kind = "inspire", cooldown = 120, radius = 150, text = "+10 morale to every formation within 150 that is not routing. Recharges in 120 s." }

local function inspire(): Ability
	return table.clone(INSPIRE)
end

local LIST: { General } = {
	-- France
	{ id = "napoleon", name = "Napoléon", nation = "france", rank = "Emperor", match = { "napol" },
		traits = {
			t("emperor", "The Emperor's presence", "local", { recovery = 0.2 }, "+0.2 morale recovered per second."),
			t("grandbattery", "Grande batterie", "local", { accuracy = 1.1 }, "Batteries hit 10% more often.", GUNS),
		},
		ability = { id = "vive", name = "Vive l'Empereur!", kind = "vive", cooldown = 180, radius = 200, text = "Every routing (not shattered) formation within 200 rallies at once, and every formation within 200 gains +20 morale. Recharges in 180 s." } },
	{ id = "davout", name = "Davout", nation = "france", rank = "Marshal", match = { "davout" },
		traits = {
			t("ironmarshal", "Iron Marshal", "local", { shockFloor = 25 }, "Casualties alone never push morale below 25 (shaken, never routing). Flank attacks and routing friends still can."),
			t("drill", "Drill-master", "local", { accuracy = 1.05 }, "Muskets hit 5% more often."),
		},
		ability = { id = "holdline", name = "Hold the line", kind = "holdline", cooldown = 150, radius = 150, duration = 45, text = "For 45 s, formations within 150 cannot rout unless below 30% strength (morale stops at 20). Recharges in 150 s." } },
	{ id = "lannes", name = "Lannes", nation = "france", rank = "Marshal", match = { "lannes" },
		traits = {
			t("roland", "Roland of the army", "local", { melee = 1.1 }, "+10% melee."),
			t("vanguard", "Advance guard", "local", { speed = 1.05 }, "Marches 5% faster."),
		},
		ability = inspire() },
	{ id = "ney", name = "Ney", nation = "france", rank = "Marshal", match = { "%f[%a]ney%f[%A]" },
		traits = {
			t("bravest", "Bravest of the Brave", "local", { chargeImpact = 1.15, accuracy = 0.9 }, "+15% cavalry charge impact, but −10% musket accuracy (impetuous, poor fire discipline)."),
			t("rougeaud", "Le Rougeaud", "local", { recovery = 0.15 }, "+0.15 morale recovered per second."),
		},
		ability = { id = "charge", name = "Charge!", kind = "charge", cooldown = 120, radius = 200, duration = 30, text = "For 30 s, cavalry within 200 hits ×1.3 harder in the charge. Recharges in 120 s." } },
	{ id = "soult", name = "Soult", nation = "france", rank = "Marshal", match = { "soult" },
		traits = {
			t("tactician", "First tactician of Europe", "local", { speed = 1.05 }, "Marches 5% faster."),
			t("pratzen", "Storm of the Pratzen", "local", { melee = 1.05 }, "+5% melee."),
		},
		ability = inspire() },
	{ id = "murat", name = "Murat", nation = "france", rank = "Marshal", match = { "murat" },
		traits = {
			t("sabreur", "Beau sabreur", "local", { chargeRecovery = 0.75 }, "Cavalry is ready to charge again 25% sooner.", CAV),
			t("panache", "Panache", "local", { chargeImpact = 1.1 }, "Cavalry charges 10% harder.", CAV),
		},
		ability = inspire() },
	{ id = "bessieres", name = "Bessières", nation = "france", rank = "Marshal", match = { "bessi" },
		traits = {
			t("guardsman", "Commander of the Guard", "local", { recovery = 0.15 }, "+0.15 morale recovered per second."),
			t("reserve", "Cavalry of the reserve", "local", { chargeRecovery = 0.85 }, "Cavalry is ready to charge again 15% sooner.", CAV),
		},
		ability = inspire() },
	{ id = "bernadotte", name = "Bernadotte", nation = "france", rank = "Marshal", match = { "bernadotte" },
		traits = {
			t("prudent", "Prudent", "local", { recovery = 0.15 }, "+0.15 morale recovered per second."),
			t("late", "Late to the field", "local", { speed = 0.95 }, "Marches 5% slower."),
		},
		ability = inspire() },
	{ id = "augereau", name = "Augereau", nation = "france", rank = "Marshal", match = { "augereau" },
		traits = {
			t("castiglione", "Old soldier of Castiglione", "local", { melee = 1.1 }, "+10% melee."),
			t("enfant", "Child of the people", "local", { recovery = 0.1 }, "+0.1 morale recovered per second."),
		},
		ability = inspire() },
	-- Austria
	{ id = "charles", name = "Archduke Charles", nation = "austria", rank = "Generalissimus", match = { "archduke charles", "erzherzog carl", "erzherzog karl" },
		traits = {
			t("aspern", "Victor of Aspern", "local", { recovery = 0.2 }, "+0.2 morale recovered per second."),
			t("reformer", "Reformer", "local", { accuracy = 1.05 }, "Infantry hits 5% more often.", INF),
		},
		ability = { id = "example", name = "Personal example", kind = "example", cooldown = 90, radius = 200, text = "The nearest routing (not shattered) formation within 200 rallies at once with at least 45 morale; if none is routing, the nearest shaken one gains +20 morale. Recharges in 90 s." } },
	{ id = "mack", name = "Mack", nation = "austria", rank = "Feldmarschall-Leutnant", match = { "%f[%a]mack%f[%A]" },
		traits = {
			t("theorist", "Staff theorist", "local", { accuracy = 1.05 }, "Infantry hits 5% more often.", INF),
			t("ulm", "Unlucky at Ulm", "army", { speed = 0.95 }, "Marches 5% slower."),
		},
		ability = inspire() },
	{ id = "schwarzenberg", name = "Schwarzenberg", nation = "austria", rank = "Feldmarschall", match = { "schwarzenberg" },
		traits = {
			t("coalition", "Coalition commander", "local", { recovery = 0.15 }, "+0.15 morale recovered per second."),
			t("methodical", "Methodical", "army", { speed = 0.95 }, "Marches 5% slower."),
		},
		ability = inspire() },
	-- Russia
	{ id = "kutuzov", name = "Kutuzov", nation = "russia", rank = "General of Infantry", match = { "kutuzov" },
		traits = {
			t("steady", "Steady retreats", "army", { steadyRetreat = true }, "No cohesion lost when ordered to Retreat."),
			t("oldfox", "Old fox of the north", "local", { recovery = 0.15 }, "+0.15 morale recovered per second."),
		},
		ability = { id = "withdraw", name = "Strategic withdrawal", kind = "withdraw", cooldown = 180, radius = 250, text = "Every routing (not shattered) formation within 250 rallies at once, then falls back 200 toward your own edge. Recharges in 180 s." } },
	{ id = "bagration", name = "Bagration", nation = "russia", rank = "Lieutenant-General", match = { "bagration" },
		traits = {
			t("lion", "Lion of the army", "local", { melee = 1.1 }, "+10% melee."),
			t("rearguard", "Rearguard fighter", "local", { recovery = 0.15 }, "+0.15 morale recovered per second."),
		},
		ability = inspire() },
	{ id = "buxhowden", name = "Buxhöwden", nation = "russia", rank = "General of Infantry", match = { "buxh" },
		traits = {
			t("plodding", "Plodding", "local", { speed = 0.95 }, "Marches 5% slower."),
			t("stubborn", "Stubborn", "local", { shockFloor = 22 }, "Casualties alone never push morale below 22."),
		},
		ability = inspire() },
	-- Prussia
	{ id = "brunswick", name = "Brunswick", nation = "prussia", rank = "Feldmarschall", match = { "brunswick", "braunschweig" },
		traits = {
			t("frederician", "Frederician drill", "local", { accuracy = 1.05 }, "Infantry hits 5% more often.", INF),
			t("hesitant", "Hesitant", "army", { speed = 0.95 }, "Marches 5% slower."),
		},
		ability = inspire() },
	{ id = "hohenlohe", name = "Hohenlohe", nation = "prussia", rank = "General der Infanterie", match = { "hohenlohe" },
		traits = {
			t("parade", "Parade-ground lines", "local", { accuracy = 1.05 }, "Infantry hits 5% more often.", INF),
			t("concentrate", "Slow to concentrate", "army", { speed = 0.95 }, "Marches 5% slower."),
		},
		ability = inspire() },
	{ id = "blucher", name = "Blücher", nation = "prussia", rank = "Feldmarschall", match = { "blücher", "blucher", "bluecher" },
		traits = {
			t("vorwarts", "Marschall Vorwärts", "local", { speed = 1.1, recovery = 0.3 }, "While advancing toward the enemy: marches 10% faster and recovers +0.3 morale per second.", nil, "advancing"),
			t("hussar", "Old hussar", "local", { chargeImpact = 1.1 }, "Cavalry charges 10% harder.", CAV),
		},
		ability = { id = "vorwaerts", name = "Vorwärts!", kind = "vorwaerts", cooldown = 150, radius = 200, duration = 60, text = "Formations within 200 gain +10 morale at once and, for 60 s, march 20% faster and recover +0.3 morale per second. Recharges in 150 s." } },
	-- Britain
	{ id = "wellington", name = "Wellington", nation = "britain", rank = "Field Marshal", match = { "wellington" },
		traits = {
			t("reverse", "Reverse slope", "local", { cover = 0.15, hideBeyond = 120 }, "Infantry halted behind a crest (ground ahead rises): +15% cover, and the enemy cannot see it beyond 120 until it fires.", INF, "crest"),
			t("peninsula", "Peninsula drill", "local", { accuracy = 1.05 }, "Infantry hits 5% more often.", INF),
		},
		ability = { id = "upguards", name = "Up, Guards, and at 'em!", kind = "upguards", cooldown = 180, radius = 250, duration = 12, text = "Infantry within 250 that is halted behind a crest rises: muskets reloaded at once, fire at will on, and +50% accuracy for 12 s. Recharges in 180 s." } },
	{ id = "uxbridge", name = "Uxbridge", nation = "britain", rank = "Lieutenant-General", match = { "uxbridge" },
		traits = {
			t("cavcommander", "Cavalry commander", "local", { chargeImpact = 1.1 }, "Cavalry charges 10% harder.", CAV),
			t("pursuit", "Reckless pursuit", "local", { chargeRecovery = 1.15 }, "Cavalry takes 15% longer to be ready to charge again.", CAV),
		},
		ability = inspire() },
	{ id = "picton", name = "Picton", nation = "britain", rank = "Lieutenant-General", match = { "picton" },
		traits = {
			t("fighting", "Fighting general", "local", { melee = 1.1 }, "+10% melee."),
			t("hard", "Hard as nails", "local", { recovery = 0.15 }, "+0.15 morale recovered per second."),
		},
		ability = inspire() },
}

-- Any HQ without a named commander.
Generals.generic = { id = "generic", name = "Staff", nation = "", rank = "General", match = {}, traits = {}, ability = inspire() } :: General

Generals.list = LIST
Generals.byId = {} :: { [string]: General }
for _, g in LIST do
	Generals.byId[g.id] = g
end
Generals.byId.generic = Generals.generic

local function matches(g: General, text: string): boolean
	local s = string.lower(text)
	for _, pat in g.match do
		if string.find(s, pat) then
			return true
		end
	end
	return false
end

-- General commanding an HQ: the explicit id on the unit definition, else matched from its name.
function Generals.forHQ(name: string, explicit: string?): General
	if explicit and Generals.byId[explicit] then
		return Generals.byId[explicit]
	end
	for _, g in LIST do
		if matches(g, name) then
			return g
		end
	end
	return Generals.generic
end

-- Corps commander named in a formation's corps string ("V Corps · Lannes" -> Lannes), or nil.
-- Only the part after "·" names commanders, so "Garde Impériale" or "HQ" never match.
function Generals.corpsGeneral(corps: string): General?
	local _, dot = string.find(corps, "·", 1, true)
	if not dot then
		return nil
	end
	local tail = string.sub(corps, dot + 1)
	for _, g in LIST do
		if matches(g, tail) then
			return g
		end
	end
	return nil
end

-- Full plain-text description shown in tooltips: name, effect, reach.
function Generals.describe(tr: Trait): string
	local reach = if tr.scope == "army" then "the whole army" else string.format("formations within %d of his HQ, or his corps", Generals.TraitRadius)
	return string.format("%s: %s (Applies to %s.)", tr.name, tr.text, reach)
end

function Generals.trait(id: string): Trait?
	for _, g in LIST do
		for _, tr in g.traits do
			if tr.id == id then
				return tr
			end
		end
	end
	return nil
end

return Generals
