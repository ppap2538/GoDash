-- "Finance" phone app and the repo crew (server/FinanceService). Shows your instalments with
-- pay / pay-off buttons and the KK Motors offers ("0% down, 0% interest*"). When two instalments
-- are missed while you ride the vehicle, a pickup with the repo crew chases you for a minute: get
-- away, or pay the arrears in the app; if they catch you, the vehicle is towed.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Sounds = require(Shared.Config.Sounds)
local Vehicles = require(Shared.Config.Vehicles)
local RiderPose = require(Shared.RiderPose)
local Util = require(Shared.Util)
local UI = require(script.Parent.UI.Kit)
local State = require(script.Parent.State)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)
local Choice = require(script.Parent.Choice)
local Drive = require(script.Parent.Drive)
local GPS = require(script.Parent.GPS)
local EngineSound = require(script.Parent.EngineSound)

local Finance = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local Credit = require(Shared.Config.Credit) -- the same numbers server/FinanceService charges
local TERMS = Credit.TERMS
local function vname(def): string
	return (Lang.code == "th" and def.thai) or def.name
end

local function call(op: string, arg: string?)
	local ok, msg = Net.call("City", op, arg)
	if msg and msg ~= "" then Feedback.toast(msg, ok and "good" or "bad") end
	if ok then Feedback.good() end
	Phone.refresh()
	return ok
end

