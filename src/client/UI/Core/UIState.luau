-- UIState: the one place that decides what is on screen. Gameplay modules report facts
-- (UIState.set("driving", true), UIState.set("phone", true) …); widgets register themselves under
-- a name (UIState.bind("speedo", frame)); the rules below turn facts into visibility. Nobody else
-- toggles a HUD widget's .Visible.
--
--   walking  status + navigation + job card + phone button + interaction prompts
--   driving  + speedometer (+ pedals on touch, + a short key hint on keyboards)
--   phone    the phone docks on the right and the HUD re-flows beside it; on screens without the
--            room (phones, narrow windows) the navigation cluster, speedometer and pedals hide
--   build    build panel; job card and speedometer hide; bottom-centre moves above the panel
--   modal    reward card on top; interaction prompts hide
local Layout = require(script.Parent.Layout)

local UIState = {}

UIState.BUILD_PANEL_H = 186

local flags = {
	driving = false, -- in a vehicle
	phone = false, -- phone open
	build = false, -- build mode
	modal = false, -- reward card showing
	offer = false, -- a job offer is waiting for an answer
	job = false, -- a job is in progress
	prompts = false, -- the engine is showing at least one ProximityPrompt
	hint = false, -- first seconds of a drive: show the key help
}

local RULES: { [string]: (f: typeof(flags)) -> boolean } = {
	status = function(_) return true end,
	nav = function(f) return (not f.phone) or Layout.roomy end,
	job = function(f) return f.job and not f.build end,
	offer = function(f) return f.offer end,
	speedo = function(f) return f.driving and not f.build and ((not f.phone) or Layout.roomy) end,
	touch = function(f) return Layout.isTouch and f.driving and ((not f.phone) or Layout.roomy) end,
	phoneButton = function(f) return not f.phone end,
	prompt = function(f) return f.prompts and not f.phone and not f.modal end,
	driveHint = function(f) return f.hint and f.driving and not Layout.isTouch and not f.phone and not f.build end,
	controls = function(f) return not Layout.isTouch and not f.build and not f.modal and ((not f.phone) or Layout.roomy) end,
}

type Binding = { inst: GuiObject, onShow: (() -> ())?, onHide: (() -> ())? }
local bound = {} :: { [string]: { Binding } }
local listeners = {} :: { () -> () }
local applying, dirty = false, false

local function applyOnce()
	for name, list in pairs(bound) do
		local rule = RULES[name]
		local v = rule ~= nil and rule(flags) == true
		for _, b in ipairs(list) do
			if b.inst.Visible ~= v then
				b.inst.Visible = v
				local cb = v and b.onShow or b.onHide
				if cb then
					local ok, err = pcall(cb)
					if not ok then warn("[UIState] " .. name .. " callback: " .. tostring(err)) end
				end
			end
		end
	end
	Layout.setInsets(flags.phone and (Layout.PHONE_W + Layout.PHONE_GAP) or 0, flags.build and (UIState.BUILD_PANEL_H + 8) or 0)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then warn("[UIState] listener error: " .. tostring(err)) end
	end
end

-- A callback may report another fact while we are applying; run again instead of nesting.
local function apply()
	if applying then
		dirty = true
		return
	end
	applying = true
	local guard = 0
	repeat
		dirty = false
		guard += 1
		applyOnce()
	until not dirty or guard >= 4
	applying = false
end

-- Report a fact. Cheap when nothing changed, so it is fine to call every frame.
function UIState.set(name: string, value: boolean)
	local v = value == true
	if flags[name] == nil then
		warn("[UIState] unknown flag " .. tostring(name))
		return
	end
	if flags[name] == v then return end
	flags[name] = v
	apply()
end

function UIState.get(name: string): boolean
	return flags[name] == true
end

-- Should the widget registered under this name be visible right now?
function UIState.visible(name: string): boolean
	local rule = RULES[name]
	return rule ~= nil and rule(flags) == true
end

-- Hand a widget's visibility to UIState. onShow / onHide run when it flips.
function UIState.bind(name: string, inst: GuiObject, onShow: (() -> ())?, onHide: (() -> ())?)
	assert(RULES[name], "UIState.bind: no rule for " .. tostring(name))
	bound[name] = bound[name] or {}
	table.insert(bound[name], { inst = inst, onShow = onShow, onHide = onHide })
	inst.Visible = UIState.visible(name)
end

-- Runs after any state or layout change.
function UIState.onChange(fn: () -> ())
	table.insert(listeners, fn)
end

-- The dominant state, for anything that wants a single word.
function UIState.mode(): string
	if flags.modal then return "modal" end
	if flags.build then return "build" end
	if flags.phone then return "phone" end
	if flags.driving then return "driving" end
	return "walking"
end

-- Room to keep clear at each bottom corner for touch controls (Roblox's thumbstick and jump
-- button on foot, our pedals in a vehicle). Bottom panels stay between the two.
function UIState.sideReserve(): number
	if not Layout.isTouch then
		-- narrow windows: stay clear of the phone button in the bottom-right corner
		return Layout.breakpoint == "compact" and 92 or 0
	end
	return flags.driving and 276 or 140
end

Layout.onChange(apply)

return UIState
