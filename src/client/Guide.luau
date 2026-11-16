-- The "what do I do now?" bar. One card at the top of the screen always says the next thing to do
-- in plain words, with an arrow that points at the place to go and its distance, and a button
-- for the action when there is one. It replaces the old step-by-step tutorial: during the first
-- delivery the same card counts the steps ("First steps 2/5").
-- Also marks the player's own vehicle in the world and binds J (go online / offline).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared.Config.Game)
local Vehicles = require(Shared.Config.Vehicles)
local Util = require(Shared.Util)
local Net = require(Shared.Net)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local UIState = require(script.Parent.UI.Core.UIState)
local State = require(script.Parent.State)
local Drive = require(script.Parent.Drive)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)
local GPS = require(script.Parent.GPS)
local Lang = require(script.Parent.Lang)

local Guide = {}
local C, F = UI.C, UI.F
local player = Players.LocalPlayer
local touch = Layout.isTouch
local L = Lang.pick
local refs = {} :: { [string]: any }
local current = nil :: any -- the last computed objective
local myVehicle: Model? = nil

local W, H = 470, 92

---------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------
local function rootPos(): Vector3?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return r and (r :: BasePart).Position or nil
end

local function findVehicle(): Model?
	local folder = Workspace:FindFirstChild("Vehicles")
	if not folder then return nil end
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Owner") == player.UserId then return m end
	end
	return nil
end

local function pedalled(): boolean
	local def = myVehicle and Vehicles.ById[myVehicle:GetAttribute("VehicleId")]
	return def ~= nil and def.pedal == true
end

local function key(k: string): string
	return touch and "" or (" [" .. k .. "]")
end

local function setOnline(on: boolean)
	Net.send("JobSetOnline", on, State.job and State.job.mode or "food")
	Feedback.click()
end
Guide.setOnline = setOnline

local function nearestGas(from: Vector3)
	local w = State.world
	if not w then return nil end
	local best, bd
	for _, p in ipairs(w.pois) do
		if p.kind == "gas" then
			local d = (p.pos - from).Magnitude
			if not bd or d < bd then best, bd = p, d end
		end
	end
	return best
end

local function placeName(t): string
	if not t then return "" end
	if Lang.code == "th" and t.thai and t.thai ~= "" then return t.thai end
	return Lang.t(t.name or "")
end

