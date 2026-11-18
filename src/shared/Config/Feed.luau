-- "City Feed" (phone app, client/Feed): made-up posts by made-up locals about what happens in town,
-- including what the player just did. Satire of Thai social media: everybody saw it, everybody comments.
-- Every name is fictional. Never real people, brands, politicians, royalty or religion.
-- {name} = the player, {place} = where it happened, {amount} = money, {who} = a customer.
local function t(th: string, en: string) return { th = th, en = en } end

local Feed = {}

Feed.authors = {
	{ "ป้าแดง ส้มตำปากซอย", "Auntie Daeng's Somtam", "👵" },
	{ "เพจ ขอนแก่นบ่มีหยัง", "Khon Kaen Nothing Happens (page)", "📰" },
	{ "แอดมินเพจรถติด", "Traffic Jam Admin", "🚦" },
	{ "น้องมายด์ ปี 2", "Mind, 2nd year", "👩‍🎓" },
	{ "ลุงชัย วินหน้าตลาด", "Uncle Chai, market taxi stand", "🧔" },
	{ "สายกิน ขอนแก่น", "Khon Kaen Foodies", "🍜" },
	{ "คุณนายเมาท์มอย", "Madam Gossip", "💅" },
	{ "หนุ่มออฟฟิศเงินเดือนหมด", "Office Guy, Broke By The 15th", "👨‍💼" },
	{ "เจ๊ปุ้ย ขายของออนไลน์", "Sister Pui Sells Online", "🛍" },
	{ "พี่หมี ช่างซ่อมรถ", "Bear the Mechanic", "🔧" },
	{ "กลุ่ม คนรักหมาซอย", "Soi Dog Lovers Group", "🐕" },
	{ "ไรเดอร์สายฮา", "Funny Rider Club", "🛵" },
}

