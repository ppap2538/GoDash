-- "What's new" card: shown once per VERSION to every rider (client/LiveOps; server records it in
-- d.seenNews). Bump VERSION and rewrite the lines with every update that players should notice.
return {
	VERSION = "2026-11-23",
	LINES = {
		{ icon = "📹", en = "Accidents now show the CCTV replay, and the person you hit gets up and comes over", th = "ชนแล้วมีภาพกล้องวงจรปิดย้อนหลัง คนเจ็บลุกขึ้นเดินมาคุยเอง" },
		{ icon = "🤝", en = "Sometimes they let it go: a light bump may cost nothing", th = "บางทีคู่กรณีก็ไม่เอาเรื่อง ชนเบาๆ อาจไม่ต้องจ่าย" },
		{ icon = "🚶", en = "People step out of your way and look before they cross", th = "คนเดินถนนหลบรถ และมองซ้ายขวาก่อนข้ามถนน" },
		{ icon = "🛵", en = "Easier steering: quicker turns, lane assist waits after you steer", th = "บังคับรถง่ายขึ้น เลี้ยวไวขึ้น ระบบประคองเลนไม่ดึงสู้มือแล้ว" },
		{ icon = "🌳", en = "Taller street trees: the shade is over your head, not in your view", th = "ต้นไม้ริมถนนสูงขึ้น ร่มเงาอยู่เหนือหัว ไม่บังจอแล้ว" },
		{ icon = "🚓", en = "Run a red light and a police motorbike pulls up behind you", th = "ฝ่าไฟแดง ตำรวจขี่มอไซมาจอดเรียกข้างหลัง" },
	},
}
