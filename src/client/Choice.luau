-- A small question card with two or three answers: customer twists on a job ("can you stop for ice?"),
-- the neighbour's questions at home, the finance company's offers. Answers by click / tap, or 1-3 on
-- a keyboard. One card at a time; a new question waits until the open one is answered.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)
local Lang = require(script.Parent.Lang)
local UI = require(script.Parent.UI.Kit)
local Layout = require(script.Parent.UI.Core.Layout)
local State = require(script.Parent.State)
local Feedback = require(script.Parent.Feedback)

local Choice = {}
local C, F = UI.C, UI.F
local center
local busy = false
local _ = Players

-- opts = { icon, title, text, answers = { { text, color? } }, seconds? }; returns the answer's number
-- (or nil when it timed out). Yields.
function Choice.ask(opts): number?
	while (busy or State.cutscene or not center) do task.wait(0.3) end
	busy = true
	local card = UI.new("Frame", { Name = "Choice", BackgroundColor3 = C.card, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.92, 0),
		Size = UDim2.fromOffset(380, 100), AutomaticSize = Enum.AutomaticSize.Y, Parent = center })
	UI.corner(card, 20)
	UI.stroke(card, C.orange, 3)
	UI.pad(card, 18, 14, 18, 14)
	UI.list(card, 8, false, Enum.HorizontalAlignment.Center)
	UI.label(card, (opts.icon or "💬") .. "  " .. (opts.title or ""), 17, C.text, F.black, { TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 24) })
	if opts.text then
		UI.label(card, opts.text, 14, C.sub, F.med, { TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y })
	end
	local sc = Instance.new("UIScale"); sc.Scale = 0.6; sc.Parent = card
	UI.tween(sc, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	local picked: number? = nil
	for i, a in ipairs(opts.answers) do
		local b = UI.button(card, (UserInputService.KeyboardEnabled and (i .. "  ") or "") .. a[1], {
			Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = a[2] or (i == 1 and C.green or C.bg), TextSize = 15,
			TextColor3 = (a[2] or (i == 1 and C.green or C.bg)) == C.bg and C.text or C.white,
		}, function() picked = picked or i end)
		UI.pad(b, 10, 0, 10, 0)
		UI.fitText(b, 15, 10)
	end
	local bar
	if opts.seconds then
		local track, set = UI.bar(card, C.orange, 4)
		track.Size = UDim2.new(1, 0, 0, 4)
		bar = set
	end
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }
	local con = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		for i, k in ipairs(keys) do
			if input.KeyCode == k and opts.answers[i] then picked = picked or i end
		end
	end)
	Feedback.notify()
	local t0 = os.clock()
	while not picked do
		task.wait()
		if opts.seconds then
			local left = 1 - (os.clock() - t0) / opts.seconds
			if bar then bar(math.max(left, 0)) end
			if left <= 0 then break end
		end
	end
	con:Disconnect()
	Feedback.click()
	UI.tween(sc, 0.15, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.17, function() card:Destroy() end)
	task.wait(0.2)
	busy = false
	return picked
end

function Choice.start()
	local gui = UI.screen("GoDashChoice", 62)
	center = Layout.region(Layout.stage(gui), "Center")
	-- a customer or passenger asks something during a job (server/TwistService)
	local function tr(t) return type(t) == "table" and (Lang.code == "th" and t.th or t.en) or tostring(t or "") end
	Net.listen("JobEvent", function(e)
		if type(e) ~= "table" then return end
		task.spawn(function()
			local answers = {}
			for _, a in ipairs(e.answers or {}) do table.insert(answers, { tr(a) }) end
			local n = Choice.ask({ icon = e.icon, title = tr(e.title), text = tr(e.text), answers = answers, seconds = e.seconds })
			Net.send("JobChoice", tostring(e.id), n == 1)
		end)
	end)
end

return Choice
