-- In-game video clips (2026-11-19, owner: "a record button in the game, so I can take the real file to TikTok").
-- A thin wrapper round Roblox's own video capture (CaptureService): up to 30 seconds, then the player saves the
-- clip to the Captures gallery in the Roblox menu, or shares it (the phone's share sheet, straight into TikTok
-- and the like; a device without one downloads the file instead, which is how a computer gets a real file).
-- Not every device can capture: Start returns why not, and the callers say "use your screen recorder" then.
-- Used by client/ClipMode (the ⏺ button, the "keep this moment" offer, the done card) and client/Replay (record a
-- replay). Required on demand: it has no start() of its own.
local Lang = require(script.Parent.Lang)

local Capture = {}
Capture.MAX = 30 -- seconds; Roblox stops the capture by itself after this
local L = Lang.pick

-- what to tell the player when Start says no
function Capture.explain(why: string?): string
	if why == "busy" then return L("🎬 Already recording", "🎬 กำลังอัดอยู่แล้ว") end
	if why == "space" then return L("🎬 Your device is out of space: can't record", "🎬 เครื่องเต็ม อัดคลิปไม่ได้") end
	return L("🎬 This device can't record in the game: use your screen recorder and crop to the middle",
		"🎬 เครื่องนี้อัดคลิปในเกมไม่ได้ ใช้ตัวอัดหน้าจอของเครื่องแทน แล้วครอปตรงกลาง")
end

local CS: any = nil
pcall(function() CS = game:GetService("CaptureService") end)

Capture.state = "idle" -- "idle" | "starting" | "rec"
Capture.startedAt = 0
local changed = Instance.new("BindableEvent")
local done = Instance.new("BindableEvent")
Capture.changed = changed.Event -- (state)
Capture.done = done.Event -- (videoCapture or nil, seconds, why or nil)

local function set(s: string)
	Capture.state = s
	changed:Fire(s)
end

-- can this build of Roblox capture video at all? (the device may still say no when it starts)
function Capture.available(): boolean
	if not CS then return false end
	local ok, fn = pcall(function() return CS.StartVideoCaptureAsync end)
	return ok and fn ~= nil
end

function Capture.recording(): boolean
	return Capture.state ~= "idle"
end

function Capture.elapsed(): number
	return Capture.state == "rec" and os.clock() - Capture.startedAt or 0
end

-- A short note at the top of the screen in its own ScreenGui: clip mode and replays hide the GoDash GUIs (the
-- toasts with them), and these notes must still be seen there.
local noteGui: ScreenGui? = nil
function Capture.say(text: string, kind: string?)
	local pg = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then return end
	if noteGui then noteGui:Destroy() end
	local g = Instance.new("ScreenGui")
	g.Name = "ClipNote" -- (no GoDash prefix on purpose)
	g.ResetOnSpawn = false
	g.DisplayOrder = 59
	g:SetAttribute("NoTranslate", true)
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0)
	t.Position = UDim2.new(0.5, 0, 0.1, 0)
	t.Size = UDim2.new(0, math.min(460, workspace.CurrentCamera.ViewportSize.X - 32), 0, 0)
	t.AutomaticSize = Enum.AutomaticSize.Y
	t.BackgroundColor3 = kind == "bad" and Color3.fromRGB(150, 30, 36) or Color3.fromRGB(20, 110, 60)
	t.BackgroundTransparency = 0.08
	t.BorderSizePixel = 0
	t.Font = Enum.Font.GothamBold
	t.TextSize = 15
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextWrapped = true
	t.Text = text
	local p = Instance.new("UIPadding")
	p.PaddingLeft, p.PaddingRight, p.PaddingTop, p.PaddingBottom = UDim.new(0, 14), UDim.new(0, 14), UDim.new(0, 9), UDim.new(0, 9)
	p.Parent = t
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = t
	t.Parent = g
	g.Parent = pg
	noteGui = g
	task.delay(4.5, function()
		if noteGui == g then noteGui = nil end
		g:Destroy()
	end)
