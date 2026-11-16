-- PBR surface materials. Textures are CC0 from Poly Haven (https://polyhaven.com), uploaded to
-- Roblox as images; see docs/ASSETS.md for every source page. The server turns each entry into a
-- MaterialVariant at start-up, so the look is code-driven and survives rebuilding the place file.
-- tile = studs per texture repeat (1 stud = 0.28 m), tuned to the real size of each surface.
local function id(n: number): string
	return "rbxassetid://" .. n
end

local Materials = {}

Materials.VARIANTS = {
	GD_Asphalt = { base = Enum.Material.Asphalt, tile = 16, color = id(125614374725974), normal = id(124828364292160), rough = id(95756026683349) },
	GD_AsphaltWorn = { base = Enum.Material.Asphalt, tile = 14, color = id(105525395870510), normal = id(100243160453550), rough = id(139750860968425) },
	GD_Sidewalk = { base = Enum.Material.Pavement, tile = 9, color = id(132775575324469), normal = id(98058705114256), rough = id(70605451089670) },
	GD_Pavers = { base = Enum.Material.Pavement, tile = 8, color = id(83729108195351), normal = id(96966314887198), rough = id(137254461752540) },
	GD_Plaster = { base = Enum.Material.Concrete, tile = 14, color = id(74700249327489), normal = id(139816245219052), rough = id(119926541563340) },
	GD_PaintedWall = { base = Enum.Material.Concrete, tile = 12, color = id(101703834717827), normal = id(110888895624403), rough = id(123266997257457) },
	GD_ConcreteWall = { base = Enum.Material.Concrete, tile = 12, color = id(100414646282423), normal = id(75825138724292), rough = id(101355776713963) },
	GD_ConcreteFloor = { base = Enum.Material.Concrete, tile = 12, color = id(105786405880588), normal = id(123207604362366), rough = id(136241009958703) },
	GD_RoofTiles = { base = Enum.Material.Slate, tile = 7, color = id(81264358933920), normal = id(125674497254964), rough = id(120922974020627) },
	GD_Corrugated = { base = Enum.Material.CorrodedMetal, tile = 7, color = id(138196366813777), normal = id(89682886368472), rough = id(113967201108547), metal = id(120402093839233) },
	GD_Brick = { base = Enum.Material.Brick, tile = 8, color = id(126618198522457), normal = id(129190122765379), rough = id(90099181177859) },
	GD_Grass = { base = Enum.Material.Grass, tile = 18, color = id(101346421569398), normal = id(92742961204835), rough = id(90812838438458) },
	GD_Shutter = { base = Enum.Material.Metal, tile = 6, color = id(134623812783935), normal = id(86603671838200), rough = id(102569562762226) },
	GD_Tiles = { base = Enum.Material.Marble, tile = 9, color = id(127032231964117), normal = id(117990414036186), rough = id(125689958176084) },
}

-- Which variant a part gets when the builders ask for a base material without naming one.
Materials.DEFAULT = {
	[Enum.Material.Asphalt] = "GD_Asphalt",
	[Enum.Material.Pavement] = "GD_Pavers",
	[Enum.Material.Concrete] = "GD_Plaster",
	[Enum.Material.Slate] = "GD_RoofTiles",
	[Enum.Material.CorrodedMetal] = "GD_Corrugated",
	[Enum.Material.Brick] = "GD_Brick",
	[Enum.Material.Marble] = "GD_Tiles",
}

return Materials
