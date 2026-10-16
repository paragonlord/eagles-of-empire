--!strict
-- Main menu over the live battlefield. Buttons call back into Main.

local Kit = require(script.Parent.Kit)

local Menu = {}

export type Callbacks = {
	play: () -> (),
	campaign: () -> (),
	help: () -> (),
	settings: () -> (),
}

local gui: ScreenGui? = nil
local campaignBtn: TextButton? = nil
local playBtn: TextButton? = nil
local note: TextLabel? = nil

function Menu.show(cb: Callbacks, isCommander: boolean, campaignAvailable: boolean)
	if not gui then
		local sg = Kit.screen("EoEMenu", 30)
		local panel = Kit.panel(sg, { size = UDim2.fromOffset(380, 400), position = UDim2.new(0, 48, 0.5, 0), anchor = Vector2.new(0, 0.5), padding = 24 })
		Kit.title(panel, "Eagles of Empire", { size = UDim2.new(1, 0, 0, 48), textSize = 40 })
		Kit.label(panel, "Napoleonic real-time tactics · Jena, 1806", { size = UDim2.new(1, 0, 0, 20), position = UDim2.new(0, 0, 0, 50), colour = Kit.MUTED })
		local list = Instance.new("Frame") :: Frame
		list.Size = UDim2.new(1, 0, 0, 200)
		list.Position = UDim2.new(0, 0, 0, 90)
		list.BackgroundTransparency = 1
		list.Parent = panel
		Kit.list(list, 8)
		playBtn = Kit.button(list, "Play Battle", cb.play, { size = UDim2.new(1, 0, 0, 40), primary = true, order = 1, textSize = 16 })
		campaignBtn = Kit.button(list, "Campaign", cb.campaign, { size = UDim2.new(1, 0, 0, 40), order = 2, textSize = 16 })
		Kit.button(list, "How to Command", cb.help, { size = UDim2.new(1, 0, 0, 40), order = 3, textSize = 16 })
		Kit.button(list, "Settings", cb.settings, { size = UDim2.new(1, 0, 0, 40), order = 4, textSize = 16 })
		note = Kit.label(panel, "", { size = UDim2.new(1, 0, 0, 40), position = UDim2.new(0, 0, 1, -44), wrap = true, colour = Kit.MUTED, textSize = 13 })
		gui = sg
	end
	if campaignBtn then
		campaignBtn.Visible = campaignAvailable
	end
	if playBtn then
		Kit.setEnabled(playBtn, isCommander, "Another player commands this battlefield; you are spectating.")
	end
	if note then
		note.Text = if isCommander then "WASD pan · Q/E rotate · wheel zoom · F1 help" else "Spectating: the commander controls the match."
	end
	if gui then
		gui.Enabled = true
	end
end

function Menu.hide()
	if gui then
		gui.Enabled = false
	end
end

function Menu.destroy()
	if gui then
		gui:Destroy()
		gui = nil
		campaignBtn = nil
		playBtn = nil
		note = nil
	end
end

return Menu