---------------------------------------------------------------------------------------------------
-- the objective: what should the player do right now?
--   returns { icon, title, detail, step?, target?, button? = { text, fn }, color?, warn? }
---------------------------------------------------------------------------------------------------
local function compute()
	local d = State.data
	if not d then
		return { icon = "⏳", title = L("Loading your rider profile…", "กำลังโหลดข้อมูลไรเดอร์…"), detail = "" }
	end
	local job = State.job or {}
	local info = Drive.info
	local driving = info.driving == true
	local pos = rootPos()
	local first = ((d.stats and d.stats.deliveries) or 0) + ((d.stats and d.stats.rides) or 0) == 0
	local vehName = myVehicle and Lang.t(myVehicle:GetAttribute("VehicleName") or myVehicle.Name) or L("vehicle", "รถ")

	-- a job offer is waiting
	if job.offer then
		return { step = 3, icon = "🔔", color = C.orange, title = L("New order! Take it?", "มีออร์เดอร์ใหม่! รับไหม?"),
			detail = touch and L("The order card is at the bottom. Tap ACCEPT.", "ดูรายละเอียดด้านล่าง แล้วแตะปุ่ม 'รับงาน'")
				or L("The order card is at the bottom. Press Y or click ACCEPT.", "ดูรายละเอียดด้านล่าง แล้วกด Y หรือคลิก 'รับงาน'"),
			button = { text = L("Accept", "รับงาน") .. key("Y"), fn = function() local o = State.job.offer; if o then Net.send("JobRespond", o.id, true) end end } }
	end

	-- a job is running
	if job.job then
		local j = job.job
		local pickup = j.stage == "pickup"
		local ride = j.mode == "ride"
		local t = pickup and j.pickup or j.dropoff
		local dist = pos and Util.flatDist(pos, t.pos) or math.huge
		local close = dist <= Game.INTERACT_RANGE
		local o = { step = pickup and 4 or 5, target = t.pos, icon = pickup and (ride and "🧍" or "🍱") or "📍" }
		if close then
			o.color = C.green
			o.title = pickup and (ride and L("Your passenger is here!", "ถึงจุดรับผู้โดยสารแล้ว!") or L("You're at the restaurant!", "ถึงร้านแล้ว!"))
				or (ride and L("You've arrived!", "ถึงที่หมายแล้ว!") or L("You're at the customer!", "ถึงบ้านลูกค้าแล้ว!"))
			local k = driving and "G" or "E"
			o.detail = touch and L("Tap the green button.", "แตะปุ่มสีเขียว") or L("Press " .. k .. " or click the button.", "กด " .. k .. " หรือคลิกปุ่ม")
			o.button = { text = (pickup and (ride and L("Pick up", "รับผู้โดยสาร") or L("Pick up food", "รับอาหาร")) or (ride and L("Drop off", "ส่งผู้โดยสาร") or L("Deliver", "ส่งอาหาร"))) .. key(k),
				fn = function() Net.send("JobAction") end }
			return o
		end
		if pickup then
			o.title = ride and L("Pick up the passenger: ", "ไปรับผู้โดยสาร: ") .. placeName(t) or L("Collect the food at ", "ไปรับอาหารที่ ") .. placeName(t)
			o.detail = L("Follow the green line on the road. The place has a green light pillar.", "ขี่ตามเส้นสีเขียวบนถนน ร้านมีเสาแสงสีเขียว")
		else
			local who = Lang.t(j.customer or "")
			o.title = ride and L("Take them to ", "ไปส่งที่ ") .. placeName(t) or L("Deliver to ", "ไปส่งให้ ") .. (who ~= "" and who or placeName(t))
			local left = j.pickedAt and (j.parSeconds - (os.time() - j.pickedAt)) or nil
			if left and left < 0 then
				o.warn = true
				o.detail = L("Late by ", "สายแล้ว ") .. Util.duration(-left) .. L(" — the fare goes down. Hurry!", " — ค่าส่งจะลดลง รีบหน่อย!")
			elseif left then
				o.detail = L("Time left ", "เหลือเวลา ") .. Util.duration(left) .. L(" · arrive early for a tip, stop at red lights", " · ส่งไวได้ทิป อย่าฝ่าไฟแดง")
			end
		end
		if not driving and myVehicle and dist > 120 then
			o.detail = L("Get on your vehicle first (F), it's much faster.", "ขึ้นรถก่อน (กด F) จะไปได้เร็วกว่า")
		end
		return o
	end

	-- no job: needs come first
	if not first and d.energy < 12 then
		return { icon = "😪", color = C.orange, warn = true, title = L("You're exhausted", "เหนื่อยมากแล้ว"),
			detail = L("Rest on a bench or sala (walk up, press E) or drink an energy drink.", "พักที่ม้านั่งหรือศาลา (เดินไปกด E) หรือดื่มเครื่องดื่มชูกำลัง") }
	end
	if not first and d.hunger < 15 then
		return { icon = "🍜", color = C.orange, warn = true, title = L("You're hungry", "หิวแล้ว"),
			detail = L("Walk into any restaurant and press E to buy food, then eat it from your Bag.", "เดินเข้าร้านอาหารแล้วกด E ซื้ออาหาร แล้วกินจากแอปกระเป๋า") }
	end

	if not driving then
		if myVehicle then
			local vp = myVehicle:GetPivot().Position
			local dist = pos and Util.flatDist(pos, vp) or 0
			return { step = 1, icon = pedalled() and "🚲" or "🛵", target = dist > 14 and vp or nil,
				title = dist > 14 and (L("Get on your ", "ขึ้น") .. vehName .. L("", "ของคุณ")) or L("Press F to get on", "กด F เพื่อขึ้นรถ"),
				detail = touch and L("Walk to the vehicle with the green tag and tap Drive.", "เดินไปที่รถที่มีป้ายสีเขียว แล้วแตะ 'ขับ'")
					or L("Walk to the vehicle with the green tag and press F.", "เดินไปที่รถที่มีป้ายสีเขียว แล้วกด F") }
		end
		return { step = 1, icon = "🔑", title = L("Bring out your vehicle", "เรียกรถของคุณออกมา"),
			detail = L("Phone → Garage → Bring it to me.", "เปิดมือถือ → โรงรถ → เรียกรถมาหาฉัน"),
			button = { text = L("Open Garage", "เปิดโรงรถ"), fn = function() Phone.setOpen(true); Phone.go("garage") end } }
	end

	-- driving, no job
	if not info.pedal and info.fuelCap and info.fuelCap > 0 and info.fuel / info.fuelCap < 0.15 then
		local gas = pos and nearestGas(pos)
		local t = GPS.target()
		local going = gas and t and not t.job and (t.pos - gas.pos).Magnitude < 5
		return { icon = "⛽", color = C.orange, warn = true, target = going and gas.pos or nil, title = L("Fuel is low!", "น้ำมันใกล้หมด!"),
			detail = going and L("Follow the green line to the fuel station, walk to the pump and press E.", "ขี่ตามเส้นสีเขียวไปปั๊ม แล้วเดินไปที่ตู้กด E")
				or L("Head to the nearest fuel station before you run dry.", "ไปเติมที่ปั๊มใกล้สุดก่อนน้ำมันหมด"),
			button = (not going and gas) and { text = L("Route to fuel", "นำทางไปปั๊ม"), fn = function() GPS.setTarget(gas.pos, gas.name) end } or nil }
	end
	if not job.online then
		return { step = 2, icon = "📲", color = C.green, title = L("Start taking orders", "เริ่มรับงาน"),
			detail = touch and L("Tap the button to go online. Orders will pop up by themselves.", "แตะปุ่มเพื่อเปิดรับงาน แล้วออร์เดอร์จะเด้งขึ้นมาเอง")
				or L("Press J or click the button to go online. Orders pop up by themselves.", "กด J หรือคลิกปุ่มเพื่อเปิดรับงาน แล้วออร์เดอร์จะเด้งขึ้นมาเอง"),
			button = { text = L("▶ Go online", "▶ เริ่มรับงาน") .. key("J"), fn = function() setOnline(true) end } }
	end
	local t = GPS.target()
	if t and not t.job then
		return { icon = "📍", target = t.pos, title = L("Going to ", "กำลังไป ") .. Lang.t(t.name), detail = L("Follow the green line on the road.", "ขี่ตามเส้นสีเขียวบนถนน") }
	end
	return { step = 3, icon = "📡", title = L("Looking for an order near you…", "กำลังหาออร์เดอร์ใกล้คุณ…"),
		detail = L("Ride around freely. A new order pops up in a few seconds.", "ขี่เล่นไปรอบๆ ได้เลย ออร์เดอร์ใหม่จะเด้งขึ้นมาในไม่กี่วินาที") }
