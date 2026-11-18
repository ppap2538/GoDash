-- Credit, loans and instalments (2026-11-18, owner: "bank loans and paying debt back, so it really is a
-- life sim, or a down payment and instalments for a vehicle"). Shared by server/FinanceService (the
-- rules) and client/Finance (what the app shows), so the numbers on screen are the numbers charged.
--
--   credit score  300-850, everyone starts at START. On time +, late -, paid off ++. It sets how much
--                 the bank lends and at what rate (like a credit bureau check).
--   vehicles      KK Motors: 0 / 25 / 50 % down; the financing fee falls with a bigger down payment.
--                 TERMS instalments, one every PERIOD seconds of play.
--   bank loan     KK Bank personal loan: 6 or 10 instalments, auto-debit from cash and then savings.
--                 A missed one costs LATE_FEE and credit; while in arrears GARNISH of every job's pay
--                 goes to the bank first (like a salary deduction order).
local Credit = {}

Credit.START, Credit.MIN, Credit.MAX = 650, 300, 850
Credit.PERIOD = 12 * 60
Credit.TERMS = 10

Credit.PLANS = {
	{ down = 0, fee = 0.35 }, -- the old "0% down" deal
	{ down = 25, fee = 0.20 },
	{ down = 50, fee = 0.10 },
}

function Credit.plan(down: number)
	for _, p in ipairs(Credit.PLANS) do
		if p.down == down then return p end
	end
	return nil
end

-- total to pay in instalments, each instalment, the down payment
function Credit.vehicleTerms(price: number, down: number): (number, number, number)
	local p = Credit.plan(down) or Credit.PLANS[1]
	local dp = math.floor(price * p.down / 100)
	local total = math.ceil((price - dp) * (1 + p.fee))
	return total, math.ceil(total / Credit.TERMS), dp
end

Credit.BANK_MIN, Credit.BANK_MAX = 1000, 80000
Credit.BANK_TERMS = { 6, 10 }
Credit.MIN_SCORE = 450 -- below this the bank says no
Credit.LATE_FEE = 50
Credit.GARNISH = 0.3

function Credit.limit(level: number, score: number): number
	local base = 3000 + level * 2000
	local k = math.clamp((score - 400) / 250, 0.3, 1.4)
	return math.min(Credit.BANK_MAX, math.floor(base * k / 500) * 500)
end

-- interest over the whole loan (flat): a good score pays less, a short loan pays less
function Credit.rate(score: number, n: number): number
	local r = math.clamp(0.28 - (score - 500) / 1000, 0.06, 0.32)
	return n == 6 and r * 0.65 or r
end

function Credit.bankTerms(amount: number, n: number, score: number): (number, number)
	local total = math.ceil(amount * (1 + Credit.rate(score, n)))
	return total, math.ceil(total / n)
end

-- a word and a colour for the score
function Credit.grade(score: number): (string, string, Color3)
	if score >= 760 then return "Excellent", "ดีมาก", Color3.fromRGB(46, 170, 90) end
	if score >= 680 then return "Good", "ดี", Color3.fromRGB(90, 170, 60) end
	if score >= 580 then return "Fair", "พอใช้", Color3.fromRGB(230, 160, 30) end
	return "Poor", "เสี่ยง", Color3.fromRGB(210, 60, 50)
end

return Credit
