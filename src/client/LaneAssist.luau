-- Lane assist (2026-11-18, owner: "driving is quite hard on PC and on the phone").
-- While the rider barely steers, a gentle pull keeps the vehicle in the middle of its lane: the left half of a two-way
-- road (Thai traffic keeps left), the left lane of a one-way road. It lets go
--   * as soon as the rider steers (Drive only asks below 8 % input) or uses the handbrake,
--   * near junctions (that is where you turn), off the road, below ~12 km/h, on auto drive.
-- Phone > Settings > Lane assist: on / off; until the rider picks, it is on for touch screens and off for keyboards.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadGraph = require(Shared.RoadGraph)
local GPS = require(script.Parent.GPS)
local Drive = require(script.Parent.Drive)
local State = require(script.Parent.State)
local Layout = require(script.Parent.UI.Core.Layout)

local LaneAssist = {}

local function enabled(): boolean
	local s = State.data and State.data.settings
	if s and s.lane ~= nil then return s.lane == true end
	return Layout.isTouch
end
LaneAssist.enabled = enabled

local function correction(c, ctx): number?
	if not enabled() then return nil end
	local v = ctx.speedF
	if v < 12 then return nil end
	local graph = GPS.graph()
	if not graph then return nil end
	local pos = c.chassis.Position
	local fwd = ctx.fwd
	local best, bestD2, bestDot, bestT
	for _, e in ipairs(graph:edgesNear(pos, 40)) do
		local _, _, t, d2 = RoadGraph.project(e, pos.X, pos.Z)
		local half = e.def.width / 2
		if d2 < (half + 3) ^ 2 then
			local dot = e.dx * fwd.X + e.dz * fwd.Z
			if math.abs(dot) > 0.9 and (not best or d2 < bestD2) then
				best, bestD2, bestDot, bestT = e, d2, dot, t
			end
		end
	end
	if not best then return nil end
	-- near either end of a street that is a junction: let the rider turn
	local along = bestT * best.len
	local nearA = along < best.len - along
	local node = nearA and best.a or best.b
	if math.min(along, best.len - along) < node.r + 18 and #node.links >= 3 then return nil end
	local sgn = bestDot > 0 and 1 or -1 -- (the map has no one-way direction: follow the way the rider goes)
	local dx, dz = best.dx * sgn, best.dz * sgn
	local rx, rz = -dz, dx -- right of the direction of travel
	local half = best.def.width / 2
	local px, pz = RoadGraph.project(best, pos.X, pos.Z)
	local cx, cz = px - rx * half * 0.5, pz - rz * half * 0.5 -- lane centre: half of the half-width to the left
	local lateral = (pos.X - cx) * rx + (pos.Z - cz) * rz -- + = right of the lane centre
	local headingRight = fwd.X * rx + fwd.Z * rz -- + = pointing right of the road
	local wantHeading = -math.clamp(lateral * 0.05, -0.12, 0.12) -- drift back at a shallow angle
	local err = headingRight - wantHeading
	local angle = -err * 1.1
	return math.clamp(angle / math.max(ctx.maxAngle, 0.02), -0.25, 0.25)
end

function LaneAssist.start()
	Drive.laneAssist = correction
end

return LaneAssist
