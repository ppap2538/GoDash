--!strict
-- One place for every remote. The server creates them, validates every argument and rate-limits
-- each player; the client only sends requests and never decides money, EXP or inventory.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Net = {}

-- client -> server (fire and forget)
local EVENTS_UP = { "JobSetOnline", "JobRespond", "JobAction", "JobCancel", "VehicleState", "VehicleFall", "ClientReady", "JobChoice", "Social", "ZebraRun", "LeaveSeat" }
-- server -> client
local EVENTS_DOWN = { "DataSync", "Notify", "JobOffer", "JobUpdate", "Dialogue", "Reward", "OpenUI", "PlotSync", "FarmSync", "JobEvent" }
-- client -> server with an answer {ok, message, extra}
local FUNCTIONS = { "Shop", "Garage", "Bank", "Housing", "Inventory", "Mission", "Farm", "Settings", "GetWorld", "City", "GetSkyline" }

local IS_SERVER = RunService:IsServer()
local folder: Instance

if IS_SERVER then
	local f = ReplicatedStorage:FindFirstChild("Remotes")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Remotes"
		for _, n in ipairs(EVENTS_UP) do
			local r = Instance.new("RemoteEvent"); r.Name = n; r.Parent = f
		end
		for _, n in ipairs(EVENTS_DOWN) do
			local r = Instance.new("RemoteEvent"); r.Name = n; r.Parent = f
		end
		for _, n in ipairs(FUNCTIONS) do
			local r = Instance.new("RemoteFunction"); r.Name = n; r.Parent = f
		end
		f.Parent = ReplicatedStorage
	end
	folder = f
else
	folder = ReplicatedStorage:WaitForChild("Remotes")
end

local function get(name: string): any
	local r = folder:FindFirstChild(name)
	if not r and not IS_SERVER then r = folder:WaitForChild(name, 10) end
	assert(r, "Net: unknown remote " .. name)
	return r
end

---------------------------------------------------------------------------------------------------
-- validation
---------------------------------------------------------------------------------------------------
local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < 1e9
end

local CHECKS: { [string]: (any) -> boolean } = {
	string = function(v) return type(v) == "string" and #v <= 64 end,
	number = finite,
	int = function(v) return finite(v) and v == math.floor(v) end,
	boolean = function(v) return type(v) == "boolean" end,
	vector3 = function(v) return typeof(v) == "Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end,
	table = function(v) return type(v) == "table" end,
	any = function(_v) return true end,
}

local function validate(spec: { string }, args: { any }, n: number): boolean
	if n > #spec then return false end
	for i, s in ipairs(spec) do
		local optional = s:sub(-1) == "?"
		local kind = optional and s:sub(1, -2) or s
		local v = args[i]
		if v == nil then
			if not optional then return false end
		elseif not CHECKS[kind](v) then
			return false
		end
	end
	return true
end

-- token bucket per player per remote
local buckets: { [Player]: { [string]: { t: number, tokens: number } } } = {}
local listeners = 0

local function allow(player: Player, name: string, rate: number): boolean
	local pb = buckets[player]
	if not pb then pb = {}; buckets[player] = pb end
	local b = pb[name]
	local now = os.clock()
	if not b then b = { t = now, tokens = rate }; pb[name] = b end
	b.tokens = math.min(rate, b.tokens + (now - b.t) * rate)
	b.t = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

if IS_SERVER then
	Players.PlayerRemoving:Connect(function(p) buckets[p] = nil end)
end

---------------------------------------------------------------------------------------------------
-- server API
---------------------------------------------------------------------------------------------------
-- spec: list of "string" | "number" | "int" | "boolean" | "vector3" | "table" | "any", "?" = optional
function Net.on(name: string, spec: { string }, handler: (Player, ...any) -> (), rate: number?)
	assert(IS_SERVER)
	listeners += 1
	local bucket = name .. "#" .. listeners -- each listener has its own budget
	get(name).OnServerEvent:Connect(function(player: Player, ...)
		if not allow(player, bucket, rate or 6) then return end
		local args = table.pack(...)
		if not validate(spec, args, args.n) then
			warn(("[Net] %s sent bad arguments to %s"):format(player.Name, name))
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then warn(("[Net] %s handler error: %s"):format(name, tostring(err))) end
	end)
end

-- handler returns ok:boolean, message:string?, extra:any?
function Net.fn(name: string, spec: { string }, handler: (Player, ...any) -> (boolean, string?, any?), rate: number?)
	assert(IS_SERVER)
	get(name).OnServerInvoke = function(player: Player, ...)
		if not allow(player, name, rate or 6) then return false, "Too fast, try again" end
		local args = table.pack(...)
		if not validate(spec, args, args.n) then
			warn(("[Net] %s sent bad arguments to %s"):format(player.Name, name))
			return false, "Bad request"
		end
		local res = table.pack(pcall(handler, player, ...))
		if not res[1] then
			warn(("[Net] %s handler error: %s"):format(name, tostring(res[2])))
			return false, "Server error"
		end
		return res[2], res[3], res[4]
	end
end

function Net.fire(player: Player, name: string, ...: any)
	get(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	get(name):FireAllClients(...)
end

---------------------------------------------------------------------------------------------------
-- client API
---------------------------------------------------------------------------------------------------
function Net.send(name: string, ...: any)
	get(name):FireServer(...)
end

function Net.call(name: string, ...: any): (boolean, string?, any?)
	local res = table.pack(pcall(function(...) return get(name):InvokeServer(...) end, ...))
	if not res[1] then return false, "Connection problem" end
	return res[2], res[3], res[4]
end

function Net.listen(name: string, fn: (...any) -> ()): RBXScriptConnection
	return get(name).OnClientEvent:Connect(fn)
end

return Net