local function screen()
	local ui = Phone.ui
	local d = State.data
	if not d then return end
	local hero = ui.bigCard(104, Color3.fromRGB(30, 110, 90))
	UI.label(hero, L("💳 Easy Finance", "💳 ไฟแนนซ์ทันใจ"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) })
	UI.label(hero, L("0 / 25 / 50% down · the more down, the lower the fee", "ดาวน์ 0 / 25 / 50% · ดาวน์มาก ค่าธรรมเนียมน้อย"), 13, C.white, F.bold, { Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) })
	UI.label(hero, L("Fee 35% / 20% / 10%. 2 missed instalments = repossession.", "ค่าธรรมเนียม 35% / 20% / 10% · ค้าง 2 งวด ยึดรถ"), 10, Color3.fromRGB(200, 230, 220), F.med,
		{ Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -28, 0, 14) })
	-- the credit score: it decides the bank's limit and rate
	local sc = tonumber(d.credit) or Credit.START
	local gEn, gTh, gCol = Credit.grade(sc)
	local limit = Credit.limit(d.level, sc)
	local scoreL = UI.label(hero, L(("Credit score %d (%s) · bank limit %s"):format(sc, gEn, Util.money(limit)), ("เครดิตบูโร %d (%s) · วงเงินกู้ %s"):format(sc, gTh, Util.money(limit))),
		12, C.white, F.black, { Position = UDim2.fromOffset(14, 78), Size = UDim2.new(1, -28, 0, 18) })
	local dot = UI.new("Frame", { BackgroundColor3 = gCol, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0, 87), Size = UDim2.fromOffset(12, 12), Parent = hero })
	UI.corner(dot, 6)
	local _ = scoreL

	-- KK Bank personal loan
	ui.section(L("KK BANK · PERSONAL LOAN", "KK BANK · สินเชื่อส่วนบุคคล"))
	local bl = d.bankLoan
	if bl then
		local paid = bl.terms - bl.left
		local status = bl.missed > 0 and L(("⚠️ %d overdue (+฿%d fees) · 30%% of job pay goes to the bank"):format(bl.missed, bl.fee or 0), ("⚠️ ค้าง %d งวด (+ค่าปรับ ฿%d) · หักรายได้ 30%%"):format(bl.missed, bl.fee or 0))
			or L("on time · auto-debit from cash, then savings", "ปกติ · ตัดจากเงินสดก่อน แล้วค่อยตัดบัญชีออมทรัพย์")
		ui.row("🏦", L("Loan ", "เงินกู้ ") .. Util.money(bl.principal), ("%d/%d · ฿%d %s · %s"):format(paid, bl.terms, bl.each, L("each", "ต่องวด"), status),
			L("Pay", "จ่าย"), function() call("bank_pay") end,
			{ btnWidth = 60, btnColor = bl.missed > 0 and C.red or C.green, btn2 = { text = L("Close", "ปิดยอด"), width = 64, fn = function() call("bank_payoff") end } })
	elseif sc < Credit.MIN_SCORE then
		UI.label(ui.content(), L("The bank says no for now: pay your instalments on time to rebuild your score.", "ธนาคารยังไม่อนุมัติ: ผ่อนให้ตรงงวดเพื่อให้เครดิตกลับมาดีก่อนนะ"), 12, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 30) })
	else
		for _, amt in ipairs({ 2000, 5000, 10000, 20000, 40000, 80000 }) do
			if amt <= limit then
				local t6, e6 = Credit.bankTerms(amt, 6, sc)
				local t10, e10 = Credit.bankTerms(amt, 10, sc)
				ui.row("💵", L("Borrow ", "กู้ ") .. Util.money(amt), L(("6 × ฿%d or 10 × ฿%d"):format(e6, e10), ("ผ่อน 6 × ฿%d หรือ 10 × ฿%d"):format(e6, e10)),
					L("Apply", "ยื่นกู้"), function()
						task.spawn(function()
							local n = Choice.ask({ icon = "🏦", title = L("KK Bank personal loan", "สินเชื่อส่วนบุคคล KK Bank"),
								text = L(("Borrow %s now. 6 instalments: total ฿%d · 10 instalments: total ฿%d. One instalment every 12 min of play, auto-debited. Late = ฿%d fee + 30%% of job pay."):format(Util.money(amt), t6, t10, Credit.LATE_FEE),
									("รับเงิน %s ทันที · ผ่อน 6 งวด รวม ฿%d · ผ่อน 10 งวด รวม ฿%d · ตัดอัตโนมัติทุก 12 นาทีที่เล่น · ค้างชำระ ค่าปรับ ฿%d + หักรายได้ 30%%"):format(Util.money(amt), t6, t10, Credit.LATE_FEE)),
								answers = { { L(("6 instalments (฿%d)"):format(e6), ("6 งวด (งวดละ ฿%d)"):format(e6)) }, { L(("10 instalments (฿%d)"):format(e10), ("10 งวด (งวดละ ฿%d)"):format(e10)) }, { L("Not now", "ไว้ก่อน") } } })
							if n == 1 then call("bank_loan", amt .. "|6") elseif n == 2 then call("bank_loan", amt .. "|10") end
						end)
					end, { btnWidth = 64, btnColor = C.blue })
			end
		end
	end
	ui.section(L("MY INSTALMENTS", "ค่างวดของฉัน"))
	local any = false
	for id, l in pairs(d.loans or {}) do
		any = true
		local def = Vehicles.ById[id]
		local name = def and vname(def) or id
		local status = l.repo and L("🚚 REPOSSESSED", "🚚 ถูกยึดอยู่") or (l.missed > 0 and (L("⚠️ ", "⚠️ ค้าง ") .. l.missed .. L(" overdue", " งวด")) or L("on time", "ปกติ"))
		ui.row(def and (def.class == "bike" and "🛵" or "🚗") or "💳", name, ("%d/%d · ฿%d %s · %s"):format(TERMS - l.left, TERMS, l.each, L("each", "ต่องวด"), status),
			L("Pay", "จ่าย"), function() call("loan_pay", id) end,
			{ btnWidth = 60, btnColor = (l.missed > 0 or l.repo) and C.red or C.green, btn2 = { text = L("Pay off", "ปิดยอด"), width = 64, fn = function() call("loan_payoff", id) end } })
	end
	if not any then UI.label(ui.content(), L("No instalments. (Yet.)", "ยังไม่มีหนี้ (ในตอนนี้)"), 13, C.sub, F.med) end
	UI.label(ui.content(), L("An instalment is taken from your cash every 12 minutes of play.", "หักค่างวดจากเงินสดทุก 12 นาทีที่เล่น"), 11, C.sub, F.med, { TextWrapped = true, Size = UDim2.new(1, 0, 0, 28) })
	ui.section(L("RIDE AWAY TODAY (AT KK MOTORS)", "ออกรถวันนี้ (ที่ KK Motors)"))
	local list = {}
	for _, def in pairs(Vehicles.ById) do
		if def.price > 0 and not d.vehicles[def.id] then table.insert(list, def) end
	end
	table.sort(list, function(a, b) return a.price < b.price end)
	for _, def in ipairs(list) do
		local _, each0 = Credit.vehicleTerms(def.price, 0)
		local locked = d.level < def.level
		ui.row(def.class == "bike" and "🛵" or "🚗", vname(def),
			locked and (L("Unlocks at level ", "ปลดล็อกที่เลเวล ") .. def.level) or (L("from ฿", "เริ่ม ฿") .. each0 .. L(" × 10 · cash price ", " × 10 งวด · ราคาเงินสด ") .. Util.money(def.price)),
			L("Finance", "ผ่อนเลย"), function()
				task.spawn(function()
					-- three deals: the more you put down, the smaller the fee and the instalment
					local lines, answers = {}, {}
					for _, p in ipairs(Credit.PLANS) do
						local total, each, dp = Credit.vehicleTerms(def.price, p.down)
						table.insert(lines, L(("%d%% down (%s): %d × ฿%d, total ฿%d"):format(p.down, Util.money(dp), TERMS, each, total + dp),
							("ดาวน์ %d%% (%s): ผ่อน %d × ฿%d รวม ฿%d"):format(p.down, Util.money(dp), TERMS, each, total + dp)))
						table.insert(answers, { L(("%d%% down · ฿%d/mo"):format(p.down, each), ("ดาวน์ %d%% · งวดละ ฿%d"):format(p.down, each)) })
					end
					table.insert(answers, { L("Not today", "ไว้ก่อน") })
					local n = Choice.ask({ icon = "💳", title = vname(def) .. L(": ride away today!", ": ออกรถวันนี้!"),
						text = table.concat(lines, "\n") .. L(("\nCash price %s. Miss 2 instalments and the repo crew comes."):format(Util.money(def.price)),
							("\nราคาเงินสด %s · ค้าง 2 งวด แก๊งยึดรถมาเยือน"):format(Util.money(def.price))),
						answers = answers })
					local plan = n and Credit.PLANS[n]
					if plan then call("loan_buy", def.id .. "|" .. plan.down) end
				end)
			end, { btnWidth = 70, disabled = locked, btnColor = C.orange })
	end
