-- Client copy of the server's truth: profile, job state, world info. Read-only here; every
-- change goes through a remote and comes back as a sync.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local State = {}
State.data = nil :: any
State.job = { online = false, mode = "food" } :: any
State.world = nil :: any
State.plot = nil :: any -- { id, tier, base, size, house }
State.farm = nil :: any
State.target = nil :: any -- { pos, name, kind } set by the GPS app when no job is active
State.ready = false

local dataListeners, jobListeners, worldListeners = {}, {}, {}

function State.onData(fn: (keys: { [string]: boolean }) -> ()) table.insert(dataListeners, fn) end
function State.onJob(fn: (job: any) -> ()) table.insert(jobListeners, fn) end
function State.onWorld(fn: () -> ()) table.insert(worldListeners, fn) end

local function emit(list, ...)
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then warn("[State] listener error: " .. tostring(err)) end
	end
end

function State.refreshWorld()
	task.spawn(function()
		local ok, _, info = Net.call("GetWorld")
		if ok and info then
			State.world = info
			if info.farm then State.farm = info.farm end
			emit(worldListeners)
		end
	end)
end

function State.start()
	Net.listen("DataSync", function(delta, full)
		local keys = {}
		if not full and not State.data then
			-- a partial update arrived before the full profile: ask for the whole thing
			Net.send("ClientReady")
			return
		end
		if full then
			State.data = delta
			for k in pairs(delta) do keys[k] = true end
			State.ready = true
		else
			for k, v in pairs(delta) do
				State.data[k] = v
				keys[k] = true
			end
		end
		emit(dataListeners, keys)
	end)
	Net.listen("JobUpdate", function(job)
		State.job = job
		emit(jobListeners, job)
	end)
	Net.listen("PlotSync", function(plot)
		State.plot = plot or nil
		emit(worldListeners)
	end)
	Net.listen("FarmSync", function(farm)
		State.farm = farm
		emit(worldListeners)
	end)
	Net.send("ClientReady")
	State.refreshWorld()
	-- ask again shortly: the first request can race the server's start-up
	task.delay(4, function()
		if not State.ready then Net.send("ClientReady") end
		State.refreshWorld()
	end)
end

return State
