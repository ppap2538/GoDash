-- Thai street life built by the server (owner, 2026-11-17: "reflect Thai society, satire, funny"):
--   * roadworks that never end: barriers and cones over the kerb lane, a sand pile, a worker asleep
--     under a beach umbrella, and the sign "sorry for the inconvenience · started Jan 2016 · done ???"
--   * campaign posters of made-up candidates with made-up promises ("good roads in every soi, within
--     this lifetime"). Fictional people and groups only: no real politicians or parties.
--   * motorbike-taxi stands (วินมอไซค์) by the market, night market, station and university: riders in
--     orange vests and a boss. Picking up a ride passenger on their turf without being a member of the
--     stand costs part of the tip; members get a bonus. Joining: bring the boss an iced coffee.
--   * municipal officers (เทศกิจ) on the busy pavements: ride a motor vehicle on the pavement near one
--     and you hear the whistle and pay ฿100 (away from them, the pavement is still a way round a checkpoint)
--   * Songkran: every 25-40 minutes five minutes of water fights on the main roads, fares +30%
--     (Workspace attribute Songkran = end time; client/StreetLife draws the splashing)
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local RiderPose = require(Shared.RiderPose)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Fines = require(script.Parent.FineService)
local Kit = require(script.Parent.Parent.World.Kit)

local Street = {}
local V3, CF = Vector3.new, CFrame.new
local rad = math.rad
local M = Enum.Material
local rng = Random.new()
local ORANGE = Color3.fromRGB(255, 120, 20)
local WHITE = Color3.fromRGB(245, 245, 240)
local stands = {} -- { pos, name, thai, boss = Vector3 }
local officers = {} -- { pos }
local ROAD_Y = 0.24

local function toast(player: Player, en: string, th: string, bad: boolean?)
	Net.fire(player, "Notify", "toast", { text = en, th = th, bad = bad, good = not bad })
end
local function say(player: Player, pos: Vector3, name: string, en: string, th: string)
	Net.fire(player, "Dialogue", { pos = pos, name = name, text = en, th = th })
end

-- a road-side spot: the road edge beside pos and the direction across the road (out of the road)
local function roadside(graph, pos: Vector3, extra: number): (CFrame?, any)
	local e, p = graph:nearest(pos)
	if not e then return nil end
	local out = V3(pos.X - p.X, 0, pos.Z - p.Z)
	if out.Magnitude < 0.5 then out = (V3(e.b.pos.X - e.a.pos.X, 0, e.b.pos.Z - e.a.pos.Z)):Cross(Vector3.yAxis) end
	out = out.Unit
	local at = V3(p.X, ROAD_Y, p.Z) + out * (e.def.width / 2 + extra)
	return CFrame.lookAt(at, at - out), e -- faces the road
end

local function cone(parent: Instance, cf: CFrame)
	Kit.cyl(parent, 0.95, 0.75, cf * CF(0, 0.45, 0), ORANGE, M.SmoothPlastic)
	Kit.cyl(parent, 0.75, 0.3, cf * CF(0, 0.97, 0), WHITE, M.SmoothPlastic, { decor = true })
	Kit.cyl(parent, 0.5, 0.7, cf * CF(0, 1.45, 0), ORANGE, M.SmoothPlastic, { decor = true })
end

local function sign(parent: Instance, cf: CFrame, w: number, h: number, bg: Color3, text: string, sub: string?, color: Color3?)
	for _, sx in ipairs({ -w / 2 + 0.2, w / 2 - 0.2 }) do
		Kit.part(parent, V3(0.18, 2.4 + h, 0.18), cf * CF(sx, (2.4 + h) / 2, 0.06), Color3.fromRGB(70, 70, 74), M.Metal, { decor = true })
	end
	local board = Kit.part(parent, V3(w, h, 0.15), cf * CF(0, 2.4 + h / 2, 0), bg, M.SmoothPlastic, { decor = true })
	board.CanQuery = true
	Kit.sign(board, text, { face = Enum.NormalId.Front, bg = bg, sub = sub, color = color or Color3.new(0, 0, 0), light = true, pps = 36 })
	return board
end

local function person(parent: Instance, npc, cf: CFrame, pose: string, shirt: Color3?, trousers: Color3?)
	local names = npc.pedNames()
	if #names == 0 then return nil end
	local fig = npc.figure(cf, names[rng:NextInteger(1, #names)], pose)
	if not fig then return nil end
	if shirt then RiderPose.dress(fig.model, shirt, trousers or Color3.fromRGB(40, 40, 46)) end
	fig.model.Parent = parent
	return fig.model
end

---------------------------------------------------------------------------------------------------
-- builders
---------------------------------------------------------------------------------------------------
local function roadworks(folder: Instance, npc, e, k: number)
	local a, b = e.a.pos, e.b.pos
	local dir = V3(b.X - a.X, 0, b.Z - a.Z).Unit
	local mid = a:Lerp(b, 0.5)
	local side = dir:Cross(Vector3.yAxis)
	local half = e.def.width / 2
	local base = CFrame.lookAt(V3(mid.X, ROAD_Y, mid.Z), V3(mid.X, ROAD_Y, mid.Z) + dir) -- local X = side
	local m = Instance.new("Model")
	m.Name = "Roadworks" .. k
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local x0 = half - 2.2 -- the kerb lane, outer part
	for z = -14, 14, 3.5 do cone(m, base * CF(x0 - 1.6, 0, z)) end
	for _, z in ipairs({ -10, 10 }) do
		-- red-white water barriers
		for i = 0, 1 do
			Kit.part(m, V3(1.2, 1.6, 2.6), base * CF(x0 + 0.2, 0.8, z + i * 2.7), i == 0 and Color3.fromRGB(210, 40, 36) or WHITE, M.SmoothPlastic)
		end
	end
	-- the hole nobody has filled, and a sand pile
	Kit.part(m, V3(2.6, 0.06, 5), base * CF(x0, 0.03, -2), Color3.fromRGB(46, 40, 34), M.Slate, { decor = true })
	Kit.wedge(m, V3(2.4, 1.6, 2.4), base * CF(x0 + 0.2, 0.8, 4) * CFrame.Angles(0, rad(90), 0), Color3.fromRGB(196, 168, 112), M.Sand)
	Kit.wedge(m, V3(2.4, 1.6, 2.4), base * CF(x0 + 0.2, 0.8, 6.4) * CFrame.Angles(0, rad(-90), 0), Color3.fromRGB(196, 168, 112), M.Sand)
	-- the sign
	sign(m, base * CF(half + 1.2, 0, -16) * CFrame.Angles(0, rad(180), 0), 5.6, 2.8, Color3.fromRGB(255, 205, 40),
		"ขออภัยในความไม่สะดวก", "กำลังปรับปรุงผิวจราจร · เริ่ม ม.ค. 2559 · เสร็จ ???")
	-- the worker, asleep under a beach umbrella
	local u = base * CF(half + 3.2, 0, 2)
	Kit.cyl(m, 0.14, 4.4, u * CF(0, 2.2, 0), Color3.fromRGB(200, 200, 204), M.Metal, { decor = true })
	Kit.cyl(m, 5.2, 0.25, u * CF(0, 4.3, 0), Color3.fromRGB(230, 70, 60), M.Fabric, { decor = true })
	Kit.cyl(m, 3.2, 0.3, u * CF(0, 4.55, 0), WHITE, M.Fabric, { decor = true })
	Kit.part(m, V3(1.6, 0.9, 1.6), u * CF(0.6, 0.45, 0.6), Color3.fromRGB(60, 120, 200), M.SmoothPlastic, { decor = true }) -- cool box
	person(m, npc, u * CF(-0.4, 0, 0.4) * CFrame.Angles(0, rad(150), 0), "sit", ORANGE, Color3.fromRGB(60, 70, 90))
	m.Parent = folder
end

local CANDIDATES = {
	{ "99", "นายสมหวัง ตั้งใจดี", "ถนนดีทุกซอย ภายในชาตินี้", "😁", Color3.fromRGB(30, 110, 200) },
	{ "7", "นางสาวสดใส ใจกว้าง", "เน็ตฟรีทั้งเมือง (ถ้ายืนใกล้เสา)", "😊", Color3.fromRGB(230, 90, 150) },
	{ "3", "นายมั่นคง ยืนยาว", "ไฟเขียวนานขึ้นอีก 2 วินาที", "😎", Color3.fromRGB(40, 160, 90) },
	{ "12", "นายประหยัด มีสตางค์", "ส้มตำจานละ 20 (เฉพาะร้านป้าแดง)", "🙂", Color3.fromRGB(240, 150, 30) },
	{ "21", "นางรักดี ทุกวัน", "ดูแลหมาซอยด้วยความรัก ไม่ให้ไล่ไรเดอร์", "🥰", Color3.fromRGB(150, 80, 200) },
	{ "5", "นายพร้อม ทำงาน", "ซ่อมหลุมก่อนน้ำท่วม (ปีหน้าแน่นอน)", "😅", Color3.fromRGB(200, 50, 50) },
}

local function poster(folder: Instance, cf: CFrame, k: number)
	local c = CANDIDATES[(k - 1) % #CANDIDATES + 1]
	local m = Instance.new("Model")
	m.Name = "Poster" .. k
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	for _, sx in ipairs({ -1.5, 1.5 }) do
		Kit.part(m, V3(0.14, 6.6, 0.14), cf * CF(sx, 3.3, 0.1), Color3.fromRGB(150, 120, 80), M.Wood)
	end
	local board = Kit.part(m, V3(3.6, 4.6, 0.1), cf * CF(0, 4.3, 0), c[5], M.SmoothPlastic, { decor = true })
	board.CanQuery = true
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0.4
	g.MaxDistance = 220
	g.Parent = board
	local function lbl(text: string, y: number, h: number, size: number?, color: Color3?)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromScale(0.04, y)
		t.Size = UDim2.fromScale(0.92, h)
		t.Text = text
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = color or WHITE
		t.Parent = g
		return t
	end
	lbl("เบอร์ " .. c[1], 0.02, 0.14)
	lbl(c[4], 0.16, 0.36)
	lbl(c[2], 0.53, 0.11)
	local box = Instance.new("Frame")
	box.BackgroundColor3 = WHITE
	box.BorderSizePixel = 0
	box.Position = UDim2.fromScale(0.05, 0.67)
	box.Size = UDim2.fromScale(0.9, 0.22)
	box.Parent = g
	local s = lbl(c[3], 0.68, 0.2, nil, c[5])
	s.ZIndex = 2
	lbl("กลุ่มรักขอนแก่นมากๆ (แต่งขึ้น)", 0.9, 0.08, nil, Color3.fromRGB(240, 240, 240))
	m.Parent = folder
end

local function winStand(folder: Instance, npc, cf: CFrame, k: number, poi)
	local m = Instance.new("Model")
	m.Name = "WinStand" .. k
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	-- shelter: roof on four posts, a bench, the sign
	for _, p in ipairs({ { -3.5, -2 }, { 3.5, -2 }, { -3.5, 2 }, { 3.5, 2 } }) do
		Kit.part(m, V3(0.2, 6.5, 0.2), cf * CF(p[1], 3.25, p[2]), Color3.fromRGB(90, 90, 96), M.Metal)
	end
	Kit.part(m, V3(8, 0.25, 5), cf * CF(0, 6.6, 0), Color3.fromRGB(40, 110, 190), M.Metal)
	local board = Kit.part(m, V3(7.2, 1.1, 0.12), cf * CF(0, 5.7, -2.1), ORANGE, M.SmoothPlastic, { decor = true })
	Kit.sign(board, "วินมอเตอร์ไซค์รับจ้าง", { face = Enum.NormalId.Front, bg = ORANGE, color = Color3.new(0, 0, 0), light = true, pps = 36 })
	Kit.part(m, V3(6, 0.3, 1.4), cf * CF(0, 1.5, 1.2), Color3.fromRGB(120, 80, 50), M.Wood)
	for _, sx in ipairs({ -2.6, 2.6 }) do Kit.part(m, V3(0.3, 1.5, 1.2), cf * CF(sx, 0.75, 1.2), Color3.fromRGB(80, 80, 84), M.Metal) end
	-- the riders: two on the bench, one asleep with his feet up, the boss standing
	local vest, jeans = ORANGE, Color3.fromRGB(40, 60, 110)
	person(m, npc, cf * CF(-1.6, 1.62, 1.3) * CFrame.Angles(0, rad(180), 0), "sit", vest, jeans)
	person(m, npc, cf * CF(1.4, 1.62, 1.3) * CFrame.Angles(0, rad(180), 0), "sit", vest, jeans)
	local bossCf = cf * CF(4.6, 0, -1.2) * CFrame.Angles(0, rad(200), 0)
	person(m, npc, bossCf, "stand", vest, Color3.fromRGB(30, 30, 34))
	m.Parent = folder
	local bossPos = bossCf.Position
	table.insert(stands, { pos = cf.Position, boss = bossPos, name = poi.name, thai = poi.thai })
	npc.prompt(bossPos + V3(0, 2.5, 0), "Talk to the stand boss", "Motorbike Taxi Stand", "winboss", "win" .. k)
end

local function officer(folder: Instance, npc, cf: CFrame, k: number)
	local m = Instance.new("Model")
	m.Name = "Tessakij" .. k
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	person(m, npc, cf, "stand", Color3.fromRGB(96, 104, 92), Color3.fromRGB(70, 74, 70))
	local board = Kit.part(m, V3(2.6, 1.2, 0.1), cf * CF(1.8, 1.6, 0.4), Color3.fromRGB(250, 250, 250), M.SmoothPlastic, { decor = true })
	Kit.part(m, V3(0.12, 1.2, 0.12), cf * CF(1.8, 0.6, 0.45), Color3.fromRGB(80, 80, 84), M.Metal, { decor = true })
	Kit.sign(board, "ห้ามขับขี่บนทางเท้า", { face = Enum.NormalId.Front, bg = WHITE, color = Color3.fromRGB(200, 30, 30), light = true, pps = 40 })
	m.Parent = folder
	table.insert(officers, { pos = cf.Position })
end

---------------------------------------------------------------------------------------------------
-- public
---------------------------------------------------------------------------------------------------
-- the motorbike-taxi stand whose turf pos is on (within 70 studs), or nil
function Street.winAt(pos: Vector3)
	for _, s in ipairs(stands) do
		if Util.flatDist(s.pos, pos) < 70 then return s end
	end
	return nil
end

function Street.isMember(player: Player): boolean
	local d = Data.get(player)
	return d ~= nil and d.win == true
end

function Street.songkran(): boolean
	return (Workspace:GetAttribute("Songkran") or 0) > os.time()
end

function Street.start(world, deps)
	local graph = world.graph
	local npc, vehicles = deps.npc, deps.vehicles
	local hub = world.pois.hub and world.pois.hub.door or Vector3.zero
	local folder = Instance.new("Folder")
	folder.Name = "StreetLife"
	folder.Parent = Workspace
	local wide, mains = {}, {}
	for _, e in ipairs(graph.edges) do
		if not e.minor and e.len >= 70 then
			local mid = (e.a.pos + e.b.pos) / 2
			local d = Util.flatDist(mid, hub)
			if d < (world.radius or 3000) then
				if (e.type == "street" or e.type == "main") and e.def.width >= 24 then table.insert(wide, e) end
				if e.type == "main" then table.insert(mains, e) end
			end
		end
	end
	-- roadworks: 8 sites, spread out
	local used = {}
	local function free(p: Vector3, gap: number): boolean
		for _, u in ipairs(used) do if Util.flatDist(u, p) < gap then return false end end
		return true
	end
	local made = 0
	-- (2026-11-18: the map is the whole tambon; was 8 roadworks and 18 posters round the centre)
	for _ = 1, 600 do
		if made >= 20 or #wide == 0 then break end
		local e = wide[rng:NextInteger(1, #wide)]
		local mid = (e.a.pos + e.b.pos) / 2
		if free(mid, 500) then
			table.insert(used, mid)
			made += 1
			roadworks(folder, npc, e, made)
		end
	end
	-- campaign posters along the main roads
	local posters = 0
	for _ = 1, 900 do
		if posters >= 48 or #mains == 0 then break end
		local e = mains[rng:NextInteger(1, #mains)]
		local p = e.a.pos:Lerp(e.b.pos, rng:NextNumber(0.2, 0.8))
		if free(p, 160) then
			local dir = V3(e.b.pos.X - e.a.pos.X, 0, e.b.pos.Z - e.a.pos.Z).Unit
			local side = dir:Cross(Vector3.yAxis) * (rng:NextNumber() < 0.5 and 1 or -1)
			local at = V3(p.X, ROAD_Y, p.Z) + side * (e.def.width / 2 + 1.4)
			table.insert(used, p)
			posters += 1
			poster(folder, CFrame.lookAt(at, at - side), posters)
		end
	end
	-- motorbike-taxi stands and municipal officers by the busy places
	local k = 0
	-- ("market" was never a place id: the fresh market is "freshmarket", so that stand was missing until 2026-11-18)
	for _, id in ipairs({ "freshmarket", "nightmarket", "station", "university", "bus", "bus2", "hospital", "hospital2", "mall", "walkingstreet" }) do
		local poi = world.pois[id]
		if poi and poi.door then
			local cf = roadside(graph, poi.door, 5)
			if cf then
				k += 1
				winStand(folder, npc, cf * CF(7, 0, 0), k, poi)
			end
		end
	end
	local o = 0
	for _, id in ipairs({ "freshmarket", "nightmarket", "mall", "station", "walkingstreet", "bus" }) do
		local poi = world.pois[id]
		if poi and poi.door then
			local cf = roadside(graph, poi.door, 2.2)
			if cf then
				o += 1
				officer(folder, npc, cf * CF(-12, 0, 0), o)
			end
		end
	end
	print(("[Street] %d roadworks, %d posters, %d taxi stands, %d municipal officers"):format(made, posters, k, o))

	-- the taxi-stand boss: join by bringing an iced coffee
	npc.handle("winboss", function(player, _id, part)
		local d = Data.get(player)
		if not d then return end
		local at = part.Position + V3(0, 2, 0)
		if d.win then
			say(player, at, "Stand boss", "Hey, buddy! Busy day. Pick up near here and I'll send you the good ones.", "ว่าไงน้อง วันนี้ลูกค้าเยอะ รับแถวนี้ได้เลย พี่ฝากลูกค้าดีๆ ให้")
			return
		end
		local inv = d.inventory or {}
		if (inv.coffee or 0) > 0 then
			inv.coffee -= 1
			if inv.coffee <= 0 then inv.coffee = nil end
			d.win = true
			Data.touch(player, "inventory", "win")
			say(player, at, "Stand boss", "Ahh, iced coffee! You're one of us now. Pick up on our turf any time.", "โห กาแฟเย็น! เข้าวินได้แล้วน้อง รับลูกค้าในถิ่นได้ตามสบาย")
			toast(player, "🛵 You joined the motorbike-taxi stands: tips +15% near them", "🛵 เข้าวินแล้ว! รับผู้โดยสารแถววินได้ทิป +15%")
			Net.fire(player, "Notify", "feed", { key = "win_join" })
		else
			say(player, at, "Stand boss", "Want in? Every stand has its rules, kid. Bring me an iced coffee first.", "อยากเข้าวินเหรอ ถิ่นใครถิ่นมันนะน้อง ไปเอากาแฟเย็นมาให้พี่ก่อน")
			toast(player, "☕ Buy an iced coffee (café or convenience store) and bring it to the stand boss", "☕ ซื้อกาแฟเย็น (คาเฟ่หรือร้านสะดวกซื้อ) แล้วเอามาให้พี่วิน")
		end
	end)

	-- municipal officers: riding a motor vehicle on the pavement near one
	local onWalk, finedAt = {}, {}
	Players.PlayerRemoving:Connect(function(p) onWalk[p] = nil; finedAt[p] = nil end)
	task.spawn(function()
		while true do
			task.wait(0.3)
			for _, player in ipairs(Players:GetPlayers()) do
				local v = vehicles.driving(player)
				local near = false
				if v and v.chassis and not v.def.pedal then
					local pos = v.chassis.Position
					for _, of in ipairs(officers) do
						if Util.flatDist(of.pos, pos) < 32 then near = true break end
					end
					if near then
						local e, p = graph:nearest(pos)
						local off = e and Util.flatDist(p, pos) or 0
						local onPavement = e ~= nil and off > e.def.width / 2 + 1 and off < e.def.width / 2 + 14 and vehicles.speed(player) > 4
						onWalk[player] = onPavement and (onWalk[player] or 0) + 0.3 or 0
						if (onWalk[player] or 0) >= 1.2 and os.clock() - (finedAt[player] or -100) > 60 then
							finedAt[player] = os.clock()
							-- (2026-11-19) the daily limit: past it the officer only warns (server/FineService)
							local ok, amount, why, n, limit = Fines.charge(player, "ticket", 100, "sidewalk")
							if ok then
								local en, th = Fines.countText(n, limit)
								Net.fire(player, "Notify", "toast", { text = "📢 Whistle! No riding on the pavement. Fine ฿" .. amount .. en, th = "📢 ปรี๊ดดด! ห้ามขี่บนทางเท้า ปรับ ฿" .. amount .. th, bad = true })
								Net.fire(player, "Notify", "scene", { kind = "fine", reason = "sidewalk", amount = amount, n = n, limit = limit })
								Net.fire(player, "Notify", "feed", { key = "sidewalk", vars = { pos = pos } })
							else
								Fines.warn(player, "ticket", why, "📢 No riding on the pavement", "📢 ห้ามขี่บนทางเท้า")
							end
						end
					end
				end
				if not near then onWalk[player] = 0 end
			end
		end
	end)

	-- the neighbour's questions at home (client/StreetLife): 1 polite, 2 funny, 3 blunt
	local socialAt = {}
	Players.PlayerRemoving:Connect(function(p) socialAt[p] = nil end)
	Net.on("Social", { "string", "int" }, function(player, kind, n)
		if kind ~= "auntie" or n < 1 or n > 3 then return end
		if os.clock() - (socialAt[player] or -1e9) < 90 then return end
		socialAt[player] = os.clock()
		local d = Data.get(player)
		if not d then return end
		local delta = ({ 2, 4, -3 })[n]
		d.happiness = math.clamp(d.happiness + delta, 0, 100)
		Data.touch(player, "happiness")
		if n == 3 or math.random() < 0.3 then Net.fire(player, "Notify", "feed", { key = "auntie" }) end
	end, 1)

	-- Songkran: five minutes of water fights every 25-40 minutes
	local function songkran()
		if Street.songkran() then return end
		Workspace:SetAttribute("Songkran", os.time() + 300)
		for _, p in ipairs(Players:GetPlayers()) do
			toast(p, "💦 Songkran! Water fights on the main roads for 5 minutes · fares +30%", "💦 สงกรานต์มาแล้ว! 5 นาทีนี้สาดน้ำกันทั้งถนนใหญ่ · ค่ารอบ +30%")
			Net.fire(p, "Notify", "feed", { key = "songkran", me = false })
		end
		task.delay(300, function()
			if not Street.songkran() then Workspace:SetAttribute("Songkran", nil) end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(25 * 60, 40 * 60))
			songkran()
		end
	end)
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("QaSongkran"):Connect(function()
			if Workspace:GetAttribute("QaSongkran") then
				Workspace:SetAttribute("QaSongkran", nil)
				songkran()
			end
		end)
	end
end

return Street
