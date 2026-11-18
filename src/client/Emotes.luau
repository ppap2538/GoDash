-- Emotes (2026-11-19, owner: "ท่าทาง: ไหว้ เต้น ชูสองนิ้ว ถ่ายเซลฟี่"). G on a keyboard, or the 😀 button.
--   * Roblox's own R15 emote animations: wave, dance (three, in turn), laugh, cheer. Played on your own
--     character, so everyone sees them without any help.
--   * Thai poses: ไหว้ (wai), ชูสองนิ้ว (peace sign), เซลฟี่ (selfie with a phone). The server marks the pose
--     on the character (server/EmoteService: "Emote", "EmoteAt"), and every client, this one included,
--     bends the joints of every posed character here (joint poses never replicate). Written in
--     PreSimulation like client/Rider, so it wins over the Animator for the joints it uses.
-- Any emote stops when you walk, jump or sit.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UI = require(script.Parent.UI.Kit)
local Layers = require(script.Parent.UI.Core.Layers)
local Lang = require(script.Parent.Lang)
local State = require(script.Parent.State)
local Drive = require(script.Parent.Drive)
local UIState = require(script.Parent.UI.Core.UIState)
local JobCard = require(script.Parent.UI.HUD.JobCard)

local Emotes = {}
local C, F = UI.C, UI.F
local L = Lang.pick
local player = Players.LocalPlayer
local A = CFrame.Angles
local rad = math.rad
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local LIST = {
	{ id = "wai", icon = "🙏", en = "Wai", th = "ไหว้", pose = true },
	{ id = "peace", icon = "✌️", en = "Peace", th = "ชูสองนิ้ว", pose = true },
	{ id = "selfie", icon = "🤳", en = "Selfie", th = "เซลฟี่", pose = true },
	{ id = "wave", icon = "👋", en = "Wave", th = "โบกมือ", anim = { "rbxassetid://507770239" } },
	{ id = "dance", icon = "💃", en = "Dance", th = "เต้น", anim = { "rbxassetid://507771019", "rbxassetid://507776043", "rbxassetid://507777268" }, loop = true },
	{ id = "laugh", icon = "😂", en = "Laugh", th = "หัวเราะ", anim = { "rbxassetid://507770818" } },
	{ id = "cheer", icon = "🙌", en = "Cheer", th = "เชียร์", anim = { "rbxassetid://507770677" } },
}

-- joint angles per pose, degrees { X, Z } in the R15 joint frames: +X swings a limb forward / up, waist
-- -X leans forward, neck -X nods; on Z the right arm goes out with +, the left arm with - (seen in a play
-- test 2026-11-19: the first wai had the signs the other way round and opened the arms like wings)
local POSES = {
	wai = { waist = { -8, 0 }, neck = { -14, 0 }, rs = { 26, -26 }, ls = { 26, 26 }, re = { 120, 0 }, le = { 120, 0 } },
	peace = { neck = { 4, 7 }, rs = { 95, 35 }, re = { 115, 0 }, ls = { 8, -6 }, le = { 30, 0 } },
	-- right arm out in front holding the phone at arm's length, left hand a peace sign by the face
	selfie = { neck = { 6, -10 }, rs = { 95, 12 }, re = { 8, 0 }, ls = { 95, -35 }, le = { 115, 0 } },
}
local BLEND = 0.25 -- seconds to ease into a pose

---------------------------------------------------------------------------------------------------
-- drawing the poses (every posed character this client can see)
---------------------------------------------------------------------------------------------------
local function motor(char: Model, part: string, name: string): any
	local p = char:FindFirstChild(part)
	local m = p and p:FindFirstChild(name)
	if m and (m:IsA("Motor6D") or m:IsA("AnimationConstraint")) then return m end
	return nil
end

local posed = {} :: { [Model]: any } -- [character] = { id, at, J, props }

