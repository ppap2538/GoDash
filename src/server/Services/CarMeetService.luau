-- Night car meet at the KK Plaza car park (2026-11-19, TikTok toys "มีตติ้งรถซิ่งกลางคืน").
-- From 20:30 to 02:00 game time tuned cars and bikes stand in the car park bays with their underglow on,
-- a lit banner and a speaker stack by the entrance: a place to bring your own styled ride and film it.
-- Everyone online hears about it once a night (a toast). Built at dusk, removed in the morning, nothing
-- moves: anchored display copies (VehicleFactory.display + Factory.style).
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Vehicles = require(ReplicatedStorage.Shared.Config.Vehicles)
local Net = require(ReplicatedStorage.Shared.Net)
local World = script.Parent.Parent.World
local Kit = require(World.Kit)
local Factory = require(World.VehicleFactory)

local Service = {}
local V3, CF = Vector3.new, CFrame.new
local SHOW = { "super_gt", "raptor300", "lux_e300", "zoomer125", "sedan_vios", "titan650", "pickup_dmax", "raptor300", "eco_city", "suv_fortune", "zoomer125", "super_gt" }
local FROM, TO = 20.5, 2 -- game clock

local folder: Model? = nil

local function isOn(clock: number): boolean
	return clock >= FROM or clock < TO
end

local function freeGlows(): { number }
	local out = {}
	for i, g in ipairs(Vehicles.GLOWS) do
		if not g.need then table.insert(out, i) end
	end
	return out
end

local function build(mall)
	local base, w, d = mall.base, mall.w, mall.d
	local m = Instance.new("Model")
	m.Name = "NightMeet"
	local rng = Random.new(1119)
	local glows = freeGlows()
	-- the car park bays (Places.mall: lines every 12 studs, bays 18 deep at z = -d/2 + 14)
	local x = -w / 2 + 20
	local n = 0
	while x < w / 2 - 20 and n < #SHOW do
		n += 1
		local def = Vehicles.ById[SHOW[n]]
		if def then
			local y = 0.3 + def.wheelR + 0.9
			local cf = base * CF(x, y, -d / 2 + 14) * CFrame.Angles(0, (n % 2 == 0) and math.pi or 0, 0)
			local ok, car = pcall(Factory.display, def, cf, rng:NextInteger(1, 8))
			if ok and car then
				local style = { glow = #glows > 0 and glows[rng:NextInteger(1, #glows)] or 0, sticker = rng:NextInteger(0, #Vehicles.STICKERS),
					plate = Vehicles.plateText(rng:NextInteger(1, #Vehicles.PLATE_WORDS), Vehicles.PLATE_LUCKY[rng:NextInteger(1, #Vehicles.PLATE_LUCKY)]) }
				car:SetAttribute("PlateText", style.plate)
				pcall(Factory.style, car, def, { style = style }, 0)
				for _, p in ipairs(car:GetDescendants()) do
					if p:IsA("BasePart") then p.Anchored = true end
				end
				car.Name = "Meet_" .. def.id
				car.Parent = m
			end
		end
		x += 24
	end
	-- banner on two poles behind the parked cars (at the car park entrance it stood in a bus stop), and a
	-- speaker stack beside it
	local front = base * CF(0, 0, -d / 2 + 25)
	for _, sx in ipairs({ -15, 15 }) do Kit.cyl(m, 0.8, 13, front * CF(sx, 6.5, 0), Color3.fromRGB(30, 30, 34), Kit.M.Metal, {}) end
	local board = Kit.part(m, V3(32, 4.4, 0.5), front * CF(0, 12, 0), Color3.fromRGB(110, 30, 160), Kit.M.SmoothPlastic, { decor = true })
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		Kit.sign(board, "มีตติ้งรถซิ่ง ทุกคืน", { sub = "KK NIGHT MEET · 20:30-02:00", bg = Color3.fromRGB(110, 30, 160), color = Color3.fromRGB(255, 230, 120), face = face, light = true, maxDistance = 700, pps = 14 })
	end
	Kit.nightGlow(board)
	local spk = front * CF(22, 0, 0)
	for i = 0, 1 do
		local box = Kit.part(m, V3(4, 4.4, 3.6), spk * CF(0, 2.2 + i * 4.4, 0), Color3.fromRGB(24, 24, 28), Kit.M.SmoothPlastic, {})
		for _, cy in ipairs({ -1, 1 }) do
			local cone = Kit.cyl(m, 2.2, 0.3, box.CFrame * CF(0, cy * 1, -1.85) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(60, 60, 66), Kit.M.Metal, { decor = true })
			Kit.nightGlow(cone)
		end
	end
	m.Parent = Workspace
	return m
end

function Service.start(world, deps)
	local mall
	for _, p in pairs(world.pois or {}) do
		if p.kind == "mall" and p.base then mall = p break end
	end
	if not mall then
		warn("[CarMeet] no mall on the map")
		return
	end
	local time = deps and deps.time
	local toldNight = -1
	task.spawn(function()
		while true do
			local clock = time and time.clock() or game:GetService("Lighting").ClockTime
			local on = isOn(clock)
			if on and not folder then
				local ok, res = pcall(build, mall)
				if ok then folder = res else warn("[CarMeet] " .. tostring(res)) end
				-- tell everyone once a night
				local day = Workspace:GetAttribute("Day") or 0
				if toldNight ~= day then
					toldNight = day
					for _, p in ipairs(Players:GetPlayers()) do
						Net.fire(p, "Notify", "toast", { text = "🚗 Night car meet now at the KK Plaza car park: bring your styled ride!",
							th = "🚗 คืนนี้มีตติ้งรถซิ่งที่ลานจอด KK Plaza แต่งรถแล้วมาโชว์กัน!", good = true })
					end
				end
			elseif not on and folder then
				folder:Destroy()
				folder = nil
			end
			task.wait(5)
		end
	end)
	Workspace:SetAttribute("CarMeetAt", (mall.base * CF(0, 0, -mall.d / 2 + 14)).Position)
end

return Service
