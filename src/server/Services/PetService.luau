-- Adopted soi dogs (2026-11-19, Config/Pets). A rider walks up to a soi dog and adopts it (client/Pets asks;
-- City op "adopt" = "<dog id>,<name index>"): ฿300, the dog leaves the lane (server/DogService.adopt; a new
-- stray turns up there later) and is saved in d.pet. The player attribute "Pet" = "<look>|<name index>"
-- tells every client to draw it beside / in front of that rider; "" while it stays at home.
-- City op "pet_out" toggles taking it along.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pets = require(ReplicatedStorage.Shared.Config.Pets)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Lifestyle = require(script.Parent.LifestyleService)
local City = require(script.Parent.CityRemote)
local DogService = require(script.Parent.DogService)

local Service = {}

local function show(player: Player, d)
	local pet = d and d.pet
	if type(pet) == "table" and pet.out ~= false then
		player:SetAttribute("Pet", ("%d|%d"):format(pet.look or 1, pet.name or 1))
	else
		player:SetAttribute("Pet", "")
	end
end

function Service.start()
	Data.onLoaded(function(player, d) show(player, d) end)
	City.register("adopt", function(player, arg)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		local th = not (d.settings and d.settings.lang == "en")
		if type(d.pet) == "table" then return false, th and "คุณมีน้องหมาอยู่แล้ว" or "You already have a dog" end
		local id, ni = string.match(tostring(arg or ""), "^(%d+),(%d+)$")
		local nameIx = tonumber(ni)
		if not id or not nameIx or not Pets.NAMES[nameIx] then return false, "Bad request" end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum or hum.SeatPart then return false, th and "ลงจากรถก่อน แล้วเดินไปหาน้อง" or "Get off and walk up to the dog" end
		if (d.money or 0) < Pets.PRICE then
			return false, th and ("ค่าวัคซีน+ปลอกคอ ฿%d เงินสดไม่พอ"):format(Pets.PRICE) or ("Vaccines and a collar cost ฿%d"):format(Pets.PRICE)
		end
		local look = DogService.adopt and DogService.adopt(tonumber(id) :: number, root.Position)
		if not look then return false, th and "น้องวิ่งไปแล้ว ลองเดินเข้าไปใกล้ ๆ อีกที" or "The dog wandered off; walk closer" end
		if not Economy.spend(player, Pets.PRICE, "pet") then return false, "Not enough cash" end
		d.pet = { look = look, name = nameIx, out = true, since = os.time() }
		Data.touch(player, "pet")
		Lifestyle.add(player, nil, nil, 15)
		show(player, d)
		local n = Pets.NAMES[nameIx]
		return true, th and ("🐶 %s เป็นของคุณแล้ว! ความสุข +15"):format(n.th) or ("🐶 %s is yours! Happiness +15"):format(n.en)
	end)
	City.register("pet_out", function(player)
		local d = Data.get(player)
		if not d or type(d.pet) ~= "table" then return false, "" end
		d.pet.out = d.pet.out == false
		Data.touch(player, "pet")
		show(player, d)
		return true, ""
	end)
	Players.PlayerRemoving:Connect(function(p) p:SetAttribute("Pet", nil) end)
end

return Service