end

local session = 0
local stopAt: number? = nil

-- Start a clip. Yields until the device answers. Returns true, or false and why:
-- "busy" | "device" | "space" | "unsupported" | "error"
-- Capture.done fires once per clip: with the video, or nil and why when the device never hands one back (Studio
-- says it started, then never answers: the watchdog below gives up a few seconds after the stop or the limit).
function Capture.start(): (boolean, string?)
	if Capture.state ~= "idle" then return false, "busy" end
	if not Capture.available() then return false, "unsupported" end
	set("starting")
	session += 1
	local my = session
	local finished = false
	local began = os.clock()
	stopAt = nil
	local function finish(video, secs: number, why: string?)
		if finished or session ~= my then return end
		finished = true
		set("idle")
		done:Fire(video, secs, why)
	end
	local ok, res = pcall(function()
		return CS:StartVideoCaptureAsync(function(result, video)
			local fine = video ~= nil and (result == Enum.VideoCaptureResult.Success or result == Enum.VideoCaptureResult.TimeLimitReached)
			finish(fine and video or nil, video and tonumber(video.TimeLength) or (os.clock() - began), not fine and tostring(result) or nil)
		end, {})
	end)
	if not ok then
		finished = true
		set("idle")
		warn("[Capture] " .. tostring(res))
		return false, "unsupported"
	end
	if res ~= Enum.VideoCaptureStartedResult.Success then
		finished = true
		set("idle")
		if res == Enum.VideoCaptureStartedResult.CapturingAlready then return false, "busy" end
		if res == Enum.VideoCaptureStartedResult.NoDeviceSupport then return false, "device" end
		if res == Enum.VideoCaptureStartedResult.NoSpaceOnDevice then return false, "space" end
		return false, "error"
	end
	if finished then return true end -- (it already ended while Start was answering)
	Capture.startedAt = os.clock()
	-- a note still up would be in the clip
	if noteGui then noteGui:Destroy(); noteGui = nil end
	set("rec")
	task.spawn(function()
		while not finished do
			local now = os.clock()
			if (stopAt and now - stopAt > 4) or now - Capture.startedAt > Capture.MAX + 5 then
				finish(nil, (stopAt or now) - Capture.startedAt, "no clip came back")
				break
			end
			task.wait(0.25)
		end
	end)
	return true
end

function Capture.stop()
	if Capture.state ~= "rec" or not CS then return end
	stopAt = stopAt or os.clock()
	pcall(function() CS:StopVideoCapture() end)
end

-- the Captures gallery in the Roblox menu; cb(saved: boolean)
function Capture.save(video, cb: ((boolean) -> ())?)
	local ok = pcall(function()
		CS:PromptSaveCapturesToGallery({ video }, function(results)
			local saved = false
			if typeof(results) == "table" then
				for _, v in pairs(results) do if v then saved = true end end
			end
			if cb then cb(saved) end
		end)
	end)
	if not ok and cb then cb(false) end
end

-- a screenshot with the GUI in it (client/Recap shares the day card): cb(capture or nil)
function Capture.screenshot(cb: (any) -> ())
	local ok = pcall(function()
		CS:TakeScreenshotCaptureAsync(function(_result, shot)
			cb(shot)
		end, { UICaptureMode = Enum.UICaptureMode.All })
	end)
	if not ok then cb(nil) end
end

-- the device's share sheet (TikTok and the like), with an invite to the game where the device allows it;
-- a device without a share sheet downloads the clip instead. cb(shared: boolean)
function Capture.share(video, cb: ((boolean) -> ())?)
	local ok = pcall(function()
		CS:PromptShareCapture(Content.fromObject(video), "clip",
			function() if cb then cb(true) end end,
			function() if cb then cb(false) end end)
	end)
	if not ok and cb then cb(false) end
end

return Capture