end

---------------------------------------------------------------------------------------------------
-- the repo crew
---------------------------------------------------------------------------------------------------
local chase = nil
local function endChase(caught: boolean)
	local c = chase
	if not c then return end
	chase = nil
	c.truck:Destroy()
	for _, m in ipairs(c.crew) do m:Destroy() end
	if c.gui then c.gui:Destroy() end
	if caught then
		Feedback.toast(L("🚚 Caught! The repo crew took the vehicle", "🚚 โดนจับได้! แก๊งยึดรถเอารถไปแล้ว"), "bad")
		task.spawn(function() Net.call("City", "repo_caught") end)
	end
end

local function startChase()
	if chase then return end
	local c = Drive.current()
	local graph = GPS.graph()
	local kit = ReplicatedStorage:FindFirstChild("GoDashTrafficKit")
	if not c or not graph or not kit then return end
	local tpl = kit:FindFirstChild("pickup_dmax") or kit:FindFirstChild("suv_fortune")
	if not tpl then
		for _, m in ipairs(kit:GetChildren()) do
			local def = Vehicles.ById[m.Name]
			if def and def.class == "car" then tpl = m break end
		end
	end
	if not tpl then return end
	local m = tpl:Clone()
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false end
		if p:IsA("BasePart") and p.Name:find("Body") then p.Color = Color3.fromRGB(24, 24, 28) end
	end
	local y = m:GetAttribute("Y") or 2.5
	local me = c.chassis.Position
	local back = Vector3.new(-c.chassis.CFrame.LookVector.X, 0, -c.chassis.CFrame.LookVector.Z).Unit
	local e, p = graph:nearest(me + back * 120)
	local start = e and Vector3.new(p.X, 0, p.Z) or (me + back * 120)
	m:PivotTo(CFrame.lookAt(start + Vector3.new(0, y, 0), Vector3.new(me.X, y, me.Z)))
	m.Parent = Workspace
	-- the crew: two big guys in black on the bed
	local crew = {}
	local store = ReplicatedStorage:FindFirstChild("GoDashModels")
	if store then
		local cf0, size = m:GetBoundingBox()
		for i, sx in ipairs({ -0.8, 0.8 }) do
			local t = store:FindFirstChild("Ped" .. i) or store:FindFirstChildWhichIsA("Model")
			if t then
				local ok, fig = pcall(RiderPose.build, t, cf0 * CFrame.new(sx, size.Y * 0.1, size.Z * 0.25), nil, "stand")
				if ok and fig then
					RiderPose.dress(fig, Color3.fromRGB(20, 20, 22), Color3.fromRGB(30, 30, 34))
					fig.Parent = m -- moves with the truck
					table.insert(crew, fig)
				end
			end
		end
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(200, 40); bb.StudsOffset = Vector3.new(0, 7, 0); bb.AlwaysOnTop = true; bb.MaxDistance = 400
	bb.Adornee = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
	local tl = Instance.new("TextLabel"); tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1); tl.TextScaled = true; tl.Font = Enum.Font.GothamBlack
	tl.TextColor3 = Color3.fromRGB(255, 60, 60); tl.TextStrokeTransparency = 0.3; tl.Text = L("🚚 REPO CREW", "🚚 แก๊งยึดรถ"); tl.Parent = bb
	bb.Parent = m
	local gui = Instance.new("ScreenGui"); gui.Name = "GoDashRepo"; gui.ResetOnSpawn = false; gui.DisplayOrder = 45
	local banner = Instance.new("TextLabel"); banner.AnchorPoint = Vector2.new(0.5, 0); banner.Position = UDim2.new(0.5, 0, 0, 70); banner.Size = UDim2.fromOffset(460, 34)
	banner.BackgroundColor3 = Color3.fromRGB(150, 20, 24); banner.TextColor3 = Color3.new(1, 1, 1); banner.Font = Enum.Font.GothamBold; banner.TextSize = 16; banner.Parent = gui
	local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 12); corner.Parent = banner
	banner:SetAttribute("NoTranslate", true)
	gui.Parent = player:WaitForChild("PlayerGui")
	chase = { truck = m, crew = crew, y = y, pos = start, path = nil, pathAt = 0, born = os.clock(), close = 0, gui = gui, banner = banner }
	EngineSound.oneShot(nil, Sounds.horn, 0.6, 0.8)
	Feedback.toast(L("🚚 The repo crew is after you! Lose them for 60 s, or pay the arrears in the Finance app", "🚚 แก๊งยึดรถตามมาแล้ว! หนีให้รอด 60 วิ หรือจ่ายค่างวดในแอปไฟแนนซ์"), "bad")
