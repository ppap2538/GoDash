--!strict
-- Small shared helpers. No game state here.
local Util = {}

function Util.clamp(v: number, a: number, b: number): number
	if v < a then return a end
	if v > b then return b end
	return v
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.round(v: number, step: number?): number
	local s = step or 1
	return math.floor(v / s + 0.5) * s
end

function Util.isFinite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Util.deepCopy(t: any): any
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = Util.deepCopy(v) end
	return out
end

-- Fill missing keys of `data` from `template` (recursively for dictionaries).
function Util.reconcile(data: any, template: any)
	for k, v in pairs(template) do
		if data[k] == nil then
			data[k] = Util.deepCopy(v)
		elseif type(v) == "table" and type(data[k]) == "table" and next(v) ~= nil and #v == 0 then
			Util.reconcile(data[k], v)
		end
	end
end

function Util.money(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (n < 0 and "-" or "") .. "฿" .. out
end

function Util.num(n: number): string
	local s = tostring(math.floor(math.abs(n) + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return (n < 0 and "-" or "") .. out
end

function Util.duration(sec: number): string
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return string.format("%dh %02dm", sec // 3600, (sec % 3600) // 60)
	elseif sec >= 60 then
		return string.format("%dm %02ds", sec // 60, sec % 60)
	end
	return string.format("%ds", sec)
end

-- The world is 1:1 with 1 stud = 0.28 m.
Util.METRES = 0.28
function Util.dist(studs: number): string
	local m = studs * 0.28
	if m >= 1000 then return string.format("%.1f km", m / 1000) end
	return string.format("%d m", math.floor(m / 10 + 0.5) * 10)
end

-- Day number in Thailand time (UTC+7); daily systems reset on it.
function Util.dayNumber(t: number?): number
	return math.floor(((t or os.time()) + 7 * 3600) / 86400)
end

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Util.pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

function Util.count(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do n += 1 end
	return n
end

return Util
