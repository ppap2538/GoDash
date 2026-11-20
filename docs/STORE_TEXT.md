# Store page texts (2026-11-18)

Set through Open Cloud on 2026-11-18: the English name and the Thai description below. Roblox translates the English
name for Thai players by itself; for the exact Thai name, the owner types it in Creator Dashboard -> the experience ->
Localization -> Thai -> Experience name (the localization API is not reachable with the Assistant's key).

## Name

- English (source, set): `GoDash 🛵 Thai Rider Life`
- Thai (owner types in Localization): `GoDash 🛵 ไรเดอร์เมืองไทย`
- During an event put a tag in front, then take it off afterwards, e.g. `[🏮 ลอยกระทง] GoDash 🛵 ไรเดอร์เมืองไทย` (20-30 Nov).

## Description (set, Thai)

```
🛵 ขี่มอไซส่งอาหารในขอนแก่นของจริง ขนาด 1:1!

🏮 ลอยกระทงบึงแก่นนคร 20–30 พ.ย. ลอยกระทงได้จริง พลุตอนกลางคืน
📦 รับออเดอร์ ซิ่งไปส่ง ได้ทิป ได้รีวิว 5 ดาว
🧍 รับส่งผู้โดยสาร ทั้งมอไซค์และรถยนต์
🔧 แต่งรถซิ่ง: ไฟใต้ท้อง ป้ายทะเบียน สติกเกอร์ แตร ท่อ
🏍️ รถ 12 คัน จักรยานถึงซูเปอร์คาร์
🍜 แวะกินข้าวข้างทาง ซื้อบ้าน ทำฟาร์ม
👻 ส่งของดึก ๆ ในที่เปลี่ยว... อาจเจอดี แล้วโทรเล่าให้วิทยุคืนหลอนฟัง
🔥 ชั่วโมงเร่งด่วนทุกต้นชั่วโมง ค่าส่ง +50% ชิงอันดับประจำสัปดาห์
👥 ชวนเพื่อนมาเล่น เพื่อนได้ ฿500 คุณได้ ฿1,000
🎁 รางวัลทุกวัน · โค้ด: GODASH

เล่นได้ทั้ง PC · มือถือ · แท็บเล็ต · ภาษาไทย / English
แผนที่ © OpenStreetMap contributors
```

After 30 Nov: remove the 🏮 line (and the name tag).

## Codes for clips (2026-11-19)

One code per clip, so Creator Dashboard > Analytics > Custom events ("Code LOY2569", ...) shows which clip brought
riders in: `LOY2569` (Loy Krathong teaser, to 7 Dec), `PHEE` (ghost + radio clip), `TIKTOK` (profile bio, every clip).
Codes live in `src/shared/Config/Store.luau` (CODES). The owner's own clip helpers (LOYPREVIEW, FIREWORKS, NIGHT, DUSK,
DAY, LOYOFF) are in docs/OVERHAUL.md §19 #8; they only work for the owner's account.

## English description (for an English localization later)

```
🛵 Ride a scooter through a real Thai city, built 1:1!
🏮 Loy Krathong at Bueng Kaen Nakhon, 20–30 Nov: float a krathong, fireworks at night
📦 Grab orders, race to the door, earn tips and 5-star reviews
🔧 Underglow, plates, stickers, horns, exhausts · 12 rides from a bicycle to a supercar
🍜 Street food, your own home, a farm
👻 Late-night deliveries to lonely places... might get spooky
🔥 Rush Hour every hour: +50% pay and a weekly leaderboard
👥 Invite friends: they get ฿500, you get ฿1,000 · 🎁 Code: GODASH
Map © OpenStreetMap contributors
```

## Images

**v4 (set 2026-11-20 afternoon, the toy-brick look; owner: "ภาพหน้าปกก็เปลี่ยนด้วยนะ" ... "ทำต่อให้จบเลย")**: still no text
at all (for the shots every SurfaceGui / BillboardGui was hidden on the client, so shop signs, plates and the pet's
name tag show as plain coloured boards), real Studio Play frames, the Roblox top-bar buttons painted out
(`finish.py`), rider in a plain green shirt with the dog in the basket. Order: 101583340839655 (Loy Krathong night:
fireworks over the lake, krathongs, lamp-lit toy facades), 138134277192738 (riding with the dog on a studded street,
golden afternoon), 104306683443945 (the brick city at sunset from above), 134539346335506 (a fridge on the scooter).
Icon 101418508997653 (the rider and the dog, square crop of the ride frame). All moderation Approved; read back with
`GET /assets/v1/assets/72947456721898?readMask=previews,icon`. Sources `assets/models/page_v4_*.jpg`,
`assets/models/page_icon_v4.png`. Rollback = the v3 list below + icon 109867011608612.