local function rig(char: Model): any
	if not char:FindFirstChild("UpperTorso") then return nil end
	return {
		waist = motor(char, "UpperTorso", "Waist"), neck = motor(char, "Head", "Neck"),
		rs = motor(char, "RightUpperArm", "RightShoulder"), ls = motor(char, "LeftUpperArm", "LeftShoulder"),
		re = motor(char, "RightLowerArm", "RightElbow"), le = motor(char, "LeftLowerArm", "LeftElbow"),
	}
end

local function badge(char: Model, partName: string, text: string, size: number, offset: Vector3): BillboardGui?
	local part = char:FindFirstChild(partName)
	if not part then return nil end
	local g = Instance.new("BillboardGui")
	g.Name = "GoDashEmoteBadge"
	g.Size = UDim2.fromOffset(size, size)
	-- camera space, a stud toward the viewer: a play test showed the ✌️ hidden inside the raised hand
	g.StudsOffset = offset + Vector3.new(0, 0, 1)
	g.AlwaysOnTop = false
	g.LightInfluence = 0
	g.MaxDistance = 120
	g.Adornee = part
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.5
	t.Text = text
	t:SetAttribute("NoTranslate", true)
	t.Parent = g
	g.Parent = part
	return g
end

local function props(char: Model, id: string): { Instance }
	local out = {}
	if id == "selfie" then
		local hand = char:FindFirstChild("RightHand") :: BasePart?
		if hand then
			local phone = Instance.new("Part")
			phone.Name = "GoDashSelfiePhone"
			phone.Size = Vector3.new(0.5, 0.95, 0.1)
			phone.Color = Color3.fromRGB(28, 30, 34)
			phone.Material = Enum.Material.SmoothPlastic
			phone.CanCollide, phone.CanQuery, phone.CanTouch, phone.Massless = false, false, false, true
			-- with the arm held out (shoulder 95 deg) the hand's -Y points ahead and its -Z points up: the phone
			-- stands upright just past the fingers with its screen toward the face (hand +Y)
			phone.CFrame = hand.CFrame * CFrame.new(0, -0.55, 0) * CFrame.Angles(math.rad(-90), 0, 0)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = hand, phone
			w.Parent = phone
			phone.Parent = char
			table.insert(out, phone)
		end
		local b = badge(char, "LeftHand", "✌️", 30, Vector3.new(0, 0.6, 0))
		if b then table.insert(out, b) end
	elseif id == "peace" then
		local b = badge(char, "RightHand", "✌️", 34, Vector3.new(0, 0.6, 0))
		if b then table.insert(out, b) end
	elseif id == "wai" then
		local b = badge(char, "Head", L("🙏 Sawasdee", "🙏 สวัสดีครับ"), 40, Vector3.new(0, 2.2, 0))
		if b then
			b.Size = UDim2.fromOffset(150, 34)
			table.insert(out, b)
		end
	end
	return out
end

local function release(char: Model, st)
	for _, k in ipairs({ "waist", "neck", "rs", "ls", "re", "le" }) do
		local m = st.J and st.J[k]
		if m and m.Parent then m.Transform = CFrame.identity end
	end
	for _, p in ipairs(st.props or {}) do p:Destroy() end
	posed[char] = nil
end

local function stepPoses()
	local now = Workspace:GetServerTimeNow()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local id = char and char:GetAttribute("Emote")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char and id and POSES[id] and hum and not hum.SeatPart then
			local st = posed[char]
			local at = char:GetAttribute("EmoteAt") or now
			if not st or st.id ~= id or st.at ~= at then
				if st then release(char, st) end
				st = { id = id, at = at, J = rig(char) }
				st.props = props(char, id)
				posed[char] = st
			end
			st.seen = true
			local J = st.J
			if J then
				local w = math.clamp((now - at) / BLEND, 0, 1)
				w = w * w * (3 - 2 * w)
				for k, ang in pairs(POSES[id]) do
					local m = J[k]
					if m then m.Transform = A(rad(ang[1]) * w, 0, rad(ang[2]) * w) end
				end
			end
		end
	end
	for char, st in pairs(posed) do
		if st.seen then st.seen = false else release(char, st) end
	end
