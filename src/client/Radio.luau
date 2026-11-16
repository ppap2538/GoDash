-- In-game radio: pick a station on the phone and it plays track after track while you ride.
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Stations = require(ReplicatedStorage:WaitForChild("Shared").Config.Radio)

local Radio = {}
Radio.stations = Stations
Radio.station = nil :: string? -- id of the station playing, nil = off
Radio.track = "" -- title of the current track
Radio.volume = 0.35

local group = Instance.new("SoundGroup")
group.Name = "GoDashMusic"
group.Parent = SoundService
local sound = Instance.new("Sound")
sound.Name = "Radio"
sound.SoundGroup = group
sound.Parent = SoundService
local index = 0
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

function Radio.play(id: string?)
	local s = id and find(id)
	if not s then
		Radio.station = nil
		Radio.track = ""
		sound:Stop()
		emit()
		return
	end
	Radio.station = s.id
	playIndex(s, math.random(1, #s.tracks))
end

function Radio.next()
	local s = Radio.station and find(Radio.station)
	if s then playIndex(s, index + 1) end
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
end

return Radio