end

local function updateChase(dt: number)
	local ch = chase
	if not ch then return end
	local c = Drive.current()
	local left = 60 - (os.clock() - ch.born)
	ch.banner.Text = L(("🚚 Repo crew! Lose them: %d s · or pay in the Finance app"):format(math.ceil(left)), ("🚚 แก๊งยึดรถ! หนีอีก %d วิ · หรือจ่ายในแอปไฟแนนซ์"):format(math.ceil(left)))
	if left <= 0 then
		endChase(false)
		Feedback.toast(L("😅 You lost them... for now (the instalment is still overdue)", "😅 รอดไปได้... แต่ค่างวดยังค้างอยู่นะ"), "good")
		return
	end
	if not c then return end -- off the vehicle: they wait
	local me = c.chassis.Position
	local graph = GPS.graph()
	if graph and os.clock() - ch.pathAt > 1.2 then
		ch.pathAt = os.clock()
		ch.path = graph:path(ch.pos, me)
		ch.pi = 2
	end
	local target = me
	if ch.path and ch.path[ch.pi or 2] then
		local wp = ch.path[ch.pi]
		if (Vector3.new(wp.X, 0, wp.Z) - Vector3.new(ch.pos.X, 0, ch.pos.Z)).Magnitude < 6 and ch.path[ch.pi + 1] then ch.pi += 1 end
		target = ch.path[ch.pi] or me
	end
	local d = Vector3.new(me.X - ch.pos.X, 0, me.Z - ch.pos.Z).Magnitude
	if d < 40 then target = me end
	local to = Vector3.new(target.X - ch.pos.X, 0, target.Z - ch.pos.Z)
	local mySpeed = Vector3.new(c.chassis.AssemblyLinearVelocity.X, 0, c.chassis.AssemblyLinearVelocity.Z).Magnitude
	-- a slow start (a head start for the rider), then a little faster than you
	local ramp = math.clamp((os.clock() - ch.born) / 8, 0.3, 1)
	local speed = math.clamp(mySpeed * 1.08 + 5, 14, 70) * ramp
	if to.Magnitude > 0.5 then
		ch.pos += to.Unit * math.min(to.Magnitude, speed * dt)
		ch.truck:PivotTo(CFrame.lookAt(ch.pos + Vector3.new(0, ch.y, 0), ch.pos + Vector3.new(0, ch.y, 0) + to.Unit))
	end
	if d < 8 then ch.close += dt else ch.close = math.max(0, ch.close - dt) end
	if ch.close > 1.6 then endChase(true) end
end

function Finance.start()
	Phone.addApp({ id = "finance", name = "Finance", icon = "💳", color = Color3.fromRGB(30, 110, 90),
		badge = function()
			for _, l in pairs(State.data and State.data.loans or {}) do if l.missed > 0 or l.repo then return true end end
			return false
		end }, screen)
	Net.listen("Notify", function(kind)
		if kind == "repo" then
			startChase()
		elseif kind == "repo_end" then
			if chase then
				endChase(false)
				Feedback.toast(L("🚚 Paid. The repo crew turns around", "🚚 จ่ายแล้ว แก๊งยึดรถกลับไปแล้ว"), "good")
			end
		elseif kind == "phone" then
			EngineSound.oneShot(nil, Sounds.phoneRing, 0.5, 1)
		end
	end)
	RunService.Heartbeat:Connect(updateChase)
	-- Studio test hook: Workspace attribute QaRepo = true starts a chase now
	if RunService:IsStudio() then
		Workspace:GetAttributeChangedSignal("QaRepo"):Connect(function()
			if Workspace:GetAttribute("QaRepo") then Workspace:SetAttribute("QaRepo", nil); startChase() end
		end)
	end
end

return Finance
