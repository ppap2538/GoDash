-- Instalments at KK Motors (owner, 2026-11-17: satire of Thai consumer debt). "0% down, 0% interest*,
-- no guarantor!" (*plus a 35% financing fee). Ride away today, pay ten instalments, one every
-- PERIOD seconds of play (never while offline). The instalment is taken from your cash when due; if
-- the cash is not there it is missed: the finance company calls, the City Feed gossips, and at two
-- missed instalments the repo crew comes for the vehicle (client/Finance chases you; a parked
-- vehicle is simply towed). Paying the arrears in the Finance app brings it back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Net)
local Util = require(Shared.Util)
local Vehicles = require(Shared.Config.Vehicles)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local City = require(script.Parent.CityRemote)

-- 2026-11-18: down payments (0 / 25 / 50 %), a credit score and KK Bank personal loans; the numbers live
-- in Config/Credit so the app shows exactly what is charged.
local Credit = require(Shared.Config.Credit)

local Finance = {}
Finance.TERMS = Credit.TERMS
Finance.PERIOD = Credit.PERIOD
local MAX_LOANS = 2

local function toast(player: Player, en: string, th: string, bad: boolean?)
	Net.fire(player, "Notify", "toast", { text = en, th = th, bad = bad, good = not bad })
end
local function feed(player: Player, key: string)
	Net.fire(player, "Notify", "feed", { key = key })
end

function Finance.terms(def, down: number?)
	local total, each = Credit.vehicleTerms(def.price, down or 0)
	return total, each
end

local function score(player: Player, d, delta: number)
	d.credit = math.clamp((tonumber(d.credit) or Credit.START) + delta, Credit.MIN, Credit.MAX)
	Data.touch(player, "credit")
end
Finance.score = score

-- what is owed to the bank right now (missed instalments + late fees), and the whole rest
local function arrears(bl): number
	return bl.each * bl.missed + (bl.fee or 0)
end
Finance.arrears = arrears

-- EconomyService: while a bank loan is in arrears, part of every job's pay goes to the bank first.
-- Returns what was taken.
function Finance.garnish(player: Player, d, amount: number): number
	local bl = d.bankLoan
	if not bl or bl.missed <= 0 then return 0 end
	local owed = arrears(bl)
	local take = math.min(owed, math.floor(amount * Credit.GARNISH))
	if take <= 0 then return 0 end
	-- fees first, then whole instalments
	local fee = math.min(bl.fee or 0, take)
	bl.fee = (bl.fee or 0) - fee
	bl.paidPart = (bl.paidPart or 0) + (take - fee)
	while bl.missed > 0 and bl.paidPart >= bl.each do
		bl.paidPart -= bl.each
		bl.missed -= 1
		bl.left -= 1
	end
	if bl.left <= 0 then d.bankLoan = false end
	Data.touch(player, "bankLoan")
	return take
end

function Finance.isRepo(player: Player, vehicleId: string): boolean
	local d = Data.get(player)
	local l = d and d.loans and d.loans[vehicleId]
	return l ~= nil and l.repo == true
end

