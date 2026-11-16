-- Mesh models the server loads at start (World/Assets). Builders fall back to their own simple
-- parts when a model cannot be loaded (for example in an unpublished place file).
--   kind "prop"    : CC0 models from Poly Haven, reduced in Blender and uploaded (docs/ASSETS.md)
--   kind "vehicle" : generated in Roblox Studio (Assistant mesh generation); bikes have separate wheels
--   kind "tree" / "npc" : generated in Roblox Studio
-- yaw = degrees to turn the model so its front faces local -Z; collide = solid for vehicles.
return {
	chair = { id = 78916101840021, kind = "prop", source = "plastic_monobloc_chair_01", yaw = 0, collide = false },
	box = { id = 97338872927397, kind = "prop", source = "utility_box_01", yaw = 0, collide = true },
	plant = { id = 128599174038460, kind = "prop", source = "potted_plant_04", yaw = 0, collide = false },
	trash = { id = 82890708093077, kind = "prop", source = "metal_trash_can", yaw = 0, collide = true },
	aircon = { id = 77575198154795, kind = "prop", source = "exterior_aircon_unit", yaw = 0, collide = false },
	manhole = { id = 132503814450919, kind = "prop", source = "water_manhole_cover", yaw = 0, collide = false },
	cart = { id = 136492442494037, kind = "prop", source = "CoffeeCart_01", yaw = 0, collide = true },
	shrub = { id = 115943909801276, kind = "prop", source = "shrub_03", yaw = 0, collide = false },

	v_bicycle = { id = 130696562359053, kind = "vehicle" },
	v_moped = { id = 76441750877883, kind = "vehicle" },
	v_scooter = { id = 106821451835038, kind = "vehicle" },
	v_sedan = { id = 75378759095601, kind = "vehicle" },
	v_hatch = { id = 79591357293001, kind = "vehicle" },
	v_pickup = { id = 133492243486039, kind = "vehicle" },
	v_sport = { id = 125445164931050, kind = "vehicle" },
	v_bigbike = { id = 110430906993215, kind = "vehicle" },
	v_suv = { id = 101382402201251, kind = "vehicle" },
	v_lux = { id = 74104843499091, kind = "vehicle" },
	v_super = { id = 121796219956878, kind = "vehicle" },

	tree_rain = { id = 130525039494562, kind = "tree", collide = false },
	tree_palm = { id = 101530842680223, kind = "tree", collide = false },

	npc_vendor = { id = 92402083194586, kind = "npc", collide = false },
	npc_man = { id = 99614992014947, kind = "npc", collide = false },
	npc_student = { id = 103336562920583, kind = "npc", collide = false },
}
