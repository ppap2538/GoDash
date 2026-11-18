-- Builds the city around the players, a chunk at a time, and removes chunks nobody is near.
--
-- Why: the whole city is planned at start-up (every lot, shop and address), but drawing all of it
-- would be more than a million parts. Only the part of the plan near a player is turned into
-- parts, so the full 1:1 map is a real city wherever anyone goes and the part count stays bounded
-- (about 25-40 thousand per player who is alone in a district).
--
-- The builder registers draw functions with :add(x, z, fn). A draw function gets the chunk's
-- folder as its parent and must take all its randomness from the position, never from the order.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Streamer = {}
Streamer.__index = Streamer

local LOAD = 780 -- build chunks whose centre is within this distance of a player (streaming target radius is 700)
local KEEP = 1080 -- remove a chunk once every player is farther than this ...
local LINGER = 10 -- ... for this many seconds
local BUDGET = 0.004 -- seconds of building per frame
local RUSH = 0.010 -- when a player is about to see unbuilt land

function Streamer.new(root: Instance, size: number)
	local self = setmetatable({}, Streamer)
	self.size = size
	self.chunks = {} -- [key] = { cx, cz, x, z, items, state, folder, next, seen }
	self.queue = {}
	self.built = {}
	self.root = Instance.new("Folder")
	self.root.Name = "Chunks"
	self.root.Parent = root
	self.parts = 0
	return self
end

function Streamer:key(cx: number, cz: number): number
	return (cx + 2048) * 4096 + (cz + 2048)
end

function Streamer:add(x: number, z: number, fn: (Instance) -> ())
	local cx, cz = math.floor(x / self.size), math.floor(z / self.size)
	local k = self:key(cx, cz)
	local c = self.chunks[k]
	if not c then
		c = { cx = cx, cz = cz, x = (cx + 0.5) * self.size, z = (cz + 0.5) * self.size, items = {}, next = 1 }
		self.chunks[k] = c
	end
	table.insert(c.items, fn)
end

local function step(self, c): boolean -- runs one draw function; true when the chunk is finished
	if not c.folder then
		local f = Instance.new("Folder")
		f.Name = ("%d_%d"):format(c.cx, c.cz)
		f.Parent = self.root
		c.folder = f
	end
	local fn = c.items[c.next]
	c.next += 1
	if fn then
		local ok, err = pcall(fn, c.folder)
		if not ok then warn("[World] chunk " .. c.folder.Name .. ": " .. tostring(err)) end
	end
	if c.next > #c.items then
		c.state = "built"
		table.insert(self.built, c)
		if self.onBuilt then
			local ok, err = pcall(self.onBuilt, c.folder)
			if not ok then warn("[World] after chunk " .. c.folder.Name .. ": " .. tostring(err)) end
		end
		return true
	end
	return false
end

-- Build everything within `radius` of a point before returning (start-up, before the first spawn).
function Streamer:ensureAround(pos: Vector3, radius: number)
	local n = 0
	local r = math.ceil(radius / self.size)
	local cx0, cz0 = math.floor(pos.X / self.size), math.floor(pos.Z / self.size)
	for cx = cx0 - r, cx0 + r do
		for cz = cz0 - r, cz0 + r do
			local c = self.chunks[self:key(cx, cz)]
			if c and c.state ~= "built" and (c.x - pos.X) ^ 2 + (c.z - pos.Z) ^ 2 <= (radius + self.size * 0.71) ^ 2 then
				local i = table.find(self.queue, c)
				if i then table.remove(self.queue, i) end
				c.state = "building"
				c.seen = os.clock()
				while not step(self, c) do end
				n += 1
				task.wait()
			end
		end
	end
	return n
end

local function focuses(): { Vector3 }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local focus = p.ReplicationFocus
		local char = p.Character
		local part = (focus and focus:IsA("BasePart") and focus) or (char and char:FindFirstChild("HumanoidRootPart"))
		if part then table.insert(out, (part :: BasePart).Position) end
	end
	return out
end

function Streamer:start()
	local lastScan = 0
	local rush = false
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastScan > 0.3 then
			lastScan = now
			local pts = focuses()
			local size = self.size
			local reach = LOAD + size * 0.71
			local r = math.ceil(reach / size)
			for _, pos in ipairs(pts) do
				local cx0, cz0 = math.floor(pos.X / size), math.floor(pos.Z / size)
				for cx = cx0 - r, cx0 + r do
					for cz = cz0 - r, cz0 + r do
						local c = self.chunks[self:key(cx, cz)]
						if c then
							local d2 = (c.x - pos.X) ^ 2 + (c.z - pos.Z) ^ 2
							if d2 <= reach * reach then
								c.seen = now
								if not c.state then
									c.state = "queued"
									table.insert(self.queue, c)
								end
							end
						end
					end
				end
			end
			-- nearest first
			rush = false
			if #self.queue > 0 then
				for _, c in ipairs(self.queue) do
					local best = math.huge
					for _, pos in ipairs(pts) do best = math.min(best, (c.x - pos.X) ^ 2 + (c.z - pos.Z) ^ 2) end
					c.dist = best
					if best < (size * 1.2) ^ 2 then rush = true end
				end
				table.sort(self.queue, function(a, b) return a.dist < b.dist end)
			end
			-- let go of chunks nobody is near
			local keep2 = (KEEP + size * 0.71) ^ 2
			for i = #self.built, 1, -1 do
				local c = self.built[i]
				if now - (c.seen or 0) > LINGER then
					local close = false
					for _, pos in ipairs(pts) do
						if (c.x - pos.X) ^ 2 + (c.z - pos.Z) ^ 2 <= keep2 then close = true break end
					end
					if not close then
						if c.folder then c.folder:Destroy() end
						c.folder, c.state, c.next = nil, nil, 1
						table.remove(self.built, i)
					end
				end
			end
		end
		local budget = rush and RUSH or BUDGET
		while #self.queue > 0 and os.clock() - now < budget do
			local c = self.queue[1]
			if step(self, c) then table.remove(self.queue, 1) end
		end
	end)
end

-- For the server log and QA: how much of the city is drawn right now.
function Streamer:stats()
	local total = 0
	for _ in pairs(self.chunks) do total += 1 end
	return { chunks = total, built = #self.built, queued = #self.queue }
end

return Streamer
