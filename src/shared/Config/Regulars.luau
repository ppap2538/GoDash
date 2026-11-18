-- Regular customers (2026-11-19, owner: "ทำตามที่แนะนำ"): five people in town who order at their own hours from
-- their own homes (server/RegularsService picks an address near their anchor place). The more you deliver to one
-- (d.regulars[id]), the better they tip (+5 % a step, up to +20 %) and the more of their story they tell you:
-- a line at the 1st, 3rd, 7th and 12th delivery, and a small thank-you at the 12th. Made-up people only.
local Regulars = {}

Regulars.LIST = {
	{ id = "yai", anchor = "freshmarket", from = 6, to = 10.5, icon = "👵",
		en = "Grandma Somsri", th = "ยายสมศรี",
		lines = {
			[1] = { "Thank you, dear. My knees can't do the market any more.", "ขอบใจจ้ะหลาน ยายเดินไปตลาดไม่ไหวแล้ว" },
			[3] = { "It's you again! I remember you. Ride carefully, won't you?", "หลานคนเดิมอีกแล้ว ยายจำได้นะ ขับระวังด้วยล่ะ" },
			[7] = { "I've told the whole soi you're the fastest rider in town.", "ยายเล่าให้ทั้งซอยฟังแล้วว่าหลานส่งไวที่สุด" },
			[12] = { "Here, take these sweets. I made them myself this morning.", "เอาขนมไปกินด้วยนะ ยายทำเองเมื่อเช้า" },
		} },
	{ id = "fah", anchor = "university", from = 20, to = 26, icon = "📚",
		en = "Fah (student)", th = "น้องฟ้า นักศึกษา",
		lines = {
			[1] = { "You saved me! I'm studying all night for an exam.", "พี่ช่วยชีวิตหนูไว้ อ่านหนังสือสอบทั้งคืนเลย" },
			[3] = { "Same rider! I passed, and your milk tea helped.", "พี่ไรเดอร์คนเดิม! สอบผ่านแล้วนะ ชานมพี่ช่วยได้เยอะ" },
			[7] = { "Everyone in my dorm orders now. They say you're kind.", "เพื่อนในหอสั่งตามหนูหมดแล้ว บอกว่าพี่ใจดี" },
			[12] = { "I graduate next week! Thank you for every late night.", "อาทิตย์หน้าหนูจบแล้วนะพี่ ขอบคุณที่อยู่ด้วยกันทุกคืน" },
		} },
	{ id = "chai", anchor = "dealer", from = 11, to = 14.5, icon = "🔧",
		en = "Uncle Chai (mechanic)", th = "ลุงชัย ร้านซ่อมรถ",
		lines = {
			[1] = { "Leave it there, my hands are full of grease.", "วางไว้ตรงนั้นแหละ มือเปื้อนน้ำมันอยู่" },
			[3] = { "Your bike sounds funny. Mind the engine oil.", "รถเอ็งเสียงแปลกๆ นะ ระวังน้ำมันเครื่องด้วย" },
			[7] = { "Come here, I'll change your oil. On the house.", "มานี่ ลุงเปลี่ยนน้ำมันเครื่องให้ ไม่คิดตังค์" },
			[12] = { "You're the rider I trust most in this town.", "เอ็งเป็นไรเดอร์ที่ลุงไว้ใจที่สุดในเมืองนี้" },
		} },
	{ id = "kaew", anchor = "nightmarket", from = 17, to = 23.5, icon = "🥗",
		en = "Kaew (som tam stall)", th = "พี่แก้ว ร้านส้มตำ",
		lines = {
			[1] = { "Quick, quick! The ice is for my stall.", "เร็วๆ จ้า น้ำแข็งเอาไปร้าน" },
			[3] = { "You're on time every time. Not like the others!", "มาตรงเวลาทุกที ไม่เหมือนคนอื่นเลย" },
			[7] = { "Next time sit down, I'll make you a plate of som tam.", "คราวหน้านั่งก่อน พี่ตำส้มตำให้จานนึง" },
			[12] = { "My stall is busier than ever. Thanks to you too.", "ร้านพี่ขายดีขึ้นเยอะ ส่วนหนึ่งก็เพราะน้องนี่แหละ" },
		} },
	{ id = "doc", anchor = "hospital", from = 22, to = 30, icon = "🩺",
		en = "Dr. Beer (night shift)", th = "หมอเบียร์ เวรดึก",
		lines = {
			[1] = { "Coffee, at last. Long night in the ward.", "กาแฟมาแล้ว คืนนี้เวรยาวเลย" },
			[3] = { "You again. Wear your helmet, I see too many crashes.", "คนเดิมอีกแล้ว ใส่หมวกกันน็อกด้วยนะ หมอเห็นคนเจ็บเยอะ" },
			[7] = { "The nurses call you 'our rider' now.", "พยาบาลเรียกน้องว่าไรเดอร์ประจำวอร์ดแล้วนะ" },
			[12] = { "Take care of yourself out there. Really.", "ดูแลตัวเองด้วยนะ หมอพูดจริง" },
		} },
}
Regulars.BY_ID = {}
for _, r in ipairs(Regulars.LIST) do Regulars.BY_ID[r.id] = r end
Regulars.GIFT = 200 -- the thank-you at the 12th delivery

-- extra tip share for n deliveries already made to this regular
function Regulars.tipBonus(n: number): number
	return math.min(0.2, 0.05 * math.floor((n or 0) / 3 + 0.0001) + ((n or 0) >= 1 and 0.05 or 0))
end

-- is hour h inside [from, to) (to may run past midnight: 26 = 02:00)
function Regulars.awake(r, h: number): boolean
	if h >= r.from and h < r.to then return true end
	return r.to > 24 and h + 24 >= r.from and h + 24 < r.to
end

return Regulars
