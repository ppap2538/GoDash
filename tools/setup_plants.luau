-- Prepare the vegetation library inside the Roblox place (Studio command bar / MCP, Edit mode).
-- Run it once after uploading new plant models (ids in src/shared/Config/Plants.luau), then save the place.
--
-- For every plant: load the asset, give the "Leaves" mesh a SurfaceAppearance with a see-through
-- background (the importer only sets a plain texture, which draws each leaf card as a solid
-- rectangle), turn off the importer's double-sided flag (both sides are modelled already) and
-- store the model in ServerStorage.GoDashPlants. World/Assets clones them from there.
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local Plants = require(game:GetService("ReplicatedStorage").Shared.Config.Plants)

local MATTE = "rbxassetid://82837661040675" -- assets/textures/veg/rough_matte.png (plain white = fully rough)

local folder = ServerStorage:FindFirstChild("GoDashPlants")
if folder then folder:Destroy() end
folder = Instance.new("Folder")
folder.Name = "GoDashPlants"

local done, failed = 0, {}
for name, def in pairs(Plants) do
	local ok, res = pcall(function() return InsertService:LoadAsset(def.id) end)
	if ok and res then
		local model = res:FindFirstChildWhichIsA("Model") or res
		model.Name = name
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("MeshPart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				if d.Name == "Trunk" then
					local sa = Instance.new("SurfaceAppearance")
					sa.ColorMap = d.TextureID
					sa.RoughnessMap = MATTE
					sa.Parent = d
					d.TextureID = ""
				end
				if d.Name == "Leaves" then
					d.DoubleSided = false
					local sa = Instance.new("SurfaceAppearance")
					sa.ColorMap = d.TextureID
					sa.AlphaMode = Enum.AlphaMode.Transparency
					sa.RoughnessMap = MATTE -- leaves are matte: without this every crown gets a white highlight
					sa.Parent = d
					d.TextureID = ""
					d.RenderFidelity = Enum.RenderFidelity.Performance
				end
			end
		end
		model.Parent = folder
		done += 1
	else
		table.insert(failed, name .. ": " .. tostring(res))
	end
	task.wait()
end
folder.Parent = ServerStorage
game:GetService("ChangeHistoryService"):SetWaypoint("GoDash: vegetation library")
return ("%d plants ready in ServerStorage.GoDashPlants%s"):format(done, #failed > 0 and ("; FAILED: " .. table.concat(failed, " | ")) or "")