function Finance.start(world, deps)
	local vehicles = deps.vehicles
	local missions = deps.missions

	local function nearDealer(player: Player): boolean
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		for _, poi in pairs(world.pois) do
			if poi.kind == "dealer" and Util.flatDist(root.Position, poi.pos) < math.max(poi.w or 60, poi.d or 60) / 2 + 60 then return true end
		end
		return false
	end

	local function payOff(player: Player, d, id: string)
		d.loans[id] = nil
		toast(player, "🎉 Paid off! The vehicle is all yours now", "🎉 ผ่อนหมดแล้ว! รถเป็นของเราเต็มตัว")
		feed(player, "loan_paid")
	end

	-- arg = "<vehicle id>" (0% down, as before) or "<vehicle id>|<down %>"
	City.register("loan_buy", function(player, arg)
		local d = Data.get(player)
		local id, downS = tostring(arg or ""):match("^([%w_]+)|?(%d*)$")
		local down = tonumber(downS) or 0
		local def = id and Vehicles.ById[id]
		if not d or not def or def.price <= 0 then return false, "Unknown vehicle" end
		if not Credit.plan(down) then return false, "Bad request" end
		if d.vehicles[def.id] then return false, "You already own it" end
		if d.level < def.level then return false, "Reach level " .. def.level .. " first" end
		local n = 0
		for _ in pairs(d.loans) do n += 1 end
		if n >= MAX_LOANS then return false, "Two loans at once is the limit (even this finance company has rules)" end
		if not nearDealer(player) then return false, "Visit KK Motors to buy vehicles" end
		if (tonumber(d.credit) or Credit.START) < Credit.MIN_SCORE and down == 0 then
			return false, "Credit score too low for 0% down: put some money down"
		end
		local total, each, dp = Credit.vehicleTerms(def.price, down)
		if dp > 0 and not Economy.spend(player, dp, "down_payment") then return false, "The down payment is " .. Util.money(dp) end
		d.vehicles[def.id] = Vehicles.newOwned(def)
		d.loans[def.id] = { left = Finance.TERMS, each = each, total = total, timer = Finance.PERIOD, missed = 0, repo = false, down = down }
		Data.touch(player, "vehicles", "loans")
		missions.progress(player, "buy_vehicle", 1)
		Net.fire(player, "Notify", "bigwin", { title = "New vehicle!", text = def.name, icon = def.class == "bike" and "🛵" or "🚗" })
		feed(player, "loan_buy")
		return true, ("Drove off in the %s: %s down, %d × ฿%d"):format(def.name, Util.money(dp), Finance.TERMS, each)
	end)

	-- KK Bank personal loan: arg = "<amount>|<instalments>"
	City.register("bank_loan", function(player, arg)
		local d = Data.get(player)
		if not d then return false, "Not ready" end
		local a, t = tostring(arg or ""):match("^(%d+)|(%d+)$")
		local amount, terms = tonumber(a), tonumber(t)
		if not amount or (terms ~= 6 and terms ~= 10) then return false, "Bad request" end
		if d.bankLoan then return false, "Pay off your current loan first" end
		local sc = tonumber(d.credit) or Credit.START
		if sc < Credit.MIN_SCORE then return false, "The bank says no: credit score too low. Pay your instalments on time first" end
		local limit = Credit.limit(d.level, sc)
		if amount < Credit.BANK_MIN or amount > limit then return false, "Your credit limit is " .. Util.money(limit) end
		local total, each = Credit.bankTerms(amount, terms, sc)
		d.bankLoan = { principal = amount, total = total, each = each, terms = terms, left = terms, timer = Finance.PERIOD, missed = 0, fee = 0, paidPart = 0 }
		Data.touch(player, "bankLoan")
		Economy.add(player, amount, "bank_loan")
		feed(player, "bank_loan")
		return true, ("Approved! %s now, %d × ฿%d"):format(Util.money(amount), terms, each)
	end)

	-- pay what is overdue, or the next instalment early
	City.register("bank_pay", function(player)
		local d = Data.get(player)
		local bl = d and d.bankLoan
		if not bl then return false, "No bank loan" end
		local count = math.min(math.max(1, bl.missed), bl.left)
		local amount = bl.each * count + (bl.fee or 0) - (bl.paidPart or 0)
		if not Economy.spend(player, amount, "bank_loan") then return false, "Not enough cash (" .. Util.money(amount) .. ")" end
		bl.left -= count
		local late = bl.missed > 0
		bl.missed, bl.fee, bl.paidPart = 0, 0, 0
		bl.timer = Finance.PERIOD
		if not late then score(player, d, 3) end
		if bl.left <= 0 then
			d.bankLoan = false
			score(player, d, 15)
			toast(player, "🏦 Loan paid off! Your credit score went up", "🏦 ปิดหนี้ธนาคารแล้ว! เครดิตดีขึ้น")
		end
		Data.touch(player, "bankLoan")
		return true, "Paid " .. Util.money(amount)
	end)

	-- close it now: the rest of the instalments, minus half the interest not yet due
	City.register("bank_payoff", function(player)
		local d = Data.get(player)
		local bl = d and d.bankLoan
		if not bl then return false, "No bank loan" end
		local rest = bl.each * bl.left + (bl.fee or 0) - (bl.paidPart or 0)
		local interestLeft = (bl.total - bl.principal) * (bl.left / bl.terms)
		local amount = math.max(0, math.floor(rest - interestLeft * 0.5))
		if not Economy.spend(player, amount, "bank_loan") then return false, "Paying it off costs " .. Util.money(amount) end
		d.bankLoan = false
		Data.touch(player, "bankLoan")
		score(player, d, bl.missed > 0 and 5 or 15)
		return true, "Loan closed for " .. Util.money(amount)
	end)

	City.register("loan_pay", function(player, id)
		local d = Data.get(player)
		local l = d and id and d.loans[id]
		if not l then return false, "No loan on that vehicle" end
		local count = math.max(1, l.missed)
		count = math.min(count, l.left)
		local amount = l.each * count
		if not Economy.spend(player, amount, "loan") then return false, "Not enough money" end
		l.left -= count
		l.missed = 0
		local wasRepo = l.repo
		l.repo = false
		if l.left <= 0 then payOff(player, d, id) end
		Data.touch(player, "loans")
		Net.fire(player, "Notify", "repo_end", {})
		return true, (wasRepo and "Paid. The vehicle is released: " or "Paid: ") .. "฿" .. amount
	end)

	City.register("loan_payoff", function(player, id)
		local d = Data.get(player)
		local l = d and id and d.loans[id]
		if not l then return false, "No loan on that vehicle" end
		local amount = l.each * l.left
		if not Economy.spend(player, amount, "loan") then return false, "Not enough money" end
		payOff(player, d, id)
		Data.touch(player, "loans")
		Net.fire(player, "Notify", "repo_end", {})
		return true, "Paid off: ฿" .. amount
	end)

	-- the client's repo chase ended with the truck catching you
	City.register("repo_caught", function(player)
		local d = Data.get(player)
		if not d then return false end
		local v = vehicles.get(player)
		local took = false
		for id, l in pairs(d.loans) do
			if l.missed >= 2 then
				l.repo = true
				took = true
				if v and v.id == id then vehicles.despawn(player) end
			end
		end
		if not took then return false, "" end
		Data.touch(player, "loans")
		feed(player, "loan_repo")
		return true, "The vehicle was repossessed"
	end)

	-- instalments fall due with play time
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do
				local d = Data.get(player)
				if d and d.loans then
					for id, l in pairs(d.loans) do
						if not l.repo then
							l.timer -= 10
							if l.timer <= 0 then
								l.timer = Finance.PERIOD
								local def = Vehicles.ById[id]
								local name = def and def.name or id
								if Economy.spend(player, l.each, "loan") then
									l.left -= 1
									score(player, d, 2)
									toast(player, ("💳 Instalment for the %s: −฿%d (%d left)"):format(name, l.each, l.left),
										("💳 หักค่างวด %s −฿%d (เหลือ %d งวด)"):format(def and def.thai or name, l.each, l.left))
									if l.left <= 0 then payOff(player, d, id); score(player, d, 10) end
								else
									l.missed += 1
									score(player, d, -30)
									Net.fire(player, "Notify", "phone", {})
									toast(player, ("📞 Finance company: 'You're %d instalment(s) behind on the %s...'"):format(l.missed, name),
										("📞 ไฟแนนซ์โทรมา: 'คุณค้างค่างวด %s %d งวดนะคะ...'"):format(def and def.thai or name, l.missed), true)
									feed(player, "loan_late")
									if l.missed >= 2 then
										local v = vehicles.get(player)
										if v and v.id == id and vehicles.driving(player) then
											Net.fire(player, "Notify", "repo", { id = id }) -- client/Finance: the chase
										else
											l.repo = true
											if v and v.id == id then vehicles.despawn(player) end
											toast(player, "🚚 Your " .. name .. " was towed away by the repo crew. Pay the arrears in the Finance app",
												"🚚 " .. (def and def.thai or name) .. " ถูกแก๊งยึดรถลากไปแล้ว จ่ายค่างวดที่ค้างในแอปไฟแนนซ์", true)
											feed(player, "loan_repo")
										end
									end
								end
								Data.touch(player, "loans")
							end
						end
					end
				end
			end
		end
	end)
	-- KK Bank: auto-debit from cash, then from savings; missed = late fee, credit down, a call from the
	-- bank, and a share of job pay until the arrears are cleared (EconomyService -> Finance.garnish)
	task.spawn(function()
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do
				local d = Data.get(player)
				local bl = d and d.bankLoan
				if bl then
					bl.timer -= 10
					if bl.timer <= 0 then
						bl.timer = Finance.PERIOD
						local due = bl.each - (bl.paidPart or 0)
						local fromCash = math.min(d.money, due)
						local fromSavings = math.min(d.bank or 0, due - fromCash)
						if fromCash + fromSavings >= due then
							if fromCash > 0 then Economy.spend(player, fromCash, "bank_loan") end
							if fromSavings > 0 then d.bank -= fromSavings; Data.touch(player, "bank") end
							bl.paidPart = 0
							bl.left -= 1
							score(player, d, 3)
							toast(player, ("🏦 KK Bank instalment −฿%d%s (%d left)"):format(due, fromSavings > 0 and " (from savings)" or "", bl.left),
								("🏦 ตัดชำระสินเชื่อ −฿%d%s (เหลือ %d งวด)"):format(due, fromSavings > 0 and " (ตัดจากบัญชีออมทรัพย์)" or "", bl.left))
							if bl.left <= 0 then
								d.bankLoan = false
								score(player, d, 15)
								toast(player, "🏦 Loan paid off! Your credit score went up", "🏦 ปิดหนี้ธนาคารแล้ว! เครดิตดีขึ้น")
							end
						else
							bl.missed += 1
							bl.fee = (bl.fee or 0) + Credit.LATE_FEE
							score(player, d, -35)
							Net.fire(player, "Notify", "phone", {})
							toast(player, ("📞 KK Bank: 'You missed an instalment (late fee ฿%d). Until it's paid, 30%% of each job goes to us.'"):format(Credit.LATE_FEE),
								("📞 ธนาคารโทรมา: 'ค้างชำระค่ะ (ค่าปรับล่าช้า ฿%d) ระหว่างนี้หักรายได้ 30%% ทุกงานนะคะ'"):format(Credit.LATE_FEE), true)
							feed(player, "bank_late")
						end
						Data.touch(player, "bankLoan")
					end
				end
			end
		end
	end)
	-- Studio QA: Workspace QaBankDue = true -> every bank loan falls due now
	if game:GetService("RunService"):IsStudio() then
		game:GetService("Workspace"):GetAttributeChangedSignal("QaBankDue"):Connect(function()
			if not game:GetService("Workspace"):GetAttribute("QaBankDue") then return end
			game:GetService("Workspace"):SetAttribute("QaBankDue", nil)
			for _, p in ipairs(Players:GetPlayers()) do
				local d = Data.get(p)
				if d and d.bankLoan then d.bankLoan.timer = 0 end
			end
		end)
	end
end

return Finance
