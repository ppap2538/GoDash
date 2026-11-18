-- Emotes everyone can see (2026-11-19, owner: "ท่าทาง: ไหว้ เต้น ชูสองนิ้ว ถ่ายเซลฟี่").
-- Roblox's own emote animations (wave, dance, ...) are played by the rider's own client and replicate
-- by themselves. The Thai poses (wai, peace sign, selfie) are joint poses, and joint poses never
-- replicate, so the server only puts the pose on the character as attributes ("Emote", "EmoteAt") and
-- every client draws it (client/Emotes). The pose ends after HOLD seconds, when the rider moves (the
-- client sends ""), or when they sit down.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local City = require(script.Parent.CityRemote)

local Service = {}
local POSES = { wai = true, peace = true, selfie = true }
local HOLD = 8
local last = {} :: { [Player]: number }

local function set(char: Model, id: string?)
	char:SetAttribute("Emote", id)
	char:SetAttribute("EmoteAt", id and Workspace:GetServerTimeNow() or nil)
end

function Service.start()
	Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
	City.register("emote", function(player, arg)
		local char = player.Character
		if not char then return false, "" end
		local id = tostring(arg or "")
		if id == "" then
			set(char, nil)
			return true, ""
		end
		if not POSES[id] then return false, "" end
		if os.clock() - (last[player] or 0) < 0.6 then return false, "" end
		last[player] = os.clock()
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.SeatPart or hum.Health <= 0 then return false, "" end
		set(char, id)
		local at = char:GetAttribute("EmoteAt")
		task.delay(HOLD, function()
			if char.Parent and char:GetAttribute("EmoteAt") == at then set(char, nil) end
		end)
		return true, ""
	end)
end

return Service
