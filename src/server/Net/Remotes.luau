--!strict
-- Creates the RemoteEvents under ReplicatedStorage/EoE/Remotes (server only).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("EoE")
local Protocol = require(Shared.Protocol)

local Remotes = {}

function Remotes.create(): { [string]: RemoteEvent }
	local folder: Instance? = Shared:FindFirstChild("Remotes")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Remotes"
		f.Parent = Shared
		folder = f
	end
	local parent = folder :: Instance
	local out: { [string]: RemoteEvent } = {}
	for _, name in pairs(Protocol.Remotes :: { [string]: string }) do
		local r: Instance? = parent:FindFirstChild(name)
		if not r then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = parent
			r = e
		end
		out[name] = r :: RemoteEvent
	end
	return out
end

return Remotes
