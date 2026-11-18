-- "What's new" card: shown once per VERSION to every rider (client/LiveOps; server records it in
-- d.seenNews). Bump VERSION and rewrite the lines with every update that players should notice.
return {
	VERSION = "2026-11-23",
	LINES = {
		{ icon = "📹", en = "Accidents show a CCTV replay; the person you hit gets up and comes over", th = "ชนแล้วมีภาพกล้องวงจรปิด คนเจ็บลุกขึ้นเดินมาคุยเอง" },
		{ icon = "⏪", en = "Replay your last 10 seconds from six cameras: press L (or ⏪ in clip mode)", th = "ดูรีเพลย์ 10 วิล่าสุด 6 มุมกล้อง กด L (หรือ ⏪ ในโหมดถ่ายคลิป)" },
		{ icon = "🍜", en = "Don't spill the soup! Hard braking, sharp turns and bumps show on the order meter", th = "ระวังน้ำซุปหก! เบรกแรง เลี้ยวแรง ตกหลุม ดูได้ที่มิเตอร์อาหาร" },
		{ icon = "🔊", en = "New riding sounds: indicators, tyre squeal, bumps, near misses, crashes", th = "เสียงใหม่: ไฟเลี้ยว ยางเอี๊ยด ตกหลุม รถเฉียด ล้มไถล" },
		{ icon = "🚶", en = "People step out of your way; easier steering; taller street trees", th = "คนหลบรถ บังคับรถง่ายขึ้น ต้นไม้ริมถนนไม่บังจอ" },
		{ icon = "🚓", en = "Run a red light and a police motorbike pulls up behind you", th = "ฝ่าไฟแดง ตำรวจขี่มอไซมาจอดเรียกข้างหลัง" },
	},
}
