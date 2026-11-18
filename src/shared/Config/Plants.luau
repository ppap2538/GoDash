-- The vegetation library: our own models (tools/blender_trees.py) with our own leaf cards
-- (tools/make_leaf_cards.py), uploaded to Roblox as Model assets. See docs/ASSETS.md section 7.
--
-- Each model is a "Trunk" (bark) and "Leaves" (cards with a transparent background). Roblox imports
-- the leaf texture as a plain texture, which would draw the cards as solid rectangles, so the leaves
-- need a SurfaceAppearance with AlphaMode = Transparency. Game scripts are not allowed to create one;
-- tools/setup_plants.luau does it once in Studio and stores the finished plants in
-- ServerStorage.GoDashPlants, where World/Assets picks them up. A place without that folder (for
-- example one built from src/ alone) falls back to the simple part-built trees.
--
-- crown = where the canopy really starts at scale 1 (studs above the ground): the height below which only
-- 5 % of the leaf-card vertices hang, measured from the meshes in Studio (EditableMesh, 2026-11-19).
-- World/Scenery uses it to keep roadside canopies above the chase camera (owner: "trees too low, they
-- block the screen when I ride along the roadside").
return {
	tree_rain_a = { id = 77659820366860, kind = "rain", crown = 18.7 },
	tree_rain_b = { id = 138279197906613, kind = "rain", crown = 13.8 },
	tree_mango_a = { id = 139560481437384, kind = "mango", crown = 17.1 },
	tree_mango_b = { id = 101090179767571, kind = "mango", crown = 12.7 },
	tree_shade_a = { id = 101556519599051, kind = "shade", crown = 12.8 },
	tree_shade_b = { id = 87217086880833, kind = "shade", crown = 11.2 },
	tree_koon_a = { id = 140497512424084, kind = "koon", crown = 7.0 }, -- golden shower (ราชพฤกษ์ / คูน), Khon Kaen's flower
	tree_koon_b = { id = 111854610068259, kind = "koon", crown = 7.9 },
	tree_frangipani_a = { id = 94295761786020, kind = "frangipani", crown = 8.8 },
	palm_coconut_a = { id = 88791867052650, kind = "coconut", crown = 24 },
	palm_coconut_b = { id = 97665394305767, kind = "coconut", crown = 18 },
	palm_royal_a = { id = 83891513285999, kind = "royal", crown = 32 },
	banana_a = { id = 113854115848199, kind = "banana" },
	shrub_hedge_a = { id = 131756492866188, kind = "hedge" },
	shrub_bougain_a = { id = 121633667586509, kind = "bougainvillea" },
	grass_tuft_a = { id = 98394215069167, kind = "grass" },
}
