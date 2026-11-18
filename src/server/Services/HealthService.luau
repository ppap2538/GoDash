-- Injuries (2026-11-18). Owner: "if you fall and the injuries add up you have to see a doctor: the map
-- needs the way to the hospital, and a cutscene of the wound being treated, more realism".
--
--   * a fall from a two-wheeler (a crash that throws you off, a speed bump at full speed) adds 8-35
--     points by speed; a hard car crash 3-15 (seatbelt). d.injury is 0-100, the player attribute
--     "Injury" mirrors it for the client.
--   * small knocks heal on their own (1 point every HEAL_EVERY seconds of play) but not from SERIOUS up:
--     those need a doctor.
--   * what it does: from LIMP the rider limps and cannot run (client/OnFoot); from SERIOUS the Guide
--     card asks for the hospital; from MUST no new orders until treated (JobService asks Health.blocked).
--   * Khon Kaen Hospital (ShopService "heal"): the gold card fee (฿30, Thailand's 30-baht scheme) plus
--     the medicine, which grows with the wound (about ฿30-250, a delivery or two), and a long queue:
--     client/Cutscene "treat" shows the queue ticket, the nurse dressing the wound and the receipt.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)
local Data = require(script.Parent.PlayerDataService)
local Gear = require(game:GetService("ReplicatedStorage").Shared.Config.Gear)

local Health = {}
Health.LIMP = 25
Health.SERIOUS = 60
Health.MUST = 80
Health.HEAL_EVERY = 90
Health.CARD_FEE = 30 -- the gold card visit

local function set(player: Player, d, value: number)
	d.injury = math.clamp(math.floor(value + 0.5), 0, 100)
	Data.touch(player, "injury")
	player:SetAttribute("Injury", d.injury)
end

function Health.get(player: Player): number
	local d = Data.get(player)
	return d and (d.injury or 0) or 0
end

-- A fall or a hard crash. kind = "bike" | "car", speed in studs/s.
function Health.injure(player: Player, kind: string, speed: number)
	local d = Data.get(player)
	if not d then return end
	local add = kind == "car" and math.clamp(3 + speed * 0.1, 3, 15) or math.clamp(8 + speed * 0.25, 8, 35)
	-- (2026-11-19) on two wheels the helmet matters (Config/Gear): a good one halves it, none makes it worse
	if kind ~= "car" then
		local helmet = Gear.worn(d.gear, "helmet")
		add = math.floor(add * (helmet and helmet.protect or 1.25) + 0.5)
	end
	local before = d.injury or 0
	set(player, d, before + add)
	local now = d.injury
	local en, th
	if now >= Health.MUST then
		en, th = ("🩹 Badly hurt (%d). Go to the hospital before taking more orders"):format(now), ("🩹 บาดเจ็บหนัก (%d) ไปโรงพยาบาลก่อนนะ ถึงจะรับงานต่อได้"):format(now)
	elseif now >= Health.SERIOUS then
		en, th = ("🩹 Hurt (%d). It won't heal by itself: see a doctor"):format(now), ("🩹 เจ็บพอสมควร (%d) แผลแบบนี้ไม่หายเอง แวะหาหมอนะ"):format(now)
	else
		en, th = ("🩹 Scraped and bruised: injury %d"):format(now), ("🩹 ถลอกฟกช้ำ บาดเจ็บสะสม %d"):format(now)
	end
	task.delay(4, function() -- after the crash scene
		if player.Parent then Net.fire(player, "Notify", "toast", { text = en, th = th, bad = true }) end
	end)
end

-- Treated at the hospital: what it cost. nil when there is nothing to treat.
function Health.treatCost(player: Player): number?
	local inj = Health.get(player)
	if inj < 1 then return nil end
	return Health.CARD_FEE + math.floor(inj * 2.2 / 10 + 0.5) * 10
end

function Health.heal(player: Player)
	local d = Data.get(player)
	if d then set(player, d, 0) end
end

-- JobService: no new orders while badly hurt
function Health.blocked(player: Player): boolean
	return Health.get(player) >= Health.MUST
end

function Health.start()
	Data.onLoaded(function(player, d)
		d.injury = tonumber(d.injury) or 0
		player:SetAttribute("Injury", d.injury)
	end)
	-- small knocks heal with time; serious ones wait for a doctor
	task.spawn(function()
		local acc = {} :: { [Player]: number }
		while true do
			task.wait(10)
			for _, player in ipairs(Players:GetPlayers()) do
				local d = Data.get(player)
				local inj = d and d.injury or 0
				if inj > 0 and inj < Health.SERIOUS then
					acc[player] = (acc[player] or 0) + 10
					if acc[player] >= Health.HEAL_EVERY then
						acc[player] = 0
						set(player, d, inj - 1)
					end
				end
			end
			for p in pairs(acc) do if not p.Parent then acc[p] = nil end end
		end
	end)
end

return Health
