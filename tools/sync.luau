-- Pull script sources from the local project into the open Roblox place (Studio command bar / MCP, Edit mode).
-- Before running:  python -I tools/sync_studio.py   and   python -m http.server 8791 --bind 127.0.0.1  (project root)
-- Needs "localhost:8791" in Assistant settings -> MCP permissions -> HTTP allow list.
-- Afterwards:      python -I tools/sync_studio.py --done   and save the place.
local H = game:GetService("HttpService")
local list = H:JSONDecode(H:GetAsync("http://localhost:8791/tools/sync.json", true))
local same, changed, created = 0, 0, 0
for _, e in ipairs(list) do
	local inst: Instance = game
	local parts = string.split(e.path, ".")
	for i, name in ipairs(parts) do
		local nextInst = (i == 1) and game:GetService(name) or inst:FindFirstChild(name)
		if not nextInst then
			nextInst = Instance.new(i == #parts and e.class or "Folder")
			nextInst.Name = name
			nextInst.Parent = inst
			if i == #parts then created += 1 end
		end
		inst = nextInst
	end
	if (inst :: any).Source == e.source then
		same += 1
	else
		(inst :: any).Source = e.source
		changed += 1
	end
end
game:GetService("ChangeHistoryService"):SetWaypoint("GoDash: sync scripts from src/")
return string.format("%d scripts: identical=%d updated=%d created=%d", #list, same, changed, created)
