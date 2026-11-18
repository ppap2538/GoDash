-- Tickets and accident bills with a daily limit (2026-11-19, owner: "โดนปรับเงินถี่เกิน ขับไม่คุ้ม",
-- "มันต้องมี limit การปรับต่อวัน": fined so often that driving did not pay, there must be a daily limit).
--   * tickets (red light, zebra crossing, riding on the pavement, police checkpoint): at most TICKETS in
--     one in-game day (Config/Game DAY_LENGTH, 16 real minutes) and never two within TICKET_GAP seconds
--   * accident bills (hitting a person or a car, server/AccidentService): at most BILLS in one in-game
--     day, BILL_GAP seconds apart
--   * both together: never more than DAY_CASH in one real day (Thai time, kept in the profile's daily)
-- Past a limit the police only warn and the other side of an accident lets it go: no money and no
-- pulled-over scene, a toast only. The trip still counts the offence for its safety (tele.red), so a
-- careless ride still loses its safe-ride bonus.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Economy = require(script.Parent.EconomyService)
local Time = require(script.Parent.TimeService)

local Fines = {}
Fines.TICKETS = 2
Fines.TICKET_GAP = 180
Fines.BILLS = 2
Fines.BILL_GAP = 90
Fines.DAY_CASH = 600
local WARN_GAP = 12 -- seconds between two warning toasts, so a careless stretch is not a wall of them

local state = {} -- [player] = { day = in-game day, ticket = { n, at }, bill = { n, at }, warnAt }
Players.PlayerRemoving:Connect(function(p) state[p] = nil end)

local function get(player: Player)
	local day = Time.day()
	local st = state[player]
	if not st or st.day ~= day then
		st = { day = day, ticket = { n = 0, at = -1e9 }, bill = { n = 0, at = -1e9 }, warnAt = st and st.warnAt or -1e9 }
		state[player] = st
	end
	return st
end

-- Decide and take the money. kind = "ticket" | "bill". Returns:
--   ok (false = let off: show a warning), the amount taken (0 when the pocket is empty),
--   why ("limit" | "gap" | "cash") when let off, and the count / limit after this one.
function Fines.charge(player: Player, kind: string, amount: number, reason: string): (boolean, number, string?, number, number)
	local st = get(player)
	local k = st[kind] or st.ticket
	local limit = kind == "bill" and Fines.BILLS or Fines.TICKETS
	local gap = kind == "bill" and Fines.BILL_GAP or Fines.TICKET_GAP
	local qaGap = RunService:IsStudio() and Workspace:GetAttribute("QaFineGap") -- QA hook: a short gap for play tests
	if type(qaGap) == "number" then gap = qaGap end
	local d = Data.get(player)
	if not d then return false, 0, "limit", k.n, limit end
	-- QA hook (clip recording in Studio): Workspace QaNoLimit = true -> every fine "charges" its full amount on
	-- the card, but no money moves and nothing is counted (Studio Play uses the real profile)
	if RunService:IsStudio() and Workspace:GetAttribute("QaNoLimit") then
		return true, math.max(0, math.floor(amount)), nil, math.min(k.n + 1, limit), limit
	end
	if k.n >= limit then return false, 0, "limit", k.n, limit end
	if os.clock() - k.at < gap then return false, 0, "gap", k.n, limit end
	Economy.rollDay(d)
	local paid = tonumber(d.daily.fines) or 0
	if paid >= Fines.DAY_CASH then return false, 0, "cash", k.n, limit end
	local take = math.max(0, math.min(math.floor(amount), Fines.DAY_CASH - paid, math.floor(d.money)))
	if take > 0 then Economy.spend(player, take, reason) end
	k.n += 1
	k.at = os.clock()
	d.daily.fines = paid + take
	Data.touch(player, "daily")
	return true, take, nil, k.n, limit
end

-- The toast when someone is let off. what / whatTh name the offence ("🚦 Ran a red light").
function Fines.warn(player: Player, kind: string, why: string?, what: string, whatTh: string)
	local st = get(player)
	if os.clock() - st.warnAt < WARN_GAP then return end
	st.warnAt = os.clock()
	local en, th
	if kind == "bill" then
		en, th = "🤝 They let it go this time: no bill", "🤝 คู่กรณีไม่เอาเรื่อง ครั้งนี้ไม่ต้องจ่าย"
	elseif why == "gap" then
		en, th = "a warning only (you were just fined)", "ตักเตือนครั้งนี้ (เพิ่งโดนใบสั่งไป)"
	elseif why == "cash" then
		en, th = ("a warning only (today's fines reached ฿%d)"):format(Fines.DAY_CASH), ("ตักเตือนครั้งนี้ (วันนี้จ่ายค่าปรับครบ ฿%d แล้ว)"):format(Fines.DAY_CASH)
	else
		en, th = ("a warning only (today's %d tickets are used up)"):format(Fines.TICKETS), ("ตักเตือนครั้งนี้ (วันนี้โดนใบสั่งครบ %d ใบแล้ว)"):format(Fines.TICKETS)
	end
	if kind ~= "bill" then en, th = what .. ": " .. en, whatTh .. ": " .. th end
	Net.fire(player, "Notify", "toast", { text = en, th = th })
end

-- "(ticket 1/2 today)" to add to a ticket's toast
function Fines.countText(n: number, limit: number): (string, string)
	return (" · ticket %d/%d today"):format(n, limit), (" · ใบสั่งวันนี้ %d/%d"):format(n, limit)
end

return Fines
