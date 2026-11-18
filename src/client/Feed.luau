-- "City Feed" phone app (owner, 2026-11-17: "reflect Thai society, satire, funny"). Made-up locals post
-- about town life and about what the player just did: crashes, tickets, reviews, soi dogs, floods,
-- the neighbour's gossip. Posts come from three places:
--   * the server: Notify("feed", { key, vars }) — fines, reviews, job twists, dogs, loans, licence, ...
--   * this client: Feed.post(key, vars) — the crash cutscene, floods, potholes, street life
--   * every couple of minutes an ordinary town post (Config/Feed.ambient)
-- Posts about the player also pop a short toast. Nothing is saved: the feed is this session's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Game = require(Shared.Config.Game)
local Map = require(Shared.Config.Maps[Game.MAP])
local Config = require(Shared.Config.Feed)
local UI = require(script.Parent.UI.Kit)
local Lang = require(script.Parent.Lang)
local Feedback = require(script.Parent.Feedback)
local Phone = require(script.Parent.Phone)

local Feed = {}
local C, F = UI.C, UI.F
local player = Players.LocalPlayer
local MAX = 40
local posts = {} -- newest first: { author, icon, text, likes, comments = {string}, at = os.clock(), me = bool }
local unread = 0
local rng = Random.new()

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function placeName(pos: Vector3?): string
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local p = pos or (r and r.Position)
	if not p then return Lang.pick("town", "ในเมือง") end
	local z = Map.zoneAt(p.X, p.Z)
	return z and Lang.name(z) or Lang.pick("town", "ในเมือง")
end

local function fill(text: string, vars): string
	vars = vars or {}
	return (text:gsub("{(%w+)}", function(k)
		if k == "name" then return player.DisplayName end
		if k == "place" then return vars.place or placeName(vars.pos) end
		local v = vars[k]
		return v ~= nil and tostring(v) or ""
	end))
end

local function ago(t: number): string
	local s = os.clock() - t
	if s < 60 then return Lang.pick("just now", "เมื่อสักครู่") end
	local m = math.floor(s / 60)
	return Lang.pick(m .. " min", m .. " นาที")
end

-- key: a list in Config/Feed.posts; vars: { place?, pos?, amount?, who? }; me: about the player (toast)
function Feed.post(key: string, vars: any?, me: boolean?)
	local list = Config.posts[key]
	if not list then return end
	local tpl = pick(list)
	local a = pick(Config.authors)
	local text = fill(Lang.code == "th" and tpl.th or tpl.en, vars)
	local comments = {}
	for _ = 1, rng:NextInteger(1, 3) do
		local c = pick(Config.comments)
		table.insert(comments, Lang.code == "th" and c.th or c.en)
	end
	table.insert(posts, 1, {
		author = Lang.code == "th" and a[1] or a[2], icon = a[3], text = text,
		likes = rng:NextInteger(me and 40 or 3, me and 2400 or 380), comments = comments, at = os.clock(), me = me == true,
	})
	if #posts > MAX then table.remove(posts) end
	unread += 1
	if me then
		local short = #text > 70 and (utf8.offset(text, 60) and text:sub(1, utf8.offset(text, 60) - 1) .. "…" or text) or text
		Feedback.toast("📣 " .. short, nil)
	end
	if Phone.isOpen() and (Phone.current() == "feed" or Phone.current() == "home") then Phone.refresh() end
end

local function screen()
	local ui = Phone.ui
	unread = 0
	local hero = ui.bigCard(66, Color3.fromRGB(58, 89, 152))
	UI.label(hero, Lang.pick("📣 City Feed", "📣 ฟีดเมืองขอนแก่น"), 18, C.white, F.black, { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 24) })
	UI.label(hero, Lang.pick("Everyone saw it. Everyone has an opinion.", "ทุกคนเห็น ทุกคนมีความเห็น"), 12, Color3.fromRGB(214, 222, 240), F.med,
		{ Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 18) })
	if #posts == 0 then
		UI.label(ui.content(), Lang.pick("Nothing yet. Go and do something silly.", "ยังไม่มีโพสต์ ออกไปทำอะไรฮาๆ ก่อนสิ"), 13, C.sub, F.med, { TextXAlignment = Enum.TextXAlignment.Center })
		return
	end
	for _, p in ipairs(posts) do
		local card = UI.card(ui.content(), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = p.me and Color3.fromRGB(255, 248, 232) or C.card })
		UI.pad(card, 12, 10, 12, 10)
		UI.list(card, 4)
		local head = UI.label(card, p.icon .. "  " .. p.author .. "  ·  " .. ago(p.at), 12, C.sub, F.bold, { Size = UDim2.new(1, 0, 0, 18) })
		head:SetAttribute("NoTranslate", true)
		local body = UI.label(card, p.text, 14, C.text, F.med, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })
		body:SetAttribute("NoTranslate", true)
		local meta = UI.label(card, ("❤️ %d   💬 %d   ↗️ %d"):format(p.likes, #p.comments + math.floor(p.likes / 9), math.floor(p.likes / 14)), 11, C.sub, F.med, { Size = UDim2.new(1, 0, 0, 16) })
		meta:SetAttribute("NoTranslate", true)
		for _, c in ipairs(p.comments) do
			local cl = UI.label(card, "   💬 " .. c, 12, C.text, F.med, { Size = UDim2.new(1, 0, 0, 16), TextTransparency = 0.25 })
			cl:SetAttribute("NoTranslate", true)
		end
	end
end

function Feed.start()
	Phone.addApp({ id = "feed", name = "City Feed", icon = "📣", color = Color3.fromRGB(58, 89, 152), badge = function() return unread > 0 end }, screen)
	Net.listen("Notify", function(kind, p)
		if kind == "feed" and type(p) == "table" and type(p.key) == "string" then
			Feed.post(p.key, p.vars, p.me ~= false)
		elseif kind == "levelup" then
			Feed.post("levelup", nil, false)
		end
	end)
	-- ordinary town life every couple of minutes
	task.spawn(function()
		task.wait(20)
		Feed.post("ambient", nil, false)
		while true do
			task.wait(rng:NextNumber(80, 150))
			Feed.post("ambient", nil, false)
		end
	end)
end

return Feed
