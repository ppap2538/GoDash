-- Energy, hunger, happiness, food buffs and resting. Ticks once a second on the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Game = require(Shared.Config.Game)
local Net = require(Shared.Net)
local Data = require(script.Parent.PlayerDataService)

local Lifestyle = {}
local resting = {} -- [player] = { pos, rate, happy, label }
local cooldown = {} -- [player] = { [key] = os.clock() }

local function clamp100(v: number): number
	return math.clamp(v, 0, 100)
end

function Lifestyle.hasBuff(player: Player, id: string): boolean
	local d = Data.get(player)
	if not d then return false end
	local b = d.buffs[id]
	return b ~= nil and b > os.time()
end

function Lifestyle.consume(player: Player, item)
	local d = Data.get(player)
	if not d then return end
	d.hunger = clamp100(d.hunger + (item.hunger or 0))
	d.energy = clamp100(d.energy + (item.energy or 0))
	d.happiness = clamp100(d.happiness + (item.happy or 0))
	if item.buff then
		d.buffs[item.buff.id] = os.time() + item.buff.seconds
		Data.touch(player, "buffs")
		Net.fire(player, "Notify", "toast", { text = "✨ " .. item.buff.name .. ": " .. item.buff.desc, good = true })
	end
	Data.touch(player, "hunger", "energy", "happiness")
end

function Lifestyle.add(player: Player, energy: number?, hunger: number?, happy: number?)
	local d = Data.get(player)
	if not d then return end
	if energy then d.energy = clamp100(d.energy + energy) end
	if hunger then d.hunger = clamp100(d.hunger + hunger) end
	if happy then d.happiness = clamp100(d.happiness + happy) end
	Data.touch(player, "hunger", "energy", "happiness")
end

-- Stay within 14 studs of `pos` to keep resting.
function Lifestyle.startRest(player: Player, pos: Vector3, rate: number, label: string, happyRate: number?)
	resting[player] = { pos = pos, rate = rate, label = label, happy = happyRate or 0 }
	player:SetAttribute("Resting", label)
	Net.fire(player, "Notify", "toast", { text = "😴 " .. label .. "… stay close to keep resting", good = true })
end

function Lifestyle.stopRest(player: Player)
	if resting[player] then
		resting[player] = nil
		player:SetAttribute("Resting", nil)
	end
end

-- One-off comfort actions (shower, TV) with a cooldown so they can't be spammed.
function Lifestyle.comfort(player: Player, key: string, happy: number, seconds: number, text: string): (boolean, string)
	local cd = cooldown[player]
	if not cd then cd = {}; cooldown[player] = cd end
	local now = os.clock()
	if cd[key] and now - cd[key] < seconds then
		return false, ("Wait %ds"):format(math.ceil(seconds - (now - cd[key])))
	end
	cd[key] = now
	Lifestyle.add(player, nil, nil, happy)
	Net.fire(player, "Notify", "toast", { text = text, good = true })
	return true, text
end

function Lifestyle.energy(player: Player): number
	local d = Data.get(player)
	return d and d.energy or 0
end

function Lifestyle.start()
	Players.PlayerRemoving:Connect(function(p) resting[p] = nil; cooldown[p] = nil end)
	local tick = 0
	task.spawn(function()
		while true do
			task.wait(1)
			tick += 1
			for _, player in ipairs(Players:GetPlayers()) do
				local d = Data.get(player)
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local rootPart = char and char:FindFirstChild("HumanoidRootPart")
				if d and hum and rootPart and hum.Health > 0 then
					local driving = hum.SeatPart ~= nil and hum.SeatPart:IsA("VehicleSeat")
					local drain = driving and Game.ENERGY_DRIVE_DECAY or Game.ENERGY_IDLE_DECAY
					if d.buffs.sugar and d.buffs.sugar > os.time() then drain *= 0.65 end
					d.hunger = clamp100(d.hunger - Game.HUNGER_DECAY)
					if d.hunger <= 0 then drain += Game.STARVING_ENERGY_DECAY end
					d.happiness = clamp100(d.happiness - Game.HAPPY_DECAY)
					local r = resting[player]
					if r then
						if (rootPart.Position - r.pos).Magnitude > 16 then
							Lifestyle.stopRest(player)
							Net.fire(player, "Notify", "toast", { text = "You stopped resting" })
						else
							d.energy = clamp100(d.energy + r.rate)
							if r.happy > 0 then d.happiness = clamp100(d.happiness + r.happy) end
							drain = 0
							if d.energy >= 100 then
								Lifestyle.stopRest(player)
								Net.fire(player, "Notify", "toast", { text = "⚡ Fully rested!", good = true })
							end
						end
					end
					d.energy = clamp100(d.energy - drain)
					d.stats.playSeconds += 1
					local weak = d.energy <= 5 or d.hunger <= 5
					hum.WalkSpeed = weak and 10 or 16
					for id, untilT in pairs(d.buffs) do
						if untilT <= os.time() then d.buffs[id] = nil; Data.touch(player, "buffs") end
					end
					if tick % 2 == 0 or r then Data.touch(player, "hunger", "energy", "happiness") end
					if tick % 30 == 0 then
						if d.hunger <= 12 then Net.fire(player, "Notify", "toast", { text = "🍜 You're hungry. Find something to eat!" })
						elseif d.energy <= 12 then Net.fire(player, "Notify", "toast", { text = "😪 You're exhausted. Rest at a bench or your bed." }) end
					end
				end
			end
		end
	end)
end

return Lifestyle
