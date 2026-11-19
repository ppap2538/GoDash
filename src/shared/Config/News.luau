-- "What's new" card: shown once per VERSION to every rider (client/LiveOps; server records it in
-- d.seenNews). Bump VERSION and rewrite the lines with every update that players should notice.
return {
	VERSION = "2026-11-25",
	LINES = {
		{ icon = "📹", en = "Accidents show a CCTV replay; the person you hit gets up and comes over", th = "ชนแล้วมีภาพกล้องวงจรปิด คนเจ็บลุกขึ้นเดินมาคุยเอง" },
		{ icon = "🎬", en = "Clip mode (B): ⏺ records a clip to share · after a crash, keep the moment in slow motion · L replays", th = "โหมดถ่ายคลิป (B): ⏺ อัดคลิปแชร์ได้ · ชนแล้วเก็บคลิปเหตุการณ์แบบสโลว์ · L ดูรีเพลย์" },
		{ icon = "🍜", en = "Don't spill the soup! Hard braking, sharp turns and bumps show on the order meter", th = "ระวังน้ำซุปหก! เบรกแรง เลี้ยวแรง ตกหลุม ดูได้ที่มิเตอร์อาหาร" },
		{ icon = "🍱", en = "Catering orders: deliver together for a bigger pay · rider crews with vests", th = "ออร์เดอร์จัดเลี้ยง ช่วยกันส่งได้เงินก้อนใหญ่ · กลุ่มไรเดอร์ใส่เสื้อทีม" },
		{ icon = "⭐", en = "Regular customers with their own stories · helmets · driving style easy/normal/real", th = "ลูกค้าประจำมีเรื่องราว · หมวกกันน็อก · เลือกสไตล์การขับ ง่าย/ปกติ/สมจริง" },
		{ icon = "🧵", en = "Khon Kaen Silk Festival from 28 Nov: tie ผูกเสี่ยว with a friend, free silk helmet", th = "เทศกาลไหมขอนแก่น 28 พ.ย. นี้ ผูกเสี่ยวกับเพื่อน รับหมวกลายผ้าไหมฟรี" },
	},
}
