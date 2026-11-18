-- Adopt a soi dog (2026-11-19, owner: "รับเลี้ยงหมาซอย ให้นั่งตะกร้าหน้ารถไปด้วย").
-- Walk up to a soi dog, adopt it (vaccines + collar), pick its name from the list (no typed names: all ages),
-- and it follows you on foot and rides in front of you on a bike: in the basket of a bicycle, standing on the
-- floorboard of a scooter, on the tank of the others. server/PetService, client/Pets.
local Pets = {}

Pets.PRICE = 300 -- baht: vaccines + a collar
Pets.NAMES = {
	{ th = "ข้าวตัง", en = "Khao Tang" }, { th = "ส้มโอ", en = "Som-O" }, { th = "มะลิ", en = "Mali" }, { th = "บราวนี่", en = "Brownie" },
	{ th = "ทองแดง", en = "Thong Daeng" }, { th = "เจ้าด่าง", en = "Spotty" }, { th = "ลูกชิ้น", en = "Meatball" }, { th = "หมูกรอบ", en = "Crispy" },
	{ th = "ถั่วแดง", en = "Red Bean" }, { th = "โกโก้", en = "Cocoa" }, { th = "ขนมปัง", en = "Bread" }, { th = "ภูผา", en = "Phupha" },
}
-- coat colours for the dogs drawn without the mesh model (the soi dogs' "Look" 1-4)
Pets.COATS = {
	Color3.fromRGB(196, 150, 96), Color3.fromRGB(70, 60, 54), Color3.fromRGB(226, 214, 196), Color3.fromRGB(150, 104, 66),
}

return Pets
