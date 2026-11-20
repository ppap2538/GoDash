-- The order meter (2026-11-19, owner: "เพิ่มตามแนะนำได้เลย": the food-spill meter). While you carry food a small
-- card under the turn hint shows how the order is holding up; with a passenger it is their comfort instead.
-- Every jolt the server counts (server/VehicleService Notify "harsh": hard braking or flooring it, a hard corner,
-- a kerb or a pothole) knocks it down with a slosh (or the passenger's "oof") and a word on what did it; a crash
-- knocks it down a lot. The numbers mirror the server's own sums in JobService (smooth = 1 - jolts x penalty /
-- the vehicle's comfort, safety = 1 - crashes x 0.34 / 0.5 for fragile orders), so what you see is what the
-- customer rates; an order that arrives untouched earns a small thank-you on the slip.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Jobs = require(Shared.Config.Jobs)
local Gear = require(Shared.Config.Gear)
local Workspace = game:GetService("Workspace")
local UI = require(script.Parent.UI.Kit)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local Drive = require(script.Parent.Drive)

local Spill = {}
local C, F = UI.C, UI.F
local L = Lang.pick

local card, icon, title, pct, fill, pop
local heatRow, heatFill, heatText -- (2026-11-19) the food cools from the pick-up: a second bar (Config/Gear bags keep it warm)
local harsh, crashes = 0, 0
local key = "" -- the job id + stage this count belongs to
local shown = 1

local WHAT = {
	brake = { "Hard braking!", "เบรกแรง!" },
	gas = { "Jerky start!", "กระชากออกตัว!" },
	turn = { "Sharp turn!", "เลี้ยวแรง!" },
	bump = { "Bump!", "ตกหลุม / ขึ้นฟุต!" },
	crash = { "Crash!", "ชน!" },
}

local function carrying()
	local j = State.job and State.job.job
	if j and j.stage == "dropoff" and (j.mode == "food" or j.mode == "ride") then return j end
	return nil
end

local function def(j)
	local list = j.mode == "ride" and Jobs.RIDE or Jobs.FOOD
	return list and list[j.type] or nil
end

-- the order's condition 0..1, the way server/JobService scores it
local function condition(j): number
	local d = def(j)
	local fragile = d and d.fragile == true
	local penalty = j.mode == "ride" and 0.1 or (fragile and 0.14 or 0.05)
	local bag = j.mode ~= "ride" and State.data and Gear.worn(State.data.gear, "bag")
	if bag then penalty *= bag.steady end
	local c = Drive.current()
	local comfort = (c and c.stats and c.stats.comfort) or 0.8
	local smooth = math.clamp(1 - harsh * penalty / math.max(comfort, 0.3), 0, 1)
	local safety = math.clamp(1 - crashes * (fragile and 0.5 or 0.34), 0, 1)
	return smooth * safety
end

local function words(j, v: number): string
	if j.mode == "ride" then
		if v >= 0.95 then return L("Passenger: comfy", "ผู้โดยสาร: นั่งสบาย") end
		if v >= 0.8 then return L("Passenger: a bit shaken", "ผู้โดยสาร: เริ่มเวียนหัว") end
		if v >= 0.55 then return L("Passenger: carsick", "ผู้โดยสาร: เมารถแล้ว") end
		return L("Passenger: about to be sick!", "ผู้โดยสาร: จะอ้วกแล้ว!")
	end
	if v >= 0.95 then return L("Order: perfect", "อาหาร: สภาพดีเยี่ยม") end
	if v >= 0.8 then return L("Order: a little spilled", "อาหาร: กระฉอกนิดหน่อย") end
	if v >= 0.55 then return L("Order: spilling", "อาหาร: หกไปบ้างแล้ว") end
	return L("Order: a mess!", "อาหาร: เละแล้ว!")
end

local function colour(v: number): Color3
	if v >= 0.8 then return Color3.fromRGB(60, 200, 110) end
	if v >= 0.55 then return Color3.fromRGB(240, 180, 40) end
	return Color3.fromRGB(230, 70, 60)
end

-- (2026-11-20, owner: "UI ... มันเยอะเกินเหตุ") the card no longer sits on screen for the whole trip: it shows for
-- 4 s at the pick-up, for 5 s after anything knocks the order, and all the time once the order is damaged
local flashUntil, lastV = 0, 1
local function refresh()
	local j = carrying()
	if not j or State.cutscene then card.Visible = false return end
	local k = tostring(j.id) .. ":" .. tostring(j.stage)
	if k ~= key then
		-- a new order picked up: the server reset its count at the pick-up
		key = k
		harsh, crashes = 0, 0
		shown = 1
		flashUntil, lastV = os.clock() + 4, 1
	end
	local v = condition(j)
	if v < lastV - 0.001 then flashUntil = os.clock() + 5 end
	lastV = v
	card.Visible = v < 0.95 or os.clock() < flashUntil
	icon.Text = j.mode == "ride" and (v >= 0.8 and "🙂" or (v >= 0.55 and "😵" or "🤢")) or (v >= 0.8 and "🍜" or (v >= 0.55 and "🥣" or "💦"))
	title.Text = words(j, v)
	shown += (v - shown) * 0.25
	pct.Text = ("%d%%"):format(math.floor(v * 100 + 0.5))
	fill.Size = UDim2.new(math.clamp(shown, 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = colour(v)
	-- heat: food only, from the pick-up time (server clock)
	local food = j.mode == "food" and type(j.pickedAt) == "number"
	heatRow.Visible = food
	card.Size = UDim2.fromOffset(250, food and 66 or 46)
	if food then
		local h = Gear.heat(State.data and State.data.gear, Workspace:GetServerTimeNow() - j.pickedAt)
		heatFill.Size = UDim2.new(h, 0, 1, 0)
		heatFill.BackgroundColor3 = h >= 0.8 and Color3.fromRGB(240, 110, 40) or (h >= 0.35 and Color3.fromRGB(240, 180, 60) or Color3.fromRGB(110, 160, 230))
		heatText.Text = h >= 0.8 and L("🔥 Hot", "🔥 ร้อน") or (h >= 0.35 and L("♨️ Warm", "♨️ อุ่น") or L("🥶 Cold", "🥶 เย็นแล้ว"))
	end
end

local function jolt(kind: string)
	local j = carrying()
	if not j then return end
	refresh()
	-- the card shakes and the cause floats up
	task.spawn(function()
		for i = 1, 6 do
			card.Rotation = (i % 2 == 0 and 1 or -1) * (7 - i) * 0.9
			task.wait(0.04)
		end
		card.Rotation = 0
	end)
	local w = WHAT[kind] or WHAT.bump
	pop.Text = (j.mode == "ride" and "😖 " or "💦 ") .. L(w[1], w[2])
	pop.TextTransparency = 0
	pop.Position = UDim2.new(0.5, 0, 1, 2)
	TweenService:Create(pop, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, 26), TextTransparency = 1 }):Play()
	if j.mode == "ride" then
		Feedback.play("grunt2", 0.32, 1.25, 0.5) -- the passenger
	else
		Feedback.play("slosh", 0.4, 1.45 + math.random() * 0.2, 0.4) -- the soup in the box
	end
end

function Spill.start()
	local parent = Feedback.top
	if not parent then return end
	card = UI.new("Frame", { Name = "OrderMeter", LayoutOrder = -5, Size = UDim2.fromOffset(250, 46), BackgroundColor3 = Color3.fromRGB(24, 28, 36),
		BackgroundTransparency = 0.12, Visible = false, Parent = parent })
	UI.corner(card, 12)
	icon = UI.label(card, "🍜", 24, C.white, F.black, { Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(36, 36), TextXAlignment = Enum.TextXAlignment.Center })
	title = UI.label(card, "", 14, C.white, F.bold, { Position = UDim2.fromOffset(46, 4), Size = UDim2.new(1, -96, 0, 20) })
	pct = UI.label(card, "100%", 15, C.white, F.black, { Position = UDim2.new(1, -50, 0, 4), Size = UDim2.fromOffset(44, 20), TextXAlignment = Enum.TextXAlignment.Right })
	local bar = UI.new("Frame", { Position = UDim2.fromOffset(46, 28), Size = UDim2.new(1, -56, 0, 9), BackgroundColor3 = Color3.fromRGB(60, 64, 74), Parent = card })
	UI.corner(bar, 5)
	fill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(60, 200, 110), Parent = bar })
	UI.corner(fill, 5)
	pop = UI.label(card, "", 14, Color3.fromRGB(255, 210, 120), F.black, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2),
		Size = UDim2.fromOffset(240, 20), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1 })
	pop.TextStrokeTransparency = 0.4
	for _, t in ipairs({ icon, title, pct, pop }) do t:SetAttribute("NoTranslate", true) end
	UI.fitText(title, 14, 10)
	heatRow = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(46, 42), Size = UDim2.new(1, -56, 0, 18), Visible = false, Parent = card })
	heatText = UI.label(heatRow, "", 12, Color3.fromRGB(255, 220, 190), F.bold, { Size = UDim2.fromOffset(78, 18) })
	heatText:SetAttribute("NoTranslate", true)
	local hb = UI.new("Frame", { Position = UDim2.fromOffset(80, 5), Size = UDim2.new(1, -80, 0, 7), BackgroundColor3 = Color3.fromRGB(60, 64, 74), Parent = heatRow })
	UI.corner(hb, 4)
	heatFill = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(240, 110, 40), Parent = hb })
	UI.corner(heatFill, 4)

	Net.listen("Notify", function(kind, p)
		if kind == "harsh" and type(p) == "table" then
			harsh = tonumber(p.harsh) or (harsh + 1)
			crashes = tonumber(p.crashes) or crashes
			jolt(tostring(p.kind or "bump"))
		elseif kind == "crash" and type(p) == "table" and carrying() then
			crashes = tonumber(p.crashes) or (crashes + 1)
			jolt("crash")
		end
	end)
	State.onJob(function() refresh() end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then return end
		acc = 0
		refresh()
	end)
end

return Spill
