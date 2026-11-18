-- Key help, bottom-left (keyboard and mouse only). Lists the keys that matter right now: walking
-- keys on foot, driving keys in a vehicle, Y while an order is offered. Open for new riders,
-- folded to a small chip after a few deliveries; K opens and folds it.
local UserInputService = game:GetService("UserInputService")
local UIRoot = script.Parent.Parent
local UI = require(UIRoot.Kit)
local UIState = require(UIRoot.Core.UIState)
local State = require(UIRoot.Parent.State)
local Drive = require(UIRoot.Parent.Drive)
local Lang = require(UIRoot.Parent.Lang)

local Controls = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local refs = {} :: { [string]: any }
local open: boolean? = nil -- nil = not decided yet (decided from the profile)
local lastKey = ""

local ROW_H, KEY_W, WIDTH = 20, 64, 236

local function keysNow(): { { string } }
	local list = {}
	local offer = State.job and State.job.offer ~= nil
	local job = State.job and State.job.job ~= nil
	if offer then table.insert(list, { "Y", L("Accept the order", "รับออร์เดอร์") }) end
	if Drive.info.driving then
		table.insert(list, { "W / S", L("Go · brake / reverse", "เร่ง · เบรก / ถอย") })
		table.insert(list, { "A / D", L("Steer", "เลี้ยวซ้าย / ขวา") })
		table.insert(list, { "Space", L("Handbrake", "เบรกมือ") })
		if job then table.insert(list, { "G", L("Pick up / deliver", "รับ / ส่งอาหาร") }) end
		table.insert(list, { "Q", Drive.info.auto and L("Auto drive off", "ปิดขับอัตโนมัติ") or L("Auto drive (follows the route)", "ขับอัตโนมัติตามเส้นทาง") })
		table.insert(list, { "V", L("First-person view", "มุมมองคนขี่") })
		table.insert(list, { "F", L("Headlights", "ไฟหน้า") })
		table.insert(list, { "E", L("Get off", "ลงจากรถ") })
	else
		table.insert(list, { "W A S D", L("Walk", "เดิน") })
		table.insert(list, { "F", L("Get on your vehicle", "ขึ้นรถ") })
		table.insert(list, { "E", L("Talk · use · shop", "คุย · ใช้งาน · ซื้อของ") })
		table.insert(list, { "Space", L("Jump", "กระโดด") })
	end
	table.insert(list, { "J", (State.job and State.job.online) and L("Stop taking orders", "ปิดรับงาน") or L("Start taking orders", "เริ่มรับงาน") })
	table.insert(list, { "M", L("Phone (map, garage…)", "มือถือ (แผนที่ โรงรถ…)") })
	return list
end

local function render()
	local list = open and keysNow() or {}
	local sig = (open and "o" or "c") .. Lang.code
	for _, k in ipairs(list) do sig ..= k[1] .. k[2] end
	if sig == lastKey then return end
	lastKey = sig
	UI.clear(refs.rows)
	for i, k in ipairs(list) do
		local row = UI.new("Frame", { BackgroundTransparency = 1, LayoutOrder = i, Size = UDim2.new(1, 0, 0, ROW_H), Parent = refs.rows })
		local cap = UI.new("Frame", { BackgroundColor3 = C.white, BackgroundTransparency = 0.86, Size = UDim2.new(0, KEY_W, 1, -2), Parent = row })
		UI.corner(cap, 5)
		UI.stroke(cap, C.white, 1, 0.65)
		local kl = UI.label(cap, k[1], 11, C.white, F.black, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.None })
		local tl = UI.label(row, k[2], 12, C.white, F.med, { Position = UDim2.fromOffset(KEY_W + 8, 0), Size = UDim2.new(1, -(KEY_W + 8), 1, 0) })
		UI.fitText(tl, 12, 9)
		kl:SetAttribute("NoTranslate", true)
		tl:SetAttribute("NoTranslate", true)
	end
	refs.head.Text = open and L("⌨  Controls   [K] hide", "⌨  ปุ่มควบคุม   [K] ซ่อน") or L("⌨  Controls  [K]", "⌨  ปุ่มควบคุม  [K]")
	local h = 26 + (#list > 0 and (#list * (ROW_H + 3) + 6) or 0)
	refs.panel.Size = UDim2.fromOffset(open and WIDTH or 150, h)
end

-- region = the HUD's BottomLeft region.
function Controls.build(region: Frame)
	local panel = UI.panel(region, { Name = "Controls", LayoutOrder = 1, Size = UDim2.fromOffset(WIDTH, 26), BackgroundTransparency = 0.3 }, 12)
	refs.panel = panel
	refs.head = UI.label(panel, "", 11, C.textDim, F.bold, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 18) })
	refs.head:SetAttribute("NoTranslate", true)
	local hit = UI.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), Parent = panel })
	local rows = UI.new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 28), Size = UDim2.new(1, -20, 1, -32), Parent = panel })
	UI.list(rows, 3)
	refs.rows = rows
	local function toggle()
		open = not open
		render()
	end
	hit.MouseButton1Click:Connect(toggle)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.K then toggle() end
	end)
	UIState.bind("controls", panel)
	State.onData(function()
		if open == nil and State.data then
			open = ((State.data.stats.deliveries or 0) + (State.data.stats.rides or 0)) < 3
		end
	end)
	-- cheap: rebuilds only when the list of keys changes
	task.spawn(function()
		while true do
			render()
			task.wait(0.3)
		end
	end)
end

return Controls