end

---------------------------------------------------------------------------------------------------
-- playing them (this rider)
---------------------------------------------------------------------------------------------------
local track: AnimationTrack? = nil
local myPose = false
local danceIx = 0
local playing = false
local city: RemoteFunction? = nil

local function stopAll()
	if track then track:Stop(0.25); track = nil end
	if myPose then
		myPose = false
		if city then task.spawn(function() pcall(function() (city :: RemoteFunction):InvokeServer("emote", "") end) end) end
	end
	playing = false
end

local function play(e)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.SeatPart or Drive.current() or State.cutscene then return end
	stopAll()
	if e.pose then
		myPose = true
		playing = true
		if city then task.spawn(function() pcall(function() (city :: RemoteFunction):InvokeServer("emote", e.id) end) end) end
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	local id = e.anim[1]
	if #e.anim > 1 then
		danceIx = danceIx % #e.anim + 1
		id = e.anim[danceIx]
	end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local ok, tr = pcall(function() return animator:LoadAnimation(a) end)
	if ok and tr then
		tr.Priority = Enum.AnimationPriority.Action
		tr.Looped = e.loop == true
		tr:Play(0.2)
		track = tr
		playing = true
	end
end

local gui, panel, toggle
local function setOpen(v: boolean)
	if panel then panel.Visible = v end
end

local function build()
	gui = UI.screen("GoDashEmotes", Layers.HUD + 1)
	toggle = UI.button(gui, "😀", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.56, 0), Size = UDim2.fromOffset(TOUCH and 52 or 44, TOUCH and 52 or 44),
		TextSize = TOUCH and 26 or 22, BackgroundColor3 = C.black, BackgroundTransparency = 0.45 }, function() setOpen(not panel.Visible) end)
	toggle:SetAttribute("NoTranslate", true)
	panel = UI.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, TOUCH and 70 or 62, 0.56, 0), Size = UDim2.fromOffset(4 * 74 + 10, 2 * 64 + 14),
		BackgroundColor3 = C.black, BackgroundTransparency = 0.35, Visible = false, Parent = gui })
	UI.corner(panel, 16)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(68, 58)
	grid.CellPadding = UDim2.fromOffset(6, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingTop = UDim.new(0, 6), UDim.new(0, 7)
	pad.Parent = panel
	for i, e in ipairs(LIST) do
		local b = UI.button(panel, e.icon .. "\n" .. L(e.en, e.th), { LayoutOrder = i, TextSize = 13, BackgroundColor3 = e.pose and Color3.fromRGB(40, 110, 80) or C.dark,
			TextWrapped = true }, function()
			setOpen(false)
			play(e)
		end)
		b:SetAttribute("NoTranslate", true)
	end
end

function Emotes.start()
	city = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("City", 30) :: RemoteFunction?
	build()
	RunService.PreSimulation:Connect(stepPoses)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		-- (G is also "pick up / deliver" at the door during a job, and the grid in build mode: those win)
		if input.KeyCode == Enum.KeyCode.G and not Drive.current() and not UIState.get("build")
			and not (State.job and State.job.job and JobCard.actionAvailable) then
			setOpen(not panel.Visible)
		end
	end)
	-- stop when walking, jumping or sitting; hide the button while driving
	RunService.Heartbeat:Connect(function()
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local driving = Drive.current() ~= nil or (hum ~= nil and hum.SeatPart ~= nil)
		toggle.Visible = not driving and not State.cutscene
		if driving and panel.Visible then panel.Visible = false end
		if playing and hum then
			if hum.MoveDirection.Magnitude > 0.1 or hum.Jump or hum.SeatPart or hum:GetState() == Enum.HumanoidStateType.Freefall then
				stopAll()
			elseif track and not track.IsPlaying then
				track = nil
				playing = myPose
			end
		end
	end)
end

return Emotes
