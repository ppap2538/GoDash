-- GoDash Auto Sync: a local Roblox Studio plugin (owner's PC only).
-- Installed by tools/autosync_start.ps1 into %LOCALAPPDATA%\Roblox\Plugins. It asks tools/autosync.py
-- (http://localhost:8791) which scripts changed on GitHub `main` since Studio last took them, and puts them into
-- the open GoDash place while Studio is in Edit mode. The owner then presses Play to check, and Publish.
-- A script that someone ALSO edited inside Studio is never overwritten silently: the panel asks first.
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

if not RunService:IsEdit() then
	return -- plugins also start inside Play's server and client; only the Edit place is synced
end

local URL = "http://localhost:8791/autosync/"
local PLACES = { [72947456721898] = true } -- the live GoDash place; add a dev copy's place id here
local POLL = 15

local alive = true
plugin.Unloading:Connect(function()
	alive = false
end)
local enabled = plugin:GetSetting("GoDashAutoSyncOn")
if enabled == nil then
	enabled = true
end

-- UI -------------------------------------------------------------------------------------------------------
local toolbar = plugin:CreateToolbar("GoDash")
local button = toolbar:CreateButton("GoDashAutoSync", "แผง GoDash Auto Sync: ดึงสคริปต์จาก GitHub เข้าเกม", "", "Auto Sync")
button.ClickableWhenViewportHidden = true
local widget = plugin:CreateDockWidgetPluginGui("GoDashAutoSync",
	DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 420, 260, 340, 200))
widget.Title = "GoDash Auto Sync"
widget.Name = "GoDashAutoSync"

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BorderSizePixel = 0
root.Parent = widget
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
pad.Parent = root

local head = Instance.new("TextLabel")
head.BackgroundTransparency = 1
head.Size = UDim2.new(1, 0, 0, 44)
head.Font = Enum.Font.SourceSansBold
head.TextSize = 18
head.TextWrapped = true
head.TextXAlignment = Enum.TextXAlignment.Left
head.TextYAlignment = Enum.TextYAlignment.Top
head.Parent = root

local scroll = Instance.new("ScrollingFrame")
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(0, 48)
scroll.Size = UDim2.new(1, 0, 1, -92)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ScrollBarThickness = 6
scroll.Parent = root
local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, -8, 0, 0)
body.AutomaticSize = Enum.AutomaticSize.Y
body.Font = Enum.Font.SourceSans
body.TextSize = 15
body.TextWrapped = true
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.Parent = scroll

local row = Instance.new("Frame")
row.BackgroundTransparency = 1
row.Position = UDim2.new(0, 0, 1, -36)
row.Size = UDim2.new(1, 0, 0, 34)
row.Parent = root
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.Padding = UDim.new(0, 8)
list.Parent = row
local function makeButton(text: string, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(width, 32)
	b.Font = Enum.Font.SourceSansBold
	b.TextSize = 15
	b.Text = text
	b.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	b.Parent = row
	return b
end
local syncNow = makeButton("ซิงก์เดี๋ยวนี้", 120)
local toggle = makeButton("", 170)
local overwrite = makeButton("ใช้ของ GitHub เขียนทับ", 170)
local skip = makeButton("ข้ามไว้ก่อน", 110)

local function paint()
	local theme = settings().Studio.Theme
	root.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
	head.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.MainText)
	body.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.SubText)
	for _, b in ipairs({ syncNow, toggle, skip }) do
		b.BackgroundColor3 = theme:GetColor(Enum.StudioStyleGuideColor.Button)
		b.TextColor3 = theme:GetColor(Enum.StudioStyleGuideColor.ButtonText)
	end
	overwrite.BackgroundColor3 = Color3.fromRGB(214, 120, 40)
	overwrite.TextColor3 = Color3.new(1, 1, 1)
end
paint()
settings().Studio.ThemeChanged:Connect(paint)