end

---------------------------------------------------------------------------------------------------
-- card
---------------------------------------------------------------------------------------------------
local STEP_NAMES = {
	{ "Get on", "ขึ้นรถ" }, { "Go online", "เปิดรับงาน" }, { "Accept", "รับออร์เดอร์" }, { "Pick up", "รับอาหาร" }, { "Deliver", "ส่งอาหาร" },
}

local function render(o)
	current = o
	refs.icon.Text = o.icon or "🛵"
	refs.title.Text = o.title or ""
	refs.detail.Text = o.detail or ""
	local accent = o.color or C.green
	refs.accent.BackgroundColor3 = accent
	refs.iconBg.BackgroundColor3 = accent
	refs.detail.TextColor3 = o.warn and Color3.fromRGB(255, 190, 150) or C.textDim
	local d = State.data
	local first = d and ((d.stats.deliveries or 0) + (d.stats.rides or 0) == 0)
	if first and o.step then
		refs.tag.Text = L("FIRST STEPS ", "เริ่มต้น ") .. o.step .. "/5 · " .. L(STEP_NAMES[o.step][1], STEP_NAMES[o.step][2])
	else
		refs.tag.Text = L("WHAT TO DO NOW", "ตอนนี้ต้องทำอะไร")
	end
	local hasBtn = o.button ~= nil
	refs.button.Visible = hasBtn
	if hasBtn then refs.button.Text = o.button.text end
	refs.compass.Visible = (not hasBtn) and o.target ~= nil
	local textRight = (hasBtn or o.target) and (hasBtn and 162 or 84) or 14
	refs.title.Size = UDim2.new(1, -(70 + textRight), 0, 24)
	refs.detail.Size = UDim2.new(1, -(70 + textRight), 0, 34)
	refs.tag.Size = UDim2.new(1, -(70 + textRight), 0, 14)