Feed.posts = {
	crash = {
		t("เมื่อกี้เห็นไรเดอร์ {name} บินข้ามแฮนด์แถว{place} ลุกขึ้นมาปัดฝุ่นแล้วไปต่อ อดทนมากกก", "Just saw rider {name} fly over the handlebars near {place}, dust off and carry on. Respect."),
		t("ใครทำหมวกกันน็อกหล่นแถว{place} ไรเดอร์ {name} ฝากบอกว่าไม่ใช่ของเขา (แต่ของเขาจริงๆ)", "Someone dropped a helmet near {place}. Rider {name} says it isn't theirs. (It is.)"),
		t("คลิปไวรัลวันนี้: {name} vs กำแพง ผลคือกำแพงชนะ 1-0", "Today's viral clip: {name} vs a wall. Wall wins 1-0."),
	},
	fine_checkpoint = {
		t("ด่านแถว{place} วันนี้ขยันมาก ไรเดอร์ {name} โดนไป {amount} บาท 😅", "The checkpoint near {place} is busy today. Rider {name} paid {amount} baht 😅"),
		t("แจ้งข่าว: ด่านตั้งอยู่แถว{place} ใครจะผ่านเลี่ยงไปทางอื่นนะ (ไม่ได้บอกให้หนี แค่บอกเฉยๆ)", "FYI: checkpoint near {place}. Take another road. (Not telling you to dodge it. Just saying.)"),
		t("{name}: ผมแค่ขับผ่าน... ตำรวจ: ใบขับขี่ด้วยครับ", "{name}: I was just passing... Officer: Licence, please."),
	},
	fine_redlight = {
		t("ไฟแดงแถว{place} มีคนฝ่าอีกแล้ว ไรเดอร์ {name} จ่ายไป {amount} บาท เลี้ยวซ้ายผ่านตลอดนะ ตรงไปไม่ได้!", "Someone ran the red near {place} again. {name} paid {amount}. Left on red is fine, straight on is not!"),
		t("ป้ายบอกซ้ายผ่านตลอด {name} ดันไปตรง... ใบสั่งมาเลยจ้า", "The sign says left on red. {name} went straight... here comes the ticket."),
	},
	-- server/TrafficService: not stopping for people on a zebra crossing (2026-11-18)
	fine_zebra = {
		t("ทางม้าลายหน้า{place} มีคนข้ามอยู่ ไรเดอร์ {name} ไม่ยอมหยุด โดนไป {amount} บาท ทางม้าลายมีไว้ให้หยุดนะจ๊ะ 🚸", "People were on the crossing near {place} and rider {name} didn't stop. {amount} baht. Zebras are for stopping 🚸"),
		t("น้องนักเรียนรอข้ามถนนแถว{place} อยู่ตั้งนาน ขอบคุณทุกคันที่หยุดให้ ยกเว้น {name} 😤", "The kids waited ages to cross near {place}. Thanks to everyone who stopped. Except {name} 😤"),
	},
	-- server/FinanceService KK Bank (2026-11-18)
	bank_loan = {
		t("ไรเดอร์ {name} กู้ธนาคารมาลงทุน หวังว่าจะไม่ใช่เอาไปแต่งรถอย่างเดียวนะ 🏦", "Rider {name} took out a bank loan to invest. Hopefully not all on neon underglow 🏦"),
	},
	bank_late = {
		t("ธนาคารโทรตามไรเดอร์ {name} ทั้งวัน ค้างผ่อนแล้วจ้า วิ่งงานใช้หนี้กันไป 📞", "The bank has been calling rider {name} all day. Behind on payments: time to ride and repay 📞"),
	},
	-- client/SpeedBumps (2026-11-18): over a speed bump far too fast
	speedbump = {
		t("ไรเดอร์ {name} ซิ่งข้ามลูกระนาดแถว{place} ลอยไปสามวิ ลงมาไม่สวย 😵 ลูกระนาดชนะอีกแล้ว", "Rider {name} hit the speed bump near {place} flat out, flew for three seconds, landed badly 😵 The bump wins again."),
		t("ป้าหน้าปากซอยแถว{place} บอกว่าเห็น {name} บินข้ามลูกระนาดเหมือนหนังแอ็กชัน แต่ตอนจบไม่เหมือน", "The auntie at the soi corner near {place} says {name} flew over the bump like an action movie. The ending was not."),
	},
	-- client/Accident (2026-11-18): you ran into someone or another vehicle and paid for it
	accident_ped = {
		t("ไรเดอร์ {name} ชนคนเดินถนนแถว{place} จ่ายค่ารักษาไป {amount} บาท ทางม้าลายมีไว้ให้คนข้ามนะ 🚶", "Rider {name} hit a pedestrian near {place} and paid {amount} baht for the hospital. Zebra crossings are for people 🚶"),
		t("ป้าข้างบ้านโพสต์: เดินไปตลาดแถว{place} ดีๆ โดน {name} เฉี่ยว ได้ค่ายามา {amount} บาท ขับช้าๆ หน่อยลูก", "Auntie posts: walking to the market near {place}, {name} clipped me. Got {amount} baht for medicine. Slow down, dear."),
	},
	accident_car = {
		t("รถชนกันแถว{place} ไรเดอร์ {name} จ่ายค่าซ่อมคู่กรณีไป {amount} บาท เว้นระยะห่างกันหน่อยนะ 🚗💥", "Fender bender near {place}. Rider {name} paid {amount} baht for the other car. Keep your distance 🚗💥"),
		t("{name} ชนท้ายเขาแถว{place} คู่กรณีลงมาพร้อมมือถือถ่ายรูปครบทุกมุม จบที่ {amount} บาท", "{name} rear-ended someone near {place}. They got out with a phone, photographed every angle. Settled at {amount} baht."),
	},
	nolicence = {
		t("ไรเดอร์ {name} โดนด่านเรียก ไม่มีใบขับขี่! ไปสอบที่ขนส่งก่อนนะ คิวยาวหน่อย 555", "{name} got stopped with no licence! Go take the test first. The queue is... long."),
	},
	review_good = {
		t("ไรเดอร์ {name} ส่งไวมาก ข้าวยังร้อนอยู่เลย ⭐⭐⭐⭐⭐ ใจดีด้วย", "Rider {name} was so fast the rice was still hot ⭐⭐⭐⭐⭐"),
		t("รีวิวจากคุณ{who}: ไรเดอร์ยิ้มเก่ง ขี่นุ่ม เดี๋ยวสั่งอีก", "Review from {who}: rider smiles a lot, rides smooth. Ordering again."),
	},
	review_bad = {
		t("รีวิวจากคุณ{who}: ฝนตกแล้วมาช้า ให้ 1 ดาว (ฝนผมเป็นคนสั่งเองไหมเนี่ย)", "Review from {who}: it rained so you were late, 1 star. (Did I order the rain too?)"),
		t("คุณ{who}: สั่งไม่เผ็ด... ทำไมจืดจัง 1 ดาวค่ะ", "{who}: I ordered not spicy... why is it so bland? 1 star."),
	},
	thanks_tip = {
		t("วันนี้ได้ทิปเป็นคำว่า 'ขอบคุณค่ะ 🙏' อีกแล้ว ไรเดอร์ {name} ยิ้มรับ (ในใจร้องไห้)", "Today's tip: 'thank you 🙏' again. {name} smiles (crying inside)."),
	},
	twist_wrongpin = {
		t("ลูกค้าปักหมุดไว้ร้านยาง แต่บ้านอยู่อีกซอยนึง ไรเดอร์ {name} วนไป 3 รอบ 🌀", "The pin said tyre shop, the house was a soi away. {name} circled three times 🌀"),
	},
	twist_late = {
		t("'รอแป๊บนะคะ ลงไปแล้ว' แป๊บของคุณ{who} = 15 นาที ไรเดอร์ {name} แก่ไปอีกปี", "'Coming down now!' {who}'s 'now' = 15 minutes. {name} aged a year."),
	},
	twist_addon = {
		t("ลูกค้าสั่งข้าว แล้วขอแวะซื้อน้ำแข็ง แล้วขอทิชชู่ แล้วขอ... ไรเดอร์ {name} ใจดีเกิน", "Ordered rice, then ice, then tissues, then... rider {name} is too kind."),
	},
	twist_influencer = {
		t("ผู้โดยสารขอแวะถ่ายรูปร้านกาแฟเปิดใหม่ 48 รูป ไรเดอร์ {name} ได้เป็นช่างภาพจำเป็น 📸", "The passenger stopped for 48 photos at a new café. {name} became a photographer 📸"),
	},
	dog_chase = {
		t("หมาซอยแถว{place} ไล่ไรเดอร์ {name} อีกแล้ว ใครให้ข้าวมันประจำช่วยบอกมันหน่อย 🐕💨", "The soi dog near {place} chased {name} again. Whoever feeds it, please have a word 🐕💨"),
	},
	dog_bite = {
		t("ไรเดอร์ {name} โดนหมาซอยงับขากางเกง หมาไม่ผิด ไรเดอร์ขี่ช้าไปเอง (คอมเมนต์จากกลุ่มคนรักหมา)", "{name} got their trousers bitten. The dog did nothing wrong. (Soi Dog Lovers Group)"),
	},
	flood = {
		t("ฝนตกครึ่งชั่วโมง ถนนแถว{place} กลายเป็นคลอง ใครมีเรือให้ยืมบ้าง 🚣", "Half an hour of rain and the road near {place} became a canal. Anyone got a boat? 🚣"),
		t("มอไซค์ {name} เครื่องดับกลางน้ำแถว{place} เข็นกันไป สู้ๆ", "{name}'s bike died in the flood near {place}. Push on, champ."),
	},
	pothole = {
		t("หลุมแถว{place} ลึกจนปลาเริ่มอยู่ได้แล้ว ซ่อมหน่อยค่ะ 🕳", "The pothole near {place} is deep enough for fish now. Fix it, please 🕳"),
	},
	roadworks = {
		t("ป้าย 'ขออภัยในความไม่สะดวก' ตรง{place} อยู่มาตั้งแต่น้องผมยังเรียนอนุบาล ตอนนี้น้องจบปริญญาแล้ว", "The 'sorry for the inconvenience' sign at {place} went up when my brother was in kindergarten. He just graduated."),
	},
	uturn = {
		t("ยูเทิร์นอีก 3 กิโล... ไรเดอร์ {name} เลยกลับรถตรงนี้เลย (ไม่แนะนำนะ)", "Next U-turn: 3 km... so {name} just turned here. (Don't.)"),
	},
	livestream = {
		t("มีคนไลฟ์สดยืนกลางถนนแถว{place} 'สวัสดีค่ะทุกคน กดไลก์กดแชร์ด้วยนะคะ' 🤳", "Someone's live-streaming in the middle of the road near {place}. 'Hi everyone, like and share!' 🤳"),
	},
	wrongway = {
		t("ย้อนศรอีกแล้ว! แถว{place} มีมอไซค์สวนมาชิดขอบ ใครเห็นช่วยเตือนกันหน่อย", "Wrong-way rider again near {place}, hugging the kerb. Please warn each other."),
	},
	sidewalk = {
		t("เทศกิจแถว{place} จับคนขี่บนทางเท้าได้อีกราย ไรเดอร์ {name} 🙏 ทางเท้ามีไว้เดินนะ", "Municipal officers near {place} caught another sidewalk rider: {name} 🙏 Pavements are for feet."),
	},
	auntie = {
		t("ป้าข้างบ้านไรเดอร์ {name}: 'เมื่อไหร่จะแต่งงาน' ไรเดอร์: '...' ป้า: 'แล้วเงินเดือนเท่าไหร่'", "{name}'s neighbour: 'When are you getting married?' {name}: '...' Neighbour: 'And your salary?'"),
		t("อัปเดตจากป้าข้างบ้าน: ไรเดอร์ {name} ซื้อรถใหม่ (ป้าเดาว่าผ่อน)", "Update from the neighbour: {name} has a new bike. (She guesses it's on instalments.)"),
	},
	win_join = {
		t("วินหน้าตลาดรับสมาชิกใหม่ ไรเดอร์ {name} ผ่านการทดสอบ 'เอากาแฟเย็นมาให้พี่วิน' เรียบร้อย ☕", "The market taxi stand has a new member: {name} passed the 'bring the boss an iced coffee' test ☕"),
	},
	win_warn = {
		t("พี่วินหน้า{place} มองค้อนไรเดอร์ {name} ที่มารับลูกค้าในถิ่น 👀 ถิ่นใครถิ่นมันนะน้อง", "The taxi stand boss at {place} gave {name} the eye for picking up on his turf 👀"),
	},
	loan_buy = {
		t("ไรเดอร์ {name} ออกรถใหม่ ดาวน์ 0% ผ่อนสบายๆ (ตัวหนังสือท้ายสัญญาเล็กมากจนต้องใช้แว่นขยาย)", "{name} drove off with a new ride. 0% down! (The fine print needs a magnifying glass.)"),
	},
	loan_late = {
		t("ไฟแนนซ์โทรหาไรเดอร์ {name} 7 รอบตั้งแต่เช้า 'สะดวกคุยไหมคะ' 📞", "The finance company called {name} seven times since morning. 'Is now a good time?' 📞"),
	},
	loan_repo = {
		t("แก๊งยึดรถตามไรเดอร์ {name} ทั้งเมือง สุดท้ายรถโดนลากไป 🚚 ผ่อนให้ตรงงวดนะทุกคน", "The repo crew chased {name} across town and towed the bike away 🚚 Pay on time, folks."),
	},
	loan_escape = {
		t("รถยึดรถไล่ไรเดอร์ {name} ไม่ทัน! (แต่งวดยังค้างอยู่นะ)", "The repo truck couldn't catch {name}! (The instalment is still overdue though.)"),
	},
	loan_paid = {
		t("ไรเดอร์ {name} ผ่อนรถหมดแล้ว! ปลดหนี้ไป 1 ก้อน (เหลืออีก 12 ก้อน)", "{name} paid off the bike! One debt down. (Twelve to go.)"),
	},
	molam = {
		t("รถแห่หมอลำผ่านซอยแถว{place} เบสแรงจนกระจกบ้านสั่น ป้าออกมาเต้นเฉยเลย 🔊💃", "A party truck rolled through near {place}. The bass shook the windows and Auntie came out dancing 🔊💃"),
	},
	songkran = {
		t("สงกรานต์มาแล้ว! ถนนสายหลักมีคนสาดน้ำเพียบ ไรเดอร์ขี่ช้าๆ ค่ารอบพิเศษนะ 💦", "Songkran is here! Water fights on the main roads. Ride slowly, extra fares today 💦"),
		t("ไรเดอร์ {name} โดนสาดน้ำจนเปียกทั้งตัว แต่ยังยิ้มได้ (ข้าวในกล่องรอดไหม)", "{name} got soaked from head to toe but kept smiling. (Did the food survive?)"),
	},
	licence_pass = {
		t("ไรเดอร์ {name} สอบใบขับขี่ผ่านแล้ว! ใช้เวลารอคิว 3 ชั่วโมง สอบ 2 นาที 🎉", "{name} passed the driving test! Three hours in the queue, two minutes of test 🎉"),
	},
	licence_fail = {
		t("{name} สอบทางแคบตก ล้อแตะพื้นนิดเดียว... เจ้าหน้าที่: 'กลับไปซ้อมแล้วมาใหม่นะน้อง'", "{name} fell off the narrow plank. Examiner: 'Go practise and come back, kid.'"),
	},
	levelup = {
		t("ยินดีด้วยกับไรเดอร์ {name} ขึ้นเลเวลใหม่! เลี้ยงหมูกระทะด้วยนะ", "Congrats to rider {name} on the new level! Moo kratha is on you."),
	},
	-- town life with no player in it, every couple of minutes
	ambient = {
		t("ร้อนมากกก ออกจากบ้านไปปากซอย เหมือนเดินเข้าเตาอบ 🥵", "So hot. Walking to the end of the soi feels like entering an oven 🥵"),
		t("วันนี้เงินเดือนออก พรุ่งนี้เงินเดือนหมด 💸", "Payday today. Broke tomorrow 💸"),
		t("ใครรู้บ้างว่าร้านส้มตำที่คนต่อคิวยาวๆ แถว{place} มันอร่อยจริงหรือแค่คนต่อคิว", "Is the somtam place near {place} actually good, or is everyone just queueing because everyone is queueing?"),
		t("แมวส้มแถว{place} นอนบนเบาะมอไซค์ใครไม่รู้ เจ้าของยืนรอให้ตื่นมา 20 นาทีแล้ว 🐈", "An orange cat is asleep on someone's bike seat near {place}. The owner has waited 20 minutes for it to wake up 🐈"),
		t("สายไฟหน้าบ้านพันกันจนน่าจะต่อเน็ตได้ทั้งซอยแล้ว", "The cables outside are so tangled the whole soi could share wifi."),
		t("ไปร้านสะดวกซื้อตอนตีสอง เจอคนรู้จักครึ่งซอย", "Went to the convenience store at 2am. Met half the soi."),
		t("ป้ายหาเสียงเบอร์ 99 'ถนนดีทุกซอย ภายในชาตินี้' เออ ก็ยังไม่ได้บอกว่าชาติไหน", "Poster for candidate no. 99: 'Good roads in every soi, within this lifetime.' Didn't say whose lifetime."),
		t("ฝนตกนิดเดียว รถติดทั้งเมือง ทำไมเป็นงี้ 🌧🚗🚗🚗", "A little rain and the whole city stops. Why 🌧🚗🚗🚗"),
		t("แม่ค้าข้าวเหนียวหมูปิ้ง: 'วันนี้หมดเร็ว ไรเดอร์มารับไป 30 ไม้'", "Grilled pork seller: 'Sold out early, a rider took 30 sticks.'"),
		t("ชาวเน็ตถาม: ขอนแก่นมีอะไรเที่ยว / แอดมิน: มีรถติดค่ะ", "Netizen: what is there to do in Khon Kaen? / Admin: traffic jams."),
	},
}

Feed.comments = {
	t("55555555", "lmaooo"), t("ทัวร์ลง", "the tour bus has arrived"), t("แท็กเพื่อนที่เป็นแบบนี้", "tag a friend like this"),
	t("ขอให้ปลอดภัยนะ 🙏", "stay safe 🙏"), t("จริงที่สุด", "so true"), t("ไรเดอร์สู้ๆ ✌️", "go riders ✌️"),
	t("โดนเหมือนกันเมื่อวาน 😭", "same thing happened to me yesterday 😭"), t("ได้ข่าวว่า...", "heard that..."),
	t("ใครอยู่แถวนั้นบ้าง", "anyone near there?"), t("แชร์ให้ชาวบ้านรู้", "sharing for awareness"), t("ขำแต่เศร้า", "funny but sad"),
	t("มีคลิปไหม", "is there a clip?"), t("จองที่ไว้ก่อน", "saving my spot"), t("อ่านแล้วนึกถึงตัวเอง", "this is me"),
}

return Feed
