-- "What's new" card: shown once per VERSION to every rider (client/LiveOps; server records it in
-- d.seenNews). Bump VERSION and rewrite the lines with every update that players should notice.
return {
	VERSION = "2026-11-23",
	LINES = {
		{ icon = "📹", en = "Accidents show a CCTV replay; the person you hit gets up and comes over", th = "ชนแล้วมีภาพกล้องวงจรปิด คนเจ็บลุกขึ้นเดินมาคุยเอง" },
		{ icon = "⏪", en = "Replay your last 10 seconds from six cameras: press L (or ⏪ in clip mode)", th = "ดูรีเพลย์ 10 วิล่าสุด 6 มุมกล้อง กด L (หรือ ⏪ ในโหมดถ่ายคลิป)" },
		{ icon = "🍜", en = "Don't spill the soup! Hard braking, sharp turns and bumps show on the order meter", th = "ระวังน้ำซุปหก! เบรกแรง เลี้ยวแรง ตกหลุม ดูได้ที่มิเตอร์อาหาร" },
		{ icon = "🛡", en = "Vehicle insurance (class 1 / 2+ / 3) in the phone: the insurer pays and sends a surveyor", th = "ประกันรถชั้น 1 / 2+ / 3 ในมือถือ ชนแล้วประกันจ่าย มีพนักงานเคลมมาให้" },
		{ icon = "⚠️", en = "Breakdowns, crashes and pop-up markets around town; rush-hour traffic with indicators", th = "รถเสีย อุบัติเหตุ ตลาดนัดปิดถนน รถติดชั่วโมงเร่งด่วน รถ AI เปิดไฟเลี้ยว" },
		{ icon = "🔊", en = "New riding sounds; people dodge; easier steering; taller street trees", th = "เสียงขับรถใหม่ คนหลบรถ บังคับง่ายขึ้น ต้นไม้ไม่บังจอ" },
	},
}
