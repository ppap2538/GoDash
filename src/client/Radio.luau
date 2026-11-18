-- In-game radio: pick a station on the phone and it plays track after track while you ride.
-- Background music: the first station ("GoDash Beat") starts by itself a moment after joining unless
-- the player switched music off (settings.bgm, saved; the Radio app and Settings both change it).
-- Tracks play in a shuffled order, every track once before any repeats.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Stations = require(Shared.Config.Radio)
local Net = require(Shared.Net)
local State = require(script.Parent.State)

local Radio = {}
Radio.stations = Stations
Radio.station = nil :: string? -- id of the station playing, nil = off
Radio.track = "" -- title of the current track
Radio.volume = 0.3
Radio.DEFAULT = Stations[1].id

local group = Instance.new("SoundGroup")
group.Name = "GoDashMusic"
group.Parent = SoundService
local sound = Instance.new("Sound")
sound.Name = "Radio"
sound.SoundGroup = group
sound.Parent = SoundService
local index = 0
local queue = {} -- shuffled track numbers still to play on this station
local listeners = {}

function Radio.onChange(fn) table.insert(listeners, fn) end
local function emit()
	for _, fn in ipairs(listeners) do task.spawn(fn) end
end

local function find(id: string)
	for _, s in ipairs(Stations) do
		if s.id == id then return s end
	end
	return nil
end

local function playIndex(s, i: number)
	index = (i - 1) % #s.tracks + 1
	local t = s.tracks[index]
	Radio.track = t[1]
	sound.SoundId = t[2]
	sound.Volume = Radio.volume
	sound:Play()
	emit()
end

local function shuffled(s)
	local n = #s.tracks
	local order = {}
	for i = 1, n do order[i] = i end
	for i = n, 2, -1 do
		local j = math.random(1, i)
		order[i], order[j] = order[j], order[i]
	end
	if n > 1 and order[1] == index then order[1], order[n] = order[n], order[1] end -- no instant repeat
	return order
end

local function nextTrack(s)
	if #queue == 0 then queue = shuffled(s) end
	playIndex(s, table.remove(queue, 1))
end

function Radio.play(id: string?)
	local s = id and find(id)
	if not s then
		Radio.station = nil
		Radio.track = ""
		sound:Stop()
		emit()
		return
	end
	if Radio.station ~= s.id then queue = {} end
	Radio.station = s.id
	nextTrack(s)
end

function Radio.next()
	local s = Radio.station and find(Radio.station)
	if s then nextTrack(s) end
end

-- Save whether background music is on, so it stays that way next time.
function Radio.remember(on: boolean)
	local d = State.data
	if d and d.settings then d.settings.bgm = on end
	task.spawn(function() pcall(Net.call, "Settings", "bgm", on) end)
end

function Radio.setVolume(v: number)
	Radio.volume = math.clamp(v, 0, 1)
	sound.Volume = Radio.volume
	emit()
end

function Radio.start()
	sound.Ended:Connect(function() Radio.next() end)
	-- a track that fails to load should not leave the station silent
	task.spawn(function()
		while true do
			task.wait(6)
			if Radio.station and not sound.IsPlaying and sound.TimePosition == 0 then Radio.next() end
		end
	end)
	-- background music on by default
	task.spawn(function()
		local t0 = os.clock()
		while not State.data and os.clock() - t0 < 60 do task.wait(0.5) end
		task.wait(2.5)
		local s = State.data and State.data.settings
		if Radio.station == nil and not (s and s.bgm == false) then Radio.play(Radio.DEFAULT) end
	end)
end

return Radio
