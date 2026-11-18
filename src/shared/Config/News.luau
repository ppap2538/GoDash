-- "What's new" card: shown once per VERSION to every rider (client/LiveOps; server records it in
-- d.seenNews). Bump VERSION and rewrite the lines with every update that players should notice.
return {
	VERSION = "2026-11-20",
	LINES = {
		{ icon = "🏮", en = "Loy Krathong at Bueng Kaen Nakhon, 20-30 Nov: float a krathong, fireworks at night", th = "ลอยกระทงบึงแก่นนคร 20-30 พ.ย. ลอยกระทงได้จริง พลุตอนกลางคืน" },
		{ icon = "🛵", en = "Easier driving: calm steering at speed, a better camera, lane assist", th = "ขับง่ายขึ้น: พวงมาลัยนิ่งตอนเร็ว กล้องเห็นถนนไกลขึ้น ช่วยประคองเลน" },
		{ icon = "🚦", en = "Traffic lights only at real junctions, one light per road, countdown timers", th = "ไฟจราจรเฉพาะแยกที่มีไฟจริง ไฟเดียวต่อถนน มีตัวเลขนับถอยหลัง" },
		{ icon = "👻", en = "Late deliveries to lonely places... might get spooky. Then call the ghost radio", th = "ส่งของดึก ๆ ในที่เปลี่ยว อาจเจอดี แล้วโทรเล่าให้วิทยุคืนหลอนฟัง" },
		{ icon = "👥", en = "Invite friends: they get ฿500, you get ฿1,000", th = "ชวนเพื่อนมาเล่น เพื่อนได้ ฿500 คุณได้ ฿1,000" },
		{ icon = "📱", en = "Phones: steer anywhere on the left side, optional auto gas", th = "มือถือ: แตะเลี้ยวตรงไหนก็ได้ฝั่งซ้าย มีโหมดเร่งอัตโนมัติ" },
	},
}