local function show(title: string, text: string?, conflict: boolean?)
	head.Text = title
	body.Text = text or ""
	scroll.CanvasPosition = Vector2.zero
	overwrite.Visible = conflict == true
	skip.Visible = conflict == true
	syncNow.Visible = conflict ~= true
	toggle.Visible = conflict ~= true
end

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	button:SetActive(widget.Enabled)
end)

-- sync -----------------------------------------------------------------------------------------------------
local busy = false
local snoozed = nil -- commit the owner chose to skip; asked again when a newer commit arrives
local pending = nil -- manifest waiting for an answer about conflicts

local function isGoDash(): boolean
	return PLACES[game.PlaceId] == true and game:GetService("ServerScriptService"):FindFirstChild("GoDash") ~= nil
end

local function resolve(path: string, create: boolean, class: string?): Instance?
	local parts = string.split(path, ".")
	local ok, inst = pcall(game.GetService, game, parts[1])
	if not ok or not inst then
		return nil
	end
	for i = 2, #parts do
		local nextInst = inst:FindFirstChild(parts[i])
		if not nextInst then
			if not create then
				return nil
			end
			nextInst = Instance.new(i == #parts and class or "Folder")
			nextInst.Name = parts[i]
			nextInst.Parent = inst
		end
		inst = nextInst
	end
	return inst
end

local function current(inst: Instance?): string?
	if inst and inst:IsA("LuaSourceContainer") then
		return (((inst :: any).Source :: string):gsub("\r\n", "\n"))
	end
	return nil
end

local function conflicts(m): { string }
	local out = {}
	for _, e in ipairs(m.files) do
		local cur = current(resolve(e.path, false))
		if cur ~= nil and cur ~= e.old and cur ~= e.source then
			table.insert(out, e.path)
		end
	end
	return out
end

local function summary(m): string
	local lines = {}
	for _, c in ipairs(m.commits or {}) do
		table.insert(lines, "• " .. c)
	end
	if #(m.skipped or {}) > 0 then
		table.insert(lines, ("(ไฟล์ที่ไม่ใช่สคริปต์ %d ไฟล์ ไม่ต้องซิงก์)"):format(#m.skipped))
	end
	return table.concat(lines, "\n")
end

local function markDone(commit: string)
	local ok, res = pcall(function()
		return HttpService:JSONDecode(HttpService:PostAsync(URL .. "done", HttpService:JSONEncode({ commit = commit }),
			Enum.HttpContentType.ApplicationJson))
	end)
	if not ok or not res.ok then
		warn("[GoDash Auto Sync] could not tell autosync.py:", if ok then res.error else res)
	end
end

local function apply(m, manual: boolean?)
	local okRec, recording = pcall(ChangeHistoryService.TryBeginRecording, ChangeHistoryService, "GoDash Auto Sync")
	local updated, created, deleted = 0, 0, 0
	for _, e in ipairs(m.files) do
		local inst = resolve(e.path, false)
		if e.kind == "delete" then
			if inst then
				inst:Destroy()
				deleted += 1
			end
		elseif not inst then
			inst = resolve(e.path, true, e.class)
			if inst then
				(inst :: any).Source = e.source
				created += 1
			end
		elseif current(inst) ~= e.source then
			(inst :: any).Source = e.source
			updated += 1
		end
	end
	if okRec and recording then
		ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
	else
		ChangeHistoryService:SetWaypoint("GoDash Auto Sync")
	end
	markDone(m.commit)
	if updated + created + deleted == 0 then
		-- Studio already had this code (synced by hand before it was pushed)
		if manual then
			show("✔️ Studio ตรงกับ GitHub แล้ว (" .. m.short .. ")", summary(m))
		end
		return
	end
	print(("[GoDash Auto Sync] %s: %d updated, %d new, %d removed"):format(m.short, updated, created, deleted))
	show(("✅ อัปเดตจาก GitHub แล้ว (%s): %d สคริปต์"):format(m.short, updated + created + deleted),
		summary(m) .. "\n\nต่อไป: กด Play ลองเล่นสั้น ๆ แล้ว ไฟล์ → เผยแพร่ไปยัง Roblox (Publish)")
	widget.Enabled = true
end

local function check(manual: boolean?)
	if busy or not (enabled or manual) then
		return
	end
	if not isGoDash() then
		if manual then
			show("ไม่ใช่เกม GoDash", "ปลั๊กอินนี้ซิงก์เฉพาะ place GoDash (PlaceId ในตาราง PLACES)")
		end
		return
	end
	busy = true
	local ok, m = pcall(function()
		return HttpService:JSONDecode(HttpService:GetAsync(URL .. "manifest", true))
	end)
	busy = false
	if not ok then
		if manual then
			show("⚠️ ติดต่อตัวเฝ้า GitHub ไม่ได้",
				"autosync.py บนเครื่องไม่ได้เปิดอยู่: รัน tools/autosync_start.ps1 แล้วกดซิงก์อีกครั้ง\n\n" .. tostring(m))
		end
		return
	end
	if not m.ok then
		show("⚠️ ซิงก์อัตโนมัติไม่ได้", tostring(m.error))
		widget.Enabled = true
		return
	end
	if #m.files == 0 then
		if m.commit ~= m.base then
			markDone(m.commit) -- only docs/assets changed: nothing for Studio
		end
		if manual then
			show("✔️ Studio ตรงกับ GitHub แล้ว (" .. m.short .. ")",
				if m.fetchError then "ดึงจาก GitHub ไม่ได้: " .. tostring(m.fetchError) else "")
		end
		return
	end
	if snoozed == m.commit and not manual then
		return
	end
	local clash = conflicts(m)
	if #clash > 0 then
		pending = m
		show(("⚠️ งานใหม่จาก GitHub (%s) ชนกับที่มีคนแก้ใน Studio %d สคริปต์"):format(m.short, #clash),
			"แก้ใน Studio:\n" .. table.concat(clash, "\n") .. "\n\nงานบน GitHub:\n" .. summary(m)
				.. "\n\nเขียนทับ = ใช้ของ GitHub ทั้งหมด (ที่แก้ใน Studio ในสคริปต์พวกนี้จะหาย)", true)
		widget.Enabled = true
		return
	end
	apply(m, manual)
end

local function setEnabled(on: boolean)
	enabled = on
	plugin:SetSetting("GoDashAutoSyncOn", on)
	toggle.Text = if on then "⏸️ หยุดซิงก์อัตโนมัติ" else "▶️ เปิดซิงก์อัตโนมัติ"
end

overwrite.MouseButton1Click:Connect(function()
	local m = pending
	pending = nil
	if m then
		apply(m, true)
	end
end)
skip.MouseButton1Click:Connect(function()
	if pending then
		snoozed = pending.commit
	end
	pending = nil
	show("ข้ามไว้ก่อน", "จะถามอีกครั้งเมื่อมีงานใหม่บน GitHub หรือเมื่อกด ซิงก์เดี๋ยวนี้")
end)
syncNow.MouseButton1Click:Connect(function()
	check(true)
end)
toggle.MouseButton1Click:Connect(function()
	setEnabled(not enabled)
	show(if enabled then "🔄 ซิงก์อัตโนมัติ: เปิด" else "⏸️ ซิงก์อัตโนมัติ: ปิด",
		if enabled then ("เช็ก GitHub ทุก %d วินาที"):format(POLL) else "กด ▶️ เพื่อเปิดอีกครั้ง")
end)
button.Click:Connect(function()
	widget.Enabled = not widget.Enabled
	if widget.Enabled then
		check(true)
	end
end)

setEnabled(enabled)
show(if enabled then "🔄 ซิงก์อัตโนมัติ: เปิด" else "⏸️ ซิงก์อัตโนมัติ: ปิด", ("เช็ก GitHub ทุก %d วินาที"):format(POLL))
task.spawn(function()
	task.wait(5)
	while alive do
		check(false)
		task.wait(POLL)
	end
end)
