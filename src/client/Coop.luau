-- The catering-order card (2026-11-19; server/CoopService). While a catering order is open: what, from where to
-- where, how many riders have their share / have delivered, the time left, and a button that routes you to the
-- pick-up (or, once you have your share, to the drop-off).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(script.Parent.UI.Kit)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)
local GPS = require(script.Parent.GPS)

local Coop = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local ORANGE = Color3.fromRGB(230, 120, 30)

function Coop.start()
	local parent = Feedback.top
	if not parent then return end
	local card = UI.new("Frame", { Name = "CoopCard", LayoutOrder = -4, Size = UDim2.fromOffset(300, 64), BackgroundColor3 = Color3.fromRGB(40, 30, 22),
		BackgroundTransparency = 0.08, Visible = false, Parent = parent })
	UI.corner(card, 12)
	UI.stroke(card, ORANGE, 2)
	local title = UI.label(card, "", 14, C.white, F.black, { Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -96, 0, 20) })
	local sub = UI.label(card, "", 12, Color3.fromRGB(255, 220, 170), F.bold, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -96, 0, 18) })
	local line = UI.label(card, "", 11, Color3.fromRGB(220, 220, 220), F.med, { Position = UDim2.fromOffset(10, 42), Size = UDim2.new(1, -96, 0, 16) })
	for _, l in ipairs({ title, sub, line }) do l:SetAttribute("NoTranslate", true); UI.fitText(l, l.TextSize, 9) end
	local target: Vector3? = nil
	local targetName = ""
	local btn = UI.button(card, L("Route", "นำทาง"), { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(78, 36),
		TextSize = 13, BackgroundColor3 = ORANGE }, function()
		if target then GPS.setTarget(target, targetName) end
	end)
	btn:SetAttribute("NoTranslate", true)
	local f = ReplicatedStorage:WaitForChild("GoDashCoop", 300)
	if not f then return end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.3 then return end
		acc = 0
		local mine = player:GetAttribute("Coop")
		local on = f:GetAttribute("Active") == true and mine ~= "delivered" and not State.cutscene
		card.Visible = on
		if not on then return end
		local th = Lang.code == "th"
		local pickName = th and f:GetAttribute("PickupThai") or f:GetAttribute("PickupName") or ""
		local dropName = th and f:GetAttribute("DropThai") or f:GetAttribute("DropName") or ""
		local need, joined, delivered = f:GetAttribute("Need") or 0, f:GetAttribute("Joined") or 0, f:GetAttribute("Delivered") or 0
		local left = math.max(0, (f:GetAttribute("EndsAt") or 0) - Workspace:GetServerTimeNow())
		local clock = ("%d:%02d"):format(left // 60, math.floor(left % 60))
		title.Text = L(("🍱 Catering · %d boxes"):format(f:GetAttribute("Boxes") or 0), ("🍱 จัดเลี้ยง · %d กล่อง"):format(f:GetAttribute("Boxes") or 0))
		line.Text = pickName .. "  →  " .. dropName
		if f:GetAttribute("Stage") == "gather" then
			sub.Text = L(("Team %d/%d · join within %s"):format(joined, need, clock), ("รวมทีม %d/%d คน · รับของภายใน %s"):format(joined, need, clock))
		else
			sub.Text = L(("Delivered %d/%d · %s left"):format(delivered, joined, clock), ("ส่งแล้ว %d/%d คน · เหลือ %s"):format(delivered, joined, clock))
		end
		if mine == "joined" then
			target, targetName = f:GetAttribute("DropPos"), dropName
			btn.Text = L("To drop-off", "ไปส่ง")
		else
			target, targetName = f:GetAttribute("PickupPos"), pickName
			btn.Text = f:GetAttribute("Stage") == "gather" and L("Join", "ไปรับ") or L("Closed", "ปิดแล้ว")
		end
	end)
end

return Coop
