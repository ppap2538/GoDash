-- The vegetation library: our own models (tools/blender_trees.py) with our own leaf cards
-- (tools/make_leaf_cards.py), uploaded to Roblox as Model assets. See docs/ASSETS.md section 7.
--
-- Each model is a "Trunk" (bark) and "Leaves" (cards with a transparent background). Roblox imports
-- the leaf texture as a plain texture, which would draw the cards as solid rectangles, so the leaves
-- need a SurfaceAppearance with AlphaMode = Transparency. Game scripts are not allowed to create one;
-- tools/setup_plants.luau does it once in Studio and stores the finished plants in
-- ServerStorage.GoDashPlants, where World/Assets picks them up. A place without that folder (for
-- example one built from src/ alone) falls back to the simple part-built trees.
return {
	tree_rain_a = { id = 77659820366860, kind = "rain" },
	tree_rain_b = { id = 138279197906613, kind = "rain" },
	tree_mango_a = { id = 139560481437384, kind = "mango" },
	tree_mango_b = { id = 101090179767571, kind = "mango" },
	tree_shade_a = { id = 101556519599051, kind = "shade" },
	tree_shade_b = { id = 87217086880833, kind = "shade" },
	tree_koon_a = { id = 140497512424084, kind = "koon" }, -- golden shower (ราชพฤกษ์ / คูน), Khon Kaen's flower
	tree_koon_b = { id = 111854610068259, kind = "koon" },
	tree_frangipani_a = { id = 94295761786020, kind = "frangipani" },
	palm_coconut_a = { id = 88791867052650, kind = "coconut" },
	palm_coconut_b = { id = 97665394305767, kind = "coconut" },
	palm_royal_a = { id = 83891513285999, kind = "royal" },
	banana_a = { id = 113854115848199, kind = "banana" },
	shrub_hedge_a = { id = 131756492866188, kind = "hedge" },
	shrub_bougain_a = { id = 121633667586509, kind = "bougainvillea" },
	grass_tuft_a = { id = 98394215069167, kind = "grass" },
}