end

local function signature(o): string
	return table.concat({ o.icon or "", o.title or "", o.detail or "", o.button and o.button.text or "", o.target and "t" or "", tostring(o.step), o.warn and "w" or "" }, "|")
end

local function buildCard(parent: Instance)
	local card = UI.panel(parent, { Name = "Guide", LayoutOrder = -10, Size = UDim2.fromOffset(W, H), BackgroundTransparency = 0.12 }, 18)
	refs.card = card
	refs.accent = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.new(0, 6, 1, -24), Position = UDim2.fromOffset(0, 12), Parent = card })
	UI.corner(refs.accent, 3)
	local iconBg = UI.new("Frame", { BackgroundColor3 = C.green, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(46, 46), Parent = card })
	UI.corner(iconBg, 23)
	refs.iconBg = iconBg
	refs.icon = UI.label(iconBg, "🛵", 24, C.white, F.med, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.tag = UI.label(card, "", 11, C.green, F.bold, { Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -84, 0, 14) })
	refs.title = UI.label(card, "", 18, C.white, F.black, { Position = UDim2.fromOffset(72, 22), Size = UDim2.new(1, -84, 0, 24) })
	UI.fitText(refs.title, 18, 11)
	refs.detail = UI.label(card, "", 13, C.textDim, F.med, { Position = UDim2.fromOffset(72, 48), Size = UDim2.new(1, -84, 0, 34), TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd })
	-- arrow + distance to the target
	local compass = UI.new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(70, 74), Visible = false, Parent = card })
	refs.compass = compass
	local ring = UI.new("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.88, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(48, 48), Parent = compass })
	UI.corner(ring, 24)
	UI.stroke(ring, C.green, 2, 0.2)
	refs.arrow = UI.label(ring, "▲", 26, C.green, F.black, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 40),
		TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.dist = UI.label(compass, "", 13, C.white, F.black, { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
	refs.button = UI.button(card, "", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(148, touch and 52 or 44), TextSize = 15, Visible = false }, function()
		if current and current.button then current.button.fn() end
	end)
	UI.fitText(refs.button, 15, 10)
	for _, l in ipairs({ refs.icon, refs.tag, refs.title, refs.detail, refs.dist, refs.button, refs.arrow }) do l:SetAttribute("NoTranslate", true) end
	UIState.onChange(function()
		card.Visible = not UIState.get("build") and not UIState.get("modal")
	end)
	local function size()
		local w = Layout.breakpoint == "compact" and 420 or W
		local strip = parent.AbsoluteSize.X / math.max(Layout.scale, 0.01)
		if strip > 10 then w = math.min(w, strip) end
		card.Size = UDim2.fromOffset(math.max(w, 300), H)
	end
	size()
	Layout.onChange(size)
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(size)
end

---------------------------------------------------------------------------------------------------
-- tag over the player's own vehicle
---------------------------------------------------------------------------------------------------
local function buildVehicleTag()
	local bb = Instance.new("BillboardGui")
	bb.Name = "GoDashMyVehicle"
	bb.Size = UDim2.fromOffset(170, 52)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 500
	bb.ResetOnSpawn = false
	bb.Enabled = false
	local card = UI.new("Frame", { BackgroundColor3 = C.green, Size = UDim2.new(1, 0, 0, 40), Parent = bb })
	UI.corner(card, 14)
	UI.stroke(card, C.white, 2)
	local title = UI.label(card, "", 15, C.white, F.black, { Size = UDim2.new(1, -10, 0, 20), Position = UDim2.fromOffset(5, 2), TextXAlignment = Enum.TextXAlignment.Center })
	local sub = UI.label(card, "", 12, C.white, F.bold, { Size = UDim2.new(1, -10, 0, 16), Position = UDim2.fromOffset(5, 21), TextXAlignment = Enum.TextXAlignment.Center })
	title:SetAttribute("NoTranslate", true)
	sub:SetAttribute("NoTranslate", true)
	local tip = UI.label(bb, "▼", 16, C.green, F.black, { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4 })
	tip:SetAttribute("NoTranslate", true)
	bb.Parent = player:WaitForChild("PlayerGui")
	refs.tagGui, refs.tagTitle, refs.tagSub = bb, title, sub
end

local function updateVehicleTag()
	local bb = refs.tagGui
	if not bb then return end
	local show = myVehicle ~= nil and not Drive.info.driving and myVehicle.PrimaryPart ~= nil
	bb.Enabled = show
	if show then
		bb.Adornee = myVehicle.PrimaryPart
		refs.tagTitle.Text = (pedalled() and "🚲 " or "🛵 ") .. L("Your vehicle", "รถของคุณ")
		refs.tagSub.Text = touch and L("Walk up and tap Drive", "เดินไปแล้วแตะ 'ขับ'") or L("Walk up and press F", "เดินไปแล้วกด F")
	end
end

---------------------------------------------------------------------------------------------------
function Guide.start()
	buildCard(Feedback.top)
	buildVehicleTag()

	-- J: go online / offline (keyboard)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.J and State.data then
			local on = State.job and State.job.online
			setOnline(not on)
		end
	end)

	local last = ""
	local acc = 1
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			myVehicle = findVehicle()
			local ok, o = pcall(compute)
			if ok and o then
				local sig = signature(o)
				if sig ~= last then
					local stepChanged = current and current.step ~= o.step
					last = sig
					render(o)
					if stepChanged then UI.pop(refs.card, 0.94) end
				else
					current = o -- keep the target and button callbacks fresh
				end
			elseif not ok then
				warn("[Guide] " .. tostring(o))
			end
			updateVehicleTag()
		end
		-- arrow: direction of the target relative to where the camera looks
		local o = current
		local cam = Workspace.CurrentCamera
		local pos = rootPos()
		if o and o.target and cam and pos and refs.compass.Visible then
			local look = cam.CFrame.LookVector
			local fwd = Vector3.new(look.X, 0, look.Z)
			local to = Vector3.new(o.target.X - pos.X, 0, o.target.Z - pos.Z)
			if fwd.Magnitude > 0.01 and to.Magnitude > 0.01 then
				fwd, to = fwd.Unit, to.Unit
				local ang = math.atan2(fwd.X * to.Z - fwd.Z * to.X, fwd.X * to.X + fwd.Z * to.Z)
				refs.arrow.Rotation = math.deg(ang)
			end
			local g = GPS.target()
			local byRoad = g and GPS.path and (g.pos - o.target).Magnitude < 3 and GPS.distance > 0
			refs.dist.Text = Lang.t(Util.dist(byRoad and GPS.distance or Util.flatDist(pos, o.target)))
		end
	end)
	Lang.onChange(function() last = "" end)
end

return Guide
