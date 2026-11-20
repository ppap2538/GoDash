-- The game's art style (2026-11-20, owner: "อยากได้ฟิลตัวต่อ ... ทุกอย่างเลยเอาจริงๆ": the whole game like the
-- big Roblox games, plastic toy bricks with studs, not the photo-real look of 2026-11-16..19).
--
-- BRICKS = true:
--   * every part the world builders make becomes a toy brick (Shared/Bricks: Plastic, studs on top, classic
--     brick colours), the photo-scanned surface textures (Config/Materials) are not used;
--   * the realistic mesh models (Config/Models, Config/Plants, ReplicatedStorage.GoDashModels) are skipped and
--     every builder draws its own part-built version instead (they all have one);
--   * client/Env lights the world like a bright Roblox day instead of the filmic grade.
-- Set it to false to get the realistic look back exactly as it was.
local Look = {}

Look.BRICKS = true

-- The same evening, after playing it, the owner wanted some things real again: "เปลี่ยนรถเป็นรถแบบสมจริงหน่อย",
-- "คนก็ขอเป็นสมจริงเหมือนเดิมนะ", "พวกต้นไม้ด้วยนะขอสมจริง". So with BRICKS the city itself (roads, ground, buildings,
-- street furniture) is bricks, while vehicles, people, their cargo and all plants keep the realistic models.
Look.REAL_KINDS = { vehicle = true, npc = true, tree = true } -- Config/Models kinds kept
Look.REAL_NAMES = { plant = true, shrub = true } -- single Config/Models entries kept (potted plant, shrub)
Look.BRICK_TREES = false -- true = World/Scenery's studded block trees instead of the plant library

return Look
