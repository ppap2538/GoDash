-- Soi dogs. A few street dogs live in the small lanes. Walk or ride a bike past one and it runs
-- out barking; if it catches you it bites (you lose some happiness and energy). People inside a
-- car are barked at but cannot be bitten. Leave the lane or outrun it and it gives up.
-- The server owns each dog's position and state (attributes on a Configuration); every client
-- draws the dog model itself and eases it towards that position.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

local Service = {}
local MAX_DOGS = 140 -- (2026-11-16: was 16; the sois felt empty. 2026-11-18: 40 -> 140 for the whole tambon)
local SPACING = 240 -- studs between two dogs' homes
local NOTICE = 60 -- a dog notices you this close to its home
local LEASH = 170 -- and gives up this far from home
local CHASE_SPEED = 33 -- a bicycle tops out a little above this
local HOME_SPEED = 16
local BITE_RANGE = 6
local TICK = 0.2

function Service.start(world, deps)
	local graph = world.graph
	local radius = world.radius
	local centre = world.map.center
	local vehicles, lifestyle = deps.vehicles, deps.lifestyle
	local rng = Random.new(4242)

	-- homes: dead-quiet lane nodes, spread out
	local candidates = {}
	for _, n in ipairs(graph.nodes) do
		local pos = Vector3.new(n.x, 0, n.z)
		if (not radius) or (pos - centre).Magnitude < radius - 200 then
			local soi = #n.links > 0
			for _, l in ipairs(n.links) do
				if not l.edge.minor then soi = false break end
			end
			if soi then table.insert(candidates, n) end
		end
	end
	for i = #candidates, 2, -1 do
		local j = rng:NextInteger(1, i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end

	local folder = Instance.new("Folder")
	folder.Name = "GoDashDogs"
	local dogs = {}
	for _, n in ipairs(candidates) do
		if #dogs >= MAX_DOGS then break end
		local l = n.links[rng:NextInteger(1, #n.links)]
		-- sit at the side of the lane, not in the middle of it
		local dir = Vector3.new(l.to.x - n.x, 0, l.to.z - n.z).Unit
		local home = Vector3.new(n.x, 0.3, n.z) + dir * math.min(12, l.len * 0.4) + Vector3.new(dir.Z, 0, -dir.X) * 7
		local ok = true
		for _, d in ipairs(dogs) do
			if (d.home - home).Magnitude < SPACING then ok = false break end
		end
		if ok then
			local cfg = Instance.new("Configuration")
			cfg.Name = "Dog"
			cfg:SetAttribute("Home", home)
			cfg:SetAttribute("Pos", home)
			cfg:SetAttribute("State", "idle")
			cfg:SetAttribute("Look", rng:NextInteger(1, 4))
			cfg.Parent = folder
			table.insert(dogs, { cfg = cfg, home = home, pos = home, state = "idle", rest = 0 })
		end
	end
	folder.Parent = ReplicatedStorage

	local bitten = {} -- [player] = clock of the last bite
	Players.PlayerRemoving:Connect(function(p) bitten[p] = nil end)

	local function rootOf(player: Player): BasePart?
		local c = player.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return nil end
		return c:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	local function flat(v: Vector3): Vector3
		return Vector3.new(v.X, 0, v.Z)
	end
	local function setState(d, s: string)
		d.state = s
		d.cfg:SetAttribute("State", s)
	end
	local function step(d, target: Vector3, speed: number): number
		local to = flat(target - d.pos)
		local dist = to.Magnitude
		if dist > 0.05 then
			d.pos += to.Unit * math.min(dist, speed * TICK)
			d.cfg:SetAttribute("Pos", d.pos)
		end
		return dist
	end

	task.spawn(function()
		while true do
			task.wait(TICK)
			local now = os.clock()
			local roots = {}
			for _, p in ipairs(Players:GetPlayers()) do
				local r = rootOf(p)
				if r then roots[p] = r.Position end
			end
			for _, d in ipairs(dogs) do
				if d.state == "idle" then
					if now >= d.rest then
						for p, pos in pairs(roots) do
							if flat(pos - d.home).Magnitude < NOTICE and now - (bitten[p] or -100) > 45 then
								d.target = p
								d.started = now
								setState(d, "chase")
								-- (2026-11-17) say so: a soi dog on your tail is half the fun
								local v = vehicles.driving(p)
								if not v or v.def.class == "bike" then
									Net.fire(p, "Notify", "toast", { text = "🐕💨 A soi dog is chasing you! Get away!", th = "🐕💨 หมาซอยไล่! บิดหนีเร็ว!", bad = true })
								end
								break
							end
						end
					end
				elseif d.state == "chase" then
					local pos = d.target and roots[d.target]
					if not pos or now - d.started > 16 or flat(pos - d.home).Magnitude > LEASH then
						local p = d.target
						if p and pos then
							Net.fire(p, "Notify", "toast", { text = "😅 You got away from the soi dog", th = "😅 รอดจากหมาซอยแล้ว", good = true })
							if math.random() < 0.4 then Net.fire(p, "Notify", "feed", { key = "dog_chase", vars = { pos = d.home } }) end
						end
						d.target = nil
						setState(d, "return")
					else
						local dist = step(d, pos, CHASE_SPEED)
						if dist < BITE_RANGE then
							local p = d.target
							local v = vehicles.driving(p)
							if v and v.def.class ~= "bike" then
								-- safe inside a car: the dog just barks alongside
							else
								bitten[p] = now
								lifestyle.add(p, -4, nil, -10)
								local tele = vehicles.telemetry(p)
								if tele then tele.dog = (tele.dog or 0) + 1 end
								Net.fire(p, "Notify", "toast", { text = "🐕 A soi dog bit you!  −10 happiness", th = "🐕 โดนหมาซอยงับ! ความสุข −10", bad = true })
								Net.fire(p, "Notify", "feed", { key = "dog_bite", vars = { pos = d.home } })
								d.target = nil
								setState(d, "return")
							end
						end
					end
				else -- return
					if step(d, d.home, HOME_SPEED) < 1.5 then
						d.rest = now + 6
						setState(d, "idle")
					end
				end
			end
		end
	end)
	print(("[Dogs] %d soi dogs placed"):format(#dogs))

	-- Studio test hook: Workspace attribute QaDog = true moves the nearest dog's home next to the first player
	if game:GetService("RunService"):IsStudio() then
		workspace:GetAttributeChangedSignal("QaDog"):Connect(function()
			local p = Players:GetPlayers()[1]
			local r = p and rootOf(p)
			local d = dogs[1]
			if not r or not d then return end
			d.home = Vector3.new(r.Position.X + 30, 0.3, r.Position.Z)
			d.pos = d.home
			d.rest = 0
			d.cfg:SetAttribute("Home", d.home)
			d.cfg:SetAttribute("Pos", d.pos)
			setState(d, "idle")
		end)
	end
end

return Service