**v3 (set 2026-11-20, owner: "เอาตัวหนังสือออก ... ดูไม่ใช่เกมโปรๆ")**: no text at all, real in-game frames shot in
Studio Play at quality Level21 (viewport 1920x1033, 16:9 window, the Roblox top-bar buttons painted out, a light
grade), rider in a plain green shirt (the avatar's football shirt and the win vest taken off for the shot). Order:
108967661385379 (Loy Krathong night: pier, krathongs, fireworks), 110155452432243 (riding at golden hour, the dog in
the basket), 133804722882969 (big load: a fridge on the scooter), 84198689857352 (riding into the sunset; was still
in moderation review when set). Sources `assets/models/page_v3_*.jpg`. Uploaded with
`creationContext.assetPrivacy = OpenUse`, so no separate permission call.

Before v3 (for a rollback, `PATCH /assets/v1/assets/72947456721898?updateMask=previews`): 105822105345048 (Loy
Krathong), 78906189388680 (ride), 76079295322715 (styling), 135989347837853 (night radio), 118277502747835 (rewards).
Icon 97841633896740 → later 109867011608612 (icon v3, 2026-11-19). v2 sources `assets/models/page_*v2*.png`.

## Description v3 (2026-11-20, SET through Open Cloud on the root place after the owner's go-ahead; the universe mirrors it)

On 2026-11-20 the place and universe description read `hagame lemon pillow brave` (changed 2026-11-19 by someone
other than this repo's sessions; Thai players saw it machine-translated as "หมอนมะนาวฮากาเมะที่กล้าหาญ"), and the name
had become `GoDash Rider Thailand` (name left as is). The first Open Cloud write was refused by the Assistant's safety
check; the owner then said to set it ("แก้ให้ทีนายมี API อยู่นะ") and it went through:
`PATCH /cloud/v2/universes/10776539389/places/72947456721898?updateMask=description` (704 characters; limit 1000):

```
🛵 ขี่มอไซค์ส่งอาหารทั่วขอนแก่น เมืองจริงขนาด 1:1!

🏮 อีเวนต์ลอยกระทง บึงแก่นนคร 20–30 พ.ย. ลอยกระทงได้จริง มีพลุทุกคืน

📦 รับออเดอร์ ซิ่งไปส่ง เก็บทิปและรีวิว 5 ดาว
🧊 ออเดอร์ของใหญ่สุดฮา: ตู้เย็น ฟูก ทุเรียน ขนบนสกู๊ตเตอร์!
🧍 รับส่งผู้โดยสาร ทั้งมอไซค์และรถยนต์
🔧 แต่งรถ: ไฟใต้ท้อง ป้ายทะเบียน สติกเกอร์ แตรเพลง ท่อ
🏍️ รถ 12 คัน ตั้งแต่จักรยานถึงซูเปอร์คาร์
🐶 พาหมาซ้อนตะกร้าหน้ารถไปส่งของด้วยกัน
🚔 สมัครเป็นตำรวจจราจร ไล่จับคนฝ่าไฟแดง
🎥 โหมดอัดคลิปแนวตั้งในเกม แชร์ลง TikTok ได้เลย

⏰ ชั่วโมงเร่งด่วนทุกต้นชั่วโมง ค่าส่ง +50%
👥 ชวนเพื่อน: เพื่อนได้ ฿500 คุณได้ ฿1,000
🎁 โค้ด: GODASH

👍 กดไลก์ + ⭐ กดติดตาม เพื่อรับอัปเดตใหม่ก่อนใคร!
เล่นได้ทั้ง PC · มือถือ · แท็บเล็ต
แผนที่ © OpenStreetMap contributors
```

After 30 Nov: delete the 🏮 line and move the Loy Krathong thumbnail to the end (or drop it).
