-- Thai / English. The game's UI and the server's messages are written in English; in Thai mode
-- every TextLabel / TextButton under the player's GUI is translated as its text is set, so no
-- screen needs its own translation code. Exact strings come first, then patterns for text built
-- from parts ("Deliver to <place>"), then units (m, km, s). Anything not in the tables stays
-- English, which is always readable as a fallback.
--   Lang.t(s)        translate one string (identity in English mode)
--   Lang.set(code)   "th" | "en"; re-translates everything on screen
--   Lang.watch(root) translate every text object under root, now and as they appear
local Lang = {}
Lang.code = "th"

local listeners = {} :: { () -> () }
function Lang.onChange(fn: () -> ()) table.insert(listeners, fn) end

---------------------------------------------------------------------------------------------------
-- nouns: used on their own and inside patterns
---------------------------------------------------------------------------------------------------
local N = {
	-- food & items
	["Boat Noodles"] = "ก๋วยเตี๋ยวเรือ", ["Chicken Rice"] = "ข้าวมันไก่", ["Chili Fried Rice"] = "ข้าวผัดพริก", ["Chili Seeds"] = "เมล็ดพริก", ["Chili"] = "พริก",
	["Compost"] = "ปุ๋ยหมัก", ["Corn Seeds"] = "เมล็ดข้าวโพด", ["Corn"] = "ข้าวโพด", ["Energy Drink"] = "เครื่องดื่มชูกำลัง", ["Fertilizer"] = "ปุ๋ย",
	["Garden Salad"] = "สลัดผัก", ["Grilled Corn"] = "ข้าวโพดปิ้ง", ["Homemade Som Tam"] = "ส้มตำทำเอง", ["Iced Coffee"] = "กาแฟเย็น", ["Jasmine Rice"] = "ข้าวหอมมะลิ",
	["Kai Yang"] = "ไก่ย่าง", ["Lettuce Seeds"] = "เมล็ดผักกาด", ["Lettuce"] = "ผักกาด", ["Mango Sticky Rice"] = "ข้าวเหนียวมะม่วง", ["Moo Ping & Sticky Rice"] = "หมูปิ้งข้าวเหนียว",
	["Pad Krapao Rice"] = "ข้าวกะเพรา", ["Rice Seedlings"] = "ต้นกล้าข้าว", ["Som Tam"] = "ส้มตำ", ["Thai Milk Tea"] = "ชาไทย", ["Tomato Seeds"] = "เมล็ดมะเขือเทศ",
	["Tomato"] = "มะเขือเทศ", ["Water"] = "น้ำเปล่า", ["Watermelon Seeds"] = "เมล็ดแตงโม", ["Watermelon Slices"] = "แตงโมหั่น", ["Watermelon"] = "แตงโม", ["Rice"] = "ข้าว",
	["Food order"] = "ออร์เดอร์อาหาร", ["Spicy Mood"] = "อารมณ์แซ่บ", ["Sugar Rush"] = "น้ำตาลพุ่ง",
	-- furniture
	["Armchair"] = "อาร์มแชร์", ["Bookshelf"] = "ชั้นหนังสือ", ["Coffee Table"] = "โต๊ะกาแฟ", ["Computer Desk"] = "โต๊ะคอมพิวเตอร์", ["Counter & Sink"] = "เคาน์เตอร์และซิงก์",
	["Dining Chair"] = "เก้าอี้กินข้าว", ["Dining Table"] = "โต๊ะกินข้าว", ["Double Bed"] = "เตียงคู่", ["Floor Lamp"] = "โคมไฟตั้งพื้น", ["Flower Bed"] = "แปลงดอกไม้",
	["Framed Art"] = "ภาพแขวนผนัง", ["Garage Pad"] = "ลานจอดรถ", ["Garden Bench"] = "ม้านั่งในสวน", ["Garden Lamp"] = "โคมไฟสวน", ["Kitchen Stove"] = "เตาครัว",
	["Nightstand & Lamp"] = "โต๊ะข้างเตียงและโคมไฟ", ["Palm Tree"] = "ต้นปาล์ม", ["Potted Plant"] = "ต้นไม้กระถาง", ["Refrigerator"] = "ตู้เย็น", ["Shower"] = "ฝักบัว",
	["Single Bed"] = "เตียงเดี่ยว", ["Sink & Mirror"] = "อ่างล้างหน้าและกระจก", ["Sofa"] = "โซฟา", ["Spirit House"] = "ศาลพระภูมิ", ["Standing Fan"] = "พัดลมตั้งพื้น",
	["TV & Stand"] = "ทีวีและชั้นวาง", ["Tire Rack"] = "ชั้นวางยาง", ["Toilet"] = "ชักโครก", ["Tool Bench"] = "โต๊ะช่าง", ["Wardrobe"] = "ตู้เสื้อผ้า",
	["Washing Machine"] = "เครื่องซักผ้า", ["Wooden Fence"] = "รั้วไม้", ["Woven Rug"] = "พรมทอ",
	["Third-person view"] = "มุมมองบุคคลที่สาม", ["First-person view (V to switch back)"] = "มุมมองคนขี่ (กด V เพื่อสลับกลับ)",
	-- land
	["Small Plot"] = "ที่ดินแปลงเล็ก", ["Medium Plot"] = "ที่ดินแปลงกลาง", ["Large Plot"] = "ที่ดินแปลงใหญ่", ["Premium Plot"] = "ที่ดินพรีเมียม", ["Riverside Plot"] = "ที่ดินริมน้ำ",
	-- vehicles and upgrades
	["Old Bicycle"] = "จักรยานเก่า", ["Engine"] = "เครื่องยนต์", ["Tires"] = "ยาง", ["Brakes"] = "เบรก", ["Handling"] = "การบังคับ", ["Suspension"] = "ช่วงล่าง",
	["Fuel Efficiency"] = "ประหยัดน้ำมัน",
	-- job types
	["Neighbourhood Delivery"] = "ส่งอาหารใกล้ๆ", ["Normal Delivery"] = "ส่งอาหารทั่วไป", ["Express Delivery"] = "ส่งด่วน", ["Large Order"] = "ออร์เดอร์ใหญ่",
	["Special Food Delivery"] = "ส่งอาหารพิเศษ", ["VIP Delivery"] = "ส่งอาหาร VIP", ["Rainy Day Delivery"] = "ส่งอาหารวันฝนตก", ["GoDash Ride"] = "รับส่งผู้โดยสาร",
	["Rush Hour Ride"] = "รับส่งช่วงเร่งด่วน", ["Group Ride"] = "รับส่งเป็นกลุ่ม", ["VIP Ride"] = "รับส่ง VIP",
	-- landmark jobs (server/CivicJobs, 2026-11-18)
	["Urgent Documents"] = "ส่งเอกสารด่วน", ["Hospital Lunch Boxes"] = "ข้าวกล่องส่งโรงพยาบาล", ["School Lunch Run"] = "ส่งข้าวเที่ยงโรงเรียน",
	["Match Day Snacks"] = "เสบียงวันแข่งบอล", ["Late-night Study Snacks"] = "ของกินอ่านหนังสือดึก", ["Student to the Bus Terminal"] = "ส่งนักศึกษาไป บขส.",
	["Hospital Appointment"] = "พาไปหาหมอตามนัด", ["Catch the Train"] = "ส่งขึ้นรถไฟให้ทัน", ["Museum Visit"] = "พาเที่ยวพิพิธภัณฑ์",
	["Urgent documents"] = "เอกสารด่วน", ["Lunch boxes for the ward staff"] = "ข้าวกล่องให้พยาบาลประจำวอร์ด", ["Teachers' lunch order"] = "ข้าวเที่ยงคุณครู",
	["Ice and drinks for the stands"] = "น้ำแข็งกับน้ำดื่มขึ้นอัฒจันทร์", ["Snacks for exam night"] = "ขนมคืนก่อนสอบ", ["1 passenger"] = "ผู้โดยสาร 1 คน",
	["Officer Somsak"] = "เจ้าหน้าที่สมศักดิ์", ["Officer Wanpen"] = "เจ้าหน้าที่วันเพ็ญ", ["Officer Prasit"] = "เจ้าหน้าที่ประสิทธิ์",
	["Nurse Ploy"] = "พยาบาลพลอย", ["Nurse Kik"] = "พยาบาลกิ๊ก", ["Dr. Anan"] = "คุณหมออนันต์", ["Teacher Noi"] = "ครูน้อย", ["Teacher Pong"] = "ครูป๋อง",
	["Teacher Jiap"] = "ครูเจี๊ยบ", ["Coach Bird"] = "โค้ชเบิร์ด", ["Fan club Kaen"] = "แฟนคลับทีมแก่น", ["Nong Mook"] = "น้องมุก", ["Nong Pete"] = "น้องพีท",
	["Nong Fern"] = "น้องเฟิร์น", ["Grandma Boon"] = "ยายบุญ", ["Grandpa Sin"] = "ตาสิน", ["Pick-up point"] = "จุดรับ",
	-- places and people
	["Home"] = "บ้าน", ["Dormitory"] = "หอพัก", ["Shop house"] = "ตึกแถว", ["My Home"] = "บ้านของฉัน", ["My Allotment"] = "แปลงผักของฉัน", ["Waypoint"] = "จุดหมาย",
	["KK Motors"] = "KK Motors", ["Fuel Station"] = "ปั๊มน้ำมัน", ["Community Farm"] = "ฟาร์มชุมชน",
	["Khun Somchai"] = "คุณสมชาย", ["Khun Malee"] = "คุณมาลี", ["Khun Nok"] = "คุณนก", ["Khun Lek"] = "คุณเล็ก", ["Khun Ploy"] = "คุณพลอย", ["Khun Art"] = "คุณอาร์ต",
	["Khun Fah"] = "คุณฟ้า", ["Khun Boom"] = "คุณบูม", ["Khun Mint"] = "คุณมิ้นท์", ["Khun Tee"] = "คุณตี๋", ["Khun Aom"] = "คุณออม", ["Khun Bank"] = "คุณแบงค์",
	-- missions
	["Busy Day"] = "วันยุ่ง", ["Daily Commute"] = "เดินทางประจำวัน", ["First Order"] = "ออร์เดอร์แรก", ["Five Star Driver"] = "ไรเดอร์ห้าดาว", ["Fresh Produce"] = "ผลผลิตสด",
	["Getting Started"] = "เริ่มต้น", ["Green Thumb"] = "มือเย็น", ["Harvest Day"] = "วันเก็บเกี่ยว", ["Home Chef"] = "เชฟที่บ้าน", ["Home Owner"] = "เจ้าของบ้าน",
	["Interior Designer"] = "นักแต่งบ้าน", ["Isan Explorer"] = "นักสำรวจอีสาน", ["Lunch Rush"] = "ช่วงเที่ยงยุ่ง", ["Market Seller"] = "พ่อค้าตลาด", ["New Wheels"] = "รถใหม่",
	["Payday"] = "วันเงินออก", ["Pick Me Up"] = "มารับหน่อย", ["Pro Rider"] = "ไรเดอร์มือโปร", ["Road Warrior"] = "นักบู๊บนถนน", ["Stay Fed"] = "กินให้อิ่ม",
	["Taxi Time"] = "ได้เวลาแท็กซี่", ["Top Service"] = "บริการเยี่ยม", ["Tuner"] = "สายแต่ง", ["Water the Farm"] = "รดน้ำฟาร์ม",
}

---------------------------------------------------------------------------------------------------
-- exact strings
---------------------------------------------------------------------------------------------------
local E = {
	-- HUD
	["Energy"] = "พลังงาน", ["Fatigue"] = "ความเหนื่อยล้า", ["Food"] = "ความอิ่ม", ["Happy"] = "ความสุข", ["🥤 Energy saver"] = "🥤 ประหยัดพลังงาน", ["🌶 Tips +12%"] = "🌶 ทิป +12%",
	["LV"] = "เลเวล",["km/h"] = "กม./ชม.", ["ONLINE"] = "รับงานอยู่", ["OFFLINE"] = "ปิดรับงาน", ["Morning"] = "เช้า", ["Afternoon"] = "บ่าย", ["Evening"] = "เย็น",
	["Night"] = "กลางคืน", ["Midday"] = "เที่ยง", ["Dawn"] = "รุ่งเช้า", ["Dusk"] = "พลบค่ำ",
	["ACCEPT"] = "รับงาน", ["ACCEPT  [Y]"] = "รับงาน  [Y]", ["Decline"] = "ข้าม", ["X"] = "X", ["Skip"] = "ข้าม",
	["Pick up order"] = "รับอาหาร", ["Deliver order"] = "ส่งอาหาร", ["Pick up passenger"] = "รับผู้โดยสาร", ["Drop off passenger"] = "ส่งผู้โดยสาร",
	["Pick up order  [G]"] = "รับอาหาร  [G]", ["Deliver order  [G]"] = "ส่งอาหาร  [G]", ["Pick up passenger  [G]"] = "รับผู้โดยสาร  [G]", ["Drop off passenger  [G]"] = "ส่งผู้โดยสาร  [G]",
	["Pick up order  [E]"] = "รับอาหาร  [E]", ["Deliver order  [E]"] = "ส่งอาหาร  [E]", ["Pick up passenger  [E]"] = "รับผู้โดยสาร  [E]", ["Drop off passenger  [E]"] = "ส่งผู้โดยสาร  [E]",
	["Tap X again to cancel this job (lowers your rating)"] = "กด X อีกครั้งเพื่อยกเลิกงาน (เรตติ้งจะลดลง)",
	["GAS"] = "เร่ง", ["BRAKE"] = "เบรก", ["EXIT"] = "ลงรถ", ["TAP"] = "แตะ", ["Interact"] = "ใช้งาน",
	-- prompts (server)
	["Drive"] = "ขับ", ["Ride"] = "ขี่", ["Talk"] = "คุย", ["Plant"] = "ปลูก", ["Harvest"] = "เก็บเกี่ยว", ["Water"] = "รดน้ำ", ["Till soil"] = "พรวนดิน", ["Tend"] = "ดูแล",
	["Visit"] = "เยี่ยมชม", ["View plot"] = "ดูที่ดิน", ["Browse vehicles"] = "ดูรถ", ["Refuel / Repair"] = "เติมน้ำมัน / ซ่อม", ["Take the bus (฿30)"] = "ขึ้นรถเมล์ (฿30)",
	["Ask about farming"] = "ถามเรื่องปลูกผัก", ["Shop"] = "ซื้อของ", ["Buy"] = "ซื้อ", ["Eat"] = "กิน", ["Rest"] = "พัก", ["Sleep"] = "นอน", ["Cook"] = "ทำอาหาร",
	["Open fridge"] = "เปิดตู้เย็น", ["Take a shower"] = "อาบน้ำ", ["Watch TV"] = "ดูทีวี", ["Use computer"] = "ใช้คอมพิวเตอร์", ["Sell crops"] = "ขายผลผลิต",
	["Bench (free energy)"] = "ม้านั่ง (พักฟรี)", ["Sala (free energy)"] = "ศาลา (พักฟรี)", ["Shop / Sell"] = "ซื้อ / ขาย", ["Unlock"] = "ปลดล็อก",
	["Bring vehicle here"] = "เรียกรถมาที่นี่", ["Home workshop"] = "โต๊ะช่างที่บ้าน", ["Repair · Refuel · Upgrades"] = "ซ่อม · เติมน้ำมัน · อัปเกรด",
	["Get treatment (฿150)"] = "รักษาตัว (฿150)", ["Get treated (gold card ฿30+)"] = "รักษาแผล (บัตรทอง ฿30+)", ["Pay respects"] = "สักการะ", ["Safe driver bonus"] = "โบนัสขับขี่ปลอดภัย", ["Local"] = "คนในพื้นที่",
	["Khon Kaen Hospital"] = "โรงพยาบาลขอนแก่น", ["Kaen Nakhon Stupa"] = "พระธาตุแก่นนคร", ["Police Station"] = "สถานีตำรวจ",
	-- phone shell + home
	["GoDash Phone"] = "มือถือ GoDash", ["⌂  Home"] = "⌂  หน้าแรก", ["Loading…"] = "กำลังโหลด…", ["This screen had a problem."] = "หน้านี้มีปัญหา",
	["GoDash"] = "GoDash", ["Maps"] = "แผนที่", ["Garage"] = "โรงรถ", ["Property"] = "บ้าน/ที่ดิน", ["Farming"] = "ปลูกผัก", ["Bag"] = "กระเป๋า", ["Bank"] = "ธนาคาร",
	["Profile"] = "โปรไฟล์", ["Missions"] = "ภารกิจ", ["Radio"] = "วิทยุ", ["Settings"] = "ตั้งค่า",
	["Test session: progress is kept in memory only."] = "โหมดทดสอบ: ความคืบหน้าไม่ถูกบันทึก",
	-- GoDash app
	["You're ONLINE"] = "คุณกำลังรับงาน", ["You're offline"] = "คุณปิดรับงานอยู่", ["On a job — follow the GPS"] = "กำลังทำงาน — ขี่ตามเส้นสีเขียว",
	["New job offer!"] = "มีออร์เดอร์ใหม่!", ["Looking for jobs near you…"] = "กำลังหางานใกล้คุณ…", ["Go online to receive orders"] = "กดเริ่มรับงานเพื่อรับออร์เดอร์",
	["Go Offline"] = "ปิดรับงาน", ["GO ONLINE"] = "▶ เริ่มรับงาน", ["JOB TYPE"] = "ประเภทงาน", ["🍱 Food"] = "🍱 ส่งอาหาร", ["🧍 Rides"] = "🧍 รับส่งคน", ["Both"] = "ทั้งสองแบบ",
	["CURRENT JOB"] = "งานตอนนี้", ["TODAY"] = "วันนี้", ["Income"] = "รายได้", ["Jobs"] = "งาน", ["Rating"] = "เรตติ้ง", ["JOBS YOU CAN GET"] = "งานที่รับได้",
	-- maps
	["🤖 Auto drive · Q"] = "🤖 ขับอัตโนมัติ · Q", ["🤖 AUTO ON · Q"] = "🤖 ขับอัตโนมัติอยู่ · Q", ["⬅️ Left turn on red is allowed"] = "⬅️ ซ้ายผ่านตลอด ไม่โดนปรับ",
	["Auto drive (follows the GPS route)"] = "ขับอัตโนมัติ (ตามเส้นทาง GPS)",
	["Police checkpoint"] = "ด่านตรวจ",
	-- Loy Krathong (2026-11-18)
	["Float a krathong"] = "ลอยกระทง", ["Loy Krathong"] = "ลอยกระทง บึงแก่นนคร",
	["No festival now"] = "ตอนนี้ไม่มีงานเทศกาล", ["Go to the end of the pier at Bueng Kaen Nakhon"] = "ไปที่ปลายท่าน้ำบึงแก่นนครก่อน",
	["Wait a moment before the next one"] = "รอสักครู่ค่อยลอยอันต่อไป", ["Pick a wish"] = "เลือกคำอธิษฐานก่อน",
	["City Feed"] = "ฟีดเมือง", ["Finance"] = "ไฟแนนซ์", ["💦 Songkran +30%"] = "💦 สงกรานต์ +30%",
	["Top Riders"] = "อันดับไรเดอร์", ["Reviews"] = "รีวิว", ["Invite"] = "ชวนเพื่อน", ["Clip"] = "ถ่ายคลิป", ["Insurance"] = "ประกันภัย", ["Starter gift!"] = "ของขวัญไรเดอร์ใหม่!", ["฿1,500 toward your first motorbike · KK Motors"] = "฿1,500 ไว้ซื้อมอไซคันแรก · ไปที่ KK Motors", ["Pedal a swan boat"] = "ปั่นเรือเป็ด", ["Swan boat"] = "เรือเป็ด", ["Photo"] = "ถ่ายรูป", ["Styling"] = "แต่งซิ่ง", ["Photo mode"] = "โหมดถ่ายรูป", ["Ride along"] = "ขึ้นรถด้วย",
	["A friend is in the passenger seat"] = "มีเพื่อนนั่งที่ผู้โดยสารอยู่", ["That plate isn't allowed"] = "ป้ายนี้ใช้ไม่ได้", ["That's already your plate"] = "ป้ายนี้ติดอยู่แล้ว",
	["Already fitted"] = "ติดอยู่แล้ว", ["Changed"] = "เปลี่ยนแล้ว", ["Unknown choice"] = "ไม่มีตัวเลือกนี้", ["The plate check is busy, try again"] = "ระบบตรวจป้ายไม่ว่าง ลองใหม่",
	["Only Thai letters, A-Z, numbers and -"] = "ใช้ได้เฉพาะตัวอักษรไทย A-Z ตัวเลข และ -", ["A bicycle can only change its bell"] = "จักรยานเปลี่ยนได้แค่กระดิ่ง",
	-- Tier-A plan (2026-11-17)
	["Shop"] = "ร้านค้า", ["Season"] = "ซีซัน", ["Company"] = "บริษัท",
	["That code doesn't exist"] = "ไม่มีโค้ดนี้", ["That code has expired"] = "โค้ดนี้หมดอายุแล้ว", ["You already used that code"] = "ใช้โค้ดนี้ไปแล้ว",
	["Code redeemed!"] = "รับรางวัลจากโค้ดแล้ว!", ["You haven't unlocked that title"] = "ยังไม่ได้ปลดล็อกฉายานี้", ["Title changed"] = "เปลี่ยนฉายาแล้ว",
	["Not reached yet"] = "ยังไม่ถึงขั้นนี้", ["Needs the Premium Season Pass"] = "ต้องมี Season Pass พรีเมียม", ["Already claimed"] = "รับไปแล้ว",
	["Nothing on this tier"] = "ขั้นนี้ไม่มีรางวัล", ["Claimed"] = "รับแล้ว",
	["Reach the Rider rank first (30 jobs)"] = "ต้องถึงยศไรเดอร์ก่อน (30 งาน)", ["Rank up to hire more riders"] = "เลื่อนยศเพื่อจ้างไรเดอร์เพิ่ม",
	["Hired a rider"] = "จ้างไรเดอร์แล้ว", ["Hire a rider first"] = "จ้างไรเดอร์ก่อน", ["Already at the top level"] = "ระดับสูงสุดแล้ว",
	["Better bikes for everyone"] = "อัปเกรดรถให้ทุกคนแล้ว", ["Nothing to collect yet"] = "ยังไม่มีเงินให้เก็บ",
	["Needs the VIP pass"] = "ต้องมีพาส VIP", ["Needs the Neon Pro pass"] = "ต้องมีพาสนีออนโปร", ["Unlocked in the Season Pass"] = "ปลดล็อกได้จาก Season Pass",
	["Rank up!"] = "เลื่อนยศ!", ["🔥 Rush Hour +50%"] = "🔥 ชั่วโมงเร่งด่วน +50%",
	["🏢 You can open your own rider company now: Company app on the phone"] = "🏢 เปิดบริษัทไรเดอร์ของตัวเองได้แล้ว: แอปบริษัทในมือถือ",
	["Talk to the stand boss"] = "คุยกับพี่วิน", ["Motorbike Taxi Stand"] = "วินมอเตอร์ไซค์", ["Driving licence test"] = "สอบใบขับขี่", ["Transport Office"] = "สำนักงานขนส่ง",
	["⏳ Waited for the passenger +20"] = "⏳ รอผู้โดยสาร +20", ["⏳ 'Sorry for the wait!' +20"] = "⏳ 'ขอโทษที่ให้รอนะ' +20",
	["😤 Customer sulked: you didn't stop"] = "😤 ลูกค้างอน: ไม่แวะให้", ["😤 Review: 'the rider wouldn't stop for my photos'"] = "😤 รีวิว: 'ไรเดอร์ไม่ยอมแวะให้ถ่ายรูป'",
	["🙏 Tip: 'thank you!' (no money)"] = "🙏 ทิป: 'ขอบคุณค่ะ' (ไม่มีเงิน)", ["OK, straight there then."] = "โอเค ไปส่งเลย",
	["Two loans at once is the limit (even this finance company has rules)"] = "ผ่อนได้ทีละ 2 คันเท่านั้น (ไฟแนนซ์ก็มีกฎนะ)",
	["No loan on that vehicle"] = "รถคันนี้ไม่ได้ผ่อนอยู่", ["The vehicle was repossessed"] = "รถถูกยึดแล้ว", ["Unknown request"] = "คำขอไม่ถูกต้อง",
	["Repossessed! Pay the overdue instalments in the Finance app"] = "รถถูกยึด! จ่ายค่างวดที่ค้างในแอปไฟแนนซ์ก่อน",
	["Pick-up point"] = "จุดรับผู้โดยสาร", ["1 passenger"] = "ผู้โดยสาร 1 คน", ["🍜 Food"] = "🍜 อาหาร", ["🛍 Shops"] = "🛍 ร้านค้า", ["🏥 Services"] = "🏥 บริการ",
	["Background music"] = "เพลงประกอบ", ["Upbeat songs while you ride (Radio app: station, volume)"] = "เพลงสนุกๆ ระหว่างขี่ (แอปวิทยุ: เลือกคลื่น ปรับเสียง)",
	["Nearest fuel station"] = "ปั๊มน้ำมันใกล้สุด", ["Go"] = "ไป", ["Clear"] = "ล้าง", ["PLACES"] = "สถานที่", ["Loading places…"] = "กำลังโหลดสถานที่…",
	["Map data © OpenStreetMap contributors"] = "ข้อมูลแผนที่ © ผู้ร่วมพัฒนา OpenStreetMap",
	-- garage
	["FUEL STATION"] = "ปั๊มน้ำมัน", ["SERVICE BAY"] = "ศูนย์บริการ", ["Fuel"] = "น้ำมัน", ["Condition"] = "สภาพรถ", ["Fill the tank"] = "เติมเต็มถัง", ["Refuel"] = "เติม",
	["Repair"] = "ซ่อม", ["In perfect shape"] = "สภาพดีเยี่ยม", ["Restore to 100%"] = "ซ่อมให้กลับเป็น 100%", ["Upgrades & paint"] = "อัปเกรดและทำสี", ["Open"] = "เปิด",
	["Tuning"] = "แต่งรถ", ["KK MOTORS"] = "KK MOTORS", ["Buy, upgrade and paint here"] = "ซื้อ อัปเกรด และทำสีรถได้ที่นี่", ["MY VEHICLES"] = "รถของฉัน",
	["Details"] = "ดู", ["FOR SALE"] = "รถขาย", ["SHOWROOM (buy at KK Motors)"] = "โชว์รูม (ซื้อได้ที่ KK Motors)", ["View"] = "ดู", ["Store vehicle"] = "เก็บรถ",
	["Put your current vehicle away"] = "เก็บรถคันที่ใช้อยู่", ["Store"] = "เก็บ", ["Top speed"] = "ความเร็วสูงสุด", ["Acceleration"] = "อัตราเร่ง", ["Braking"] = "การเบรก",
	["Comfort"] = "ความนุ่มนวล", ["🔑 Bring it to me"] = "🔑 เรียกรถมาหาฉัน", ["Visit KK Motors (see Maps) to buy."] = "ไปซื้อที่ KK Motors (ดูในแผนที่)",
	["Full price at stations · emergency delivery costs 2.5×"] = "ราคาปกติที่ปั๊ม · สั่งเติมฉุกเฉินแพงกว่า 2.5 เท่า",
	["A worn vehicle is slower. Repair at KK Motors or a station."] = "รถโทรมจะวิ่งช้าลง ซ่อมได้ที่ KK Motors หรือปั๊ม",
	["UPGRADES (fitted at KK Motors)"] = "อัปเกรด (ติดตั้งที่ KK Motors)", ["MAX"] = "สูงสุด",
	-- property
	["Your home is in this server"] = "บ้านของคุณอยู่ในเซิร์ฟเวอร์นี้", ["Plots of this size are full here — home is safe"] = "ที่ดินขนาดนี้เต็มแล้วในเซิร์ฟเวอร์นี้ — บ้านคุณยังอยู่",
	["Navigate home"] = "นำทางกลับบ้าน", ["Set the GPS to your front door"] = "ตั้ง GPS ไปหน้าบ้าน", ["Build Mode"] = "โหมดแต่งบ้าน", ["Build"] = "แต่ง",
	["Place, move and remove furniture"] = "วาง ย้าย และเอาเฟอร์นิเจอร์ออก", ["Go to your plot to build"] = "ไปที่ดินของคุณก่อนจึงจะแต่งบ้านได้", ["Go to your plot first"] = "ไปที่ดินของคุณก่อน",
	["WHAT FURNITURE DOES"] = "เฟอร์นิเจอร์ช่วยอะไร", ["Bed"] = "เตียง", ["Sleep to refill Energy fast"] = "นอนเพื่อฟื้นพลังงานเร็ว", ["Stores up to 60 food items"] = "เก็บอาหารได้ 60 ชิ้น",
	["Cook crops into meals to eat or sell"] = "นำผลผลิตมาทำอาหารกินหรือขาย", ["Shower / 📺 TV"] = "ฝักบัว / 📺 ทีวี", ["Restore Happiness (better tips)"] = "เพิ่มความสุข (ได้ทิปมากขึ้น)",
	["Bring your vehicle home"] = "จอดรถที่บ้าน", ["Half-price repairs and upgrades at home"] = "ซ่อมและอัปเกรดที่บ้านลดครึ่งราคา", ["DANGER ZONE"] = "ระวัง",
	["Sell land"] = "ขายที่ดิน", ["60% of the land price + 50% of furniture"] = "ได้คืน 60% ของราคาที่ดิน + 50% ของเฟอร์นิเจอร์", ["Sell"] = "ขาย",
	["Tap Sell again to confirm"] = "กดขายอีกครั้งเพื่อยืนยัน", ["Buy land, build a home"] = "ซื้อที่ดิน สร้างบ้าน", ["Visit a FOR SALE sign to buy that plot"] = "ไปที่ป้าย FOR SALE เพื่อซื้อที่ดินแปลงนั้น",
	["Find"] = "หา", ["This plot already has an owner."] = "ที่ดินนี้มีเจ้าของแล้ว", ["You already own land. Sell it in the Property app to move."] = "คุณมีที่ดินแล้ว ขายในแอปบ้าน/ที่ดินก่อนย้าย",
	["Buy this plot"] = "ซื้อที่ดินนี้", ["Furniture limit"] = "จำนวนเฟอร์นิเจอร์สูงสุด", ["House"] = "บ้าน", ["Land for sale"] = "ที่ดินขาย",
	-- farming
	["🔒 Locked"] = "🔒 ล็อก", ["Needs tilling"] = "ต้องพรวนดิน", ["Ready to plant"] = "พร้อมปลูก", ["No allotment in this server"] = "ไม่มีแปลงผักในเซิร์ฟเวอร์นี้",
	["Till → plant → water → harvest → sell"] = "พรวนดิน → ปลูก → รดน้ำ → เก็บเกี่ยว → ขาย", ["MY BEDS"] = "แปลงของฉัน", ["MY BEDS (go to the farm to work them)"] = "แปลงของฉัน (ไปที่ฟาร์มเพื่อดูแล)",
	["Till"] = "พรวน", ["Go to your allotment first"] = "ไปที่แปลงผักของคุณก่อน", ["TODAY'S MARKET (Farmers' Market buys crops)"] = "ราคาตลาดวันนี้ (ขายที่ตลาดเกษตร)",
	["No seeds. Buy some at the Isan Seed Shop next to the farm."] = "ไม่มีเมล็ดพันธุ์ ซื้อได้ที่ร้านเมล็ดพันธุ์อีสานข้างฟาร์ม", ["Nothing is growing here."] = "ไม่มีอะไรปลูกอยู่",
	["Growth"] = "การเติบโต", ["Health"] = "สุขภาพ", ["Each harvest tires the soil. Compost restores it."] = "เก็บเกี่ยวแต่ละครั้งดินจะเสื่อม ใช้ปุ๋ยหมักฟื้นดิน",
	["Crops only grow while watered. Rain waters for free."] = "ผักโตเฉพาะตอนมีน้ำ ฝนตกช่วยรดให้ฟรี", ["Better quality grade → bigger harvest"] = "เกรดดีขึ้น → ได้ผลผลิตมากขึ้น",
	["Use"] = "ใช้", ["Improves the soil of this bed"] = "ทำให้ดินแปลงนี้ดีขึ้น", ["🌾 Harvest"] = "🌾 เก็บเกี่ยว", ["Clear bed"] = "ล้างแปลง",
	["Remove the crop (nothing is refunded)"] = "ถอนผักทิ้ง (ไม่ได้อะไรคืน)", ["Plant at your allotment"] = "ปลูกที่แปลงผักของคุณ", ["Sell at the Farmers' Market or cook at home"] = "ขายที่ตลาดเกษตรหรือทำอาหารที่บ้าน",
	["Crop care"] = "ดูแลผัก",
	-- bag / fridge / cooking / shop
	["PRODUCE"] = "ผลผลิต", ["SEEDS"] = "เมล็ดพันธุ์", ["SUPPLIES"] = "อุปกรณ์", ["Your bag is empty. Buy food at any restaurant or GoMart 24."] = "กระเป๋าว่าง ซื้ออาหารได้ที่ร้านอาหารหรือ GoMart 24",
	["IN YOUR BAG"] = "ในกระเป๋า", ["Take"] = "หยิบ", ["RECIPES (uses your bag and fridge)"] = "สูตรอาหาร (ใช้ของในกระเป๋าและตู้เย็น)",
	["Cooked meals restore more than street food, and the Fresh Market buys them."] = "อาหารทำเองฟื้นพลังได้มากกว่าอาหารข้างทาง และตลาดสดรับซื้อ", ["BUY"] = "ซื้อ", ["SELL"] = "ขาย",
	["Sell all"] = "ขายหมด", ["Nothing to sell yet."] = "ยังไม่มีอะไรจะขาย", ["WHERE TO?  ฿30 per ride"] = "ไปไหนดี?  ครั้งละ ฿30", ["Bus Stop"] = "ป้ายรถเมล์",
	["Refrigerator"] = "ตู้เย็น", ["Kitchen"] = "ครัว", ["My Career"] = "อาชีพของฉัน", ["Service"] = "ศูนย์บริการ",
	-- bank / profile / missions
	["Savings"] = "เงินออม", ["DEPOSIT"] = "ฝากเงิน", ["WITHDRAW"] = "ถอนเงิน", ["All"] = "ทั้งหมด", ["CAREER"] = "ผลงาน", ["Food deliveries"] = "ส่งอาหาร",
	["Passenger rides"] = "รับส่งผู้โดยสาร", ["Distance driven"] = "ระยะทางที่ขับ", ["Lifetime earnings"] = "รายได้ทั้งหมด", ["Five-star jobs"] = "งานห้าดาว", ["Harvests"] = "เก็บเกี่ยว",
	["Vehicles owned"] = "รถที่มี", ["None yet"] = "ยังไม่มี", ["Time played"] = "เวลาที่เล่น", ["🎁 Daily Reward"] = "🎁 รางวัลรายวัน", ["Come back tomorrow"] = "กลับมาใหม่พรุ่งนี้",
	["Claim"] = "รับ", ["Done"] = "เสร็จแล้ว", ["DAILY MISSIONS"] = "ภารกิจรายวัน",
	-- radio
	["Now playing"] = "กำลังเล่น", ["Radio is off"] = "ปิดวิทยุอยู่", ["Pick a station to ride with music"] = "เลือกสถานีเพื่อฟังเพลงระหว่างขี่", ["Licensed music from the Roblox library"] = "เพลงมีลิขสิทธิ์จากคลัง Roblox",
	["STATIONS"] = "สถานี", ["Stop"] = "หยุด", ["Play"] = "เล่น", ["Next track"] = "เพลงถัดไป", ["Skip to another song on this station"] = "ข้ามไปเพลงอื่นในสถานีนี้", ["Next"] = "ถัดไป",
	["VOLUME"] = "ระดับเสียง", ["Links from YouTube or other sites cannot be played inside Roblox."] = "ลิงก์ YouTube หรือเว็บอื่นเล่นใน Roblox ไม่ได้",
	-- settings
	["DRIVING"] = "การขับขี่", ["Steering sensitivity"] = "ความไวพวงมาลัย", ["Driving assist"] = "ตัวช่วยขับ", ["Extra grip so the vehicle is easier to control"] = "เกาะถนนขึ้นและเลี้ยวง่ายขึ้น",
	["ON"] = "เปิด", ["OFF"] = "ปิด", ["SOUND"] = "เสียง", ["Sound effects"] = "เสียงประกอบ", ["Engines, rain, UI"] = "เครื่องยนต์ ฝน ปุ่มกด", ["City ambience"] = "เสียงบรรยากาศเมือง",
	["Birds, traffic and night sounds"] = "เสียงนก รถ และกลางคืน", ["LANGUAGE"] = "ภาษา", ["GRAPHICS"] = "กราฟิก", ["CONTROLS"] = "ปุ่มควบคุม", ["Accelerate · brake / reverse"] = "เร่ง · เบรก / ถอย",
	["Steer"] = "เลี้ยว", ["Handbrake"] = "เบรกมือ", ["Boost"] = "เร่งพิเศษ", ["Headlights (get in: F)"] = "ไฟหน้า (ขึ้นรถ: F)", ["Indicators / hazards"] = "ไฟเลี้ยว / ไฟฉุกเฉิน",
	["Interact · leave vehicle"] = "ใช้งาน · ลงจากรถ", ["Pick up / deliver while driving"] = "รับ / ส่งของขณะอยู่บนรถ", ["Accept a job offer"] = "รับออร์เดอร์", ["Phone"] = "มือถือ",
	-- reward card / banners
	["Reward"] = "รางวัล", ["Fare"] = "ค่าส่ง", ["Money"] = "เงิน", ["Tip"] = "ทิป", ["Experience"] = "ประสบการณ์", ["Item"] = "ไอเทม",
	["💥 Crash! Your vehicle took damage"] = "💥 ชน! รถเสียหาย", ["Order delivered!"] = "ส่งอาหารสำเร็จ!", ["😪 Tired −20%"] = "😪 เหนื่อย ค่าส่ง −20%",
	["⏰ Very late −40%"] = "⏰ ส่งช้ามาก −40%", ["⏰ Late −20%"] = "⏰ ส่งช้า −20%", ["Delivered!"] = "ส่งสำเร็จ!", ["Ride complete!"] = "ส่งผู้โดยสารสำเร็จ!", ["New vehicle!"] = "รถใหม่!",
	-- driving toasts (client)
	["💥 Too fast into the corner: you went down!"] = "💥 เข้าโค้งเร็วเกินไป รถล้ม!", ["💥 Rolled it! Slow down for corners."] = "💥 รถพลิกคว่ำ! ชะลอก่อนเข้าโค้ง",
	["⛽ Out of fuel! Open Garage on your phone for emergency fuel."] = "⛽ น้ำมันหมด! เปิดมือถือ → โรงรถ เพื่อสั่งเติมฉุกเฉิน",
	["⛽ Fuel is low. Phone > Maps > Nearest fuel station."] = "⛽ น้ำมันใกล้หมด ดูแถบด้านบนเพื่อนำทางไปปั๊ม",
	-- server messages
	["A peaceful moment. Happiness +25"] = "จิตใจสงบ ความสุข +25", ["Already at max level"] = "เลเวลสูงสุดแล้ว", ["Already claimed today"] = "วันนี้รับไปแล้ว", ["Already claimed"] = "รับไปแล้ว",
	["Already that colour"] = "เป็นสีนี้อยู่แล้ว", ["Already tilled"] = "พรวนแล้ว", ["Already unlocked"] = "ปลดล็อกแล้ว", ["Already well watered"] = "รดน้ำพอแล้ว",
	["Bring out a vehicle first (Garage app)"] = "เรียกรถออกมาก่อน (แอปโรงรถ)", ["Rides need a motorbike or car with a passenger seat (KK Motors)"] = "รับส่งคนต้องใช้มอเตอร์ไซค์หรือรถยนต์ที่มีที่นั่งผู้โดยสาร (ซื้อที่ KK Motors)", ["Daily reward claimed"] = "รับรางวัลรายวันแล้ว", ["Delivery could not be verified."] = "ตรวจสอบการส่งไม่ผ่าน",
	["Dropped"] = "ทิ้งแล้ว", ["Enter an amount"] = "ใส่จำนวน", ["Fully fertilized"] = "ใส่ปุ๋ยเต็มแล้ว", ["Furniture limit reached for this plot"] = "เฟอร์นิเจอร์เต็มแล้ว",
	["Get closer to the drop-off point"] = "เข้าใกล้จุดส่งอีกนิด", ["Get closer to the pick-up point"] = "เข้าใกล้จุดรับอีกนิด", ["Get off your vehicle first"] = "ลงจากรถก่อน",
	["Go home to cook"] = "กลับบ้านไปทำอาหาร", ["Go home to use your fridge"] = "กลับบ้านไปใช้ตู้เย็น", ["Go to the bus stop"] = "ไปที่ป้ายรถเมล์", ["Go to the hospital"] = "ไปโรงพยาบาล",
	["Go to the police station"] = "ไปสถานีตำรวจ", ["Go to the stupa"] = "ไปที่พระธาตุ", ["Go to your allotment at the Community Farm"] = "ไปที่แปลงผักของคุณที่ฟาร์มชุมชน",
	["Job cancelled. Your rating dropped a little."] = "ยกเลิกงานแล้ว เรตติ้งลดลงเล็กน้อย", ["Mission not active"] = "ภารกิจนี้ยังไม่เปิด", ["Moved"] = "ย้ายแล้ว",
	["Needs a 4.5★ rating (3+ jobs)"] = "ต้องมีเรตติ้ง 4.5★ (3 งานขึ้นไป)", ["No repairs needed"] = "ไม่ต้องซ่อม", ["No such bed"] = "ไม่มีแปลงนี้", ["Not enough cash"] = "เงินสดไม่พอ",
	["Not enough in the bank"] = "เงินในธนาคารไม่พอ", ["Not enough money for fuel"] = "เงินไม่พอเติมน้ำมัน", ["Not enough money"] = "เงินไม่พอ", ["Not finished yet"] = "ยังไม่เสร็จ",
	["Not in the fridge"] = "ไม่มีในตู้เย็น", ["Not ready yet"] = "ยังไม่พร้อม", ["Not ready"] = "ยังไม่พร้อม", ["Not sold here"] = "ที่นี่ไม่ขาย", ["Nothing planted"] = "ยังไม่ได้ปลูกอะไร",
	["Only food goes in the fridge"] = "ใส่ได้เฉพาะอาหาร", ["Only the owner can use this"] = "เจ้าของเท่านั้นที่ใช้ได้", ["Paint jobs are done at KK Motors"] = "ทำสีได้ที่ KK Motors",
	["Pick a destination"] = "เลือกจุดหมาย", ["Pick a seed"] = "เลือกเมล็ดพันธุ์", ["Repairs are done at KK Motors or a fuel station"] = "ซ่อมได้ที่ KK Motors หรือปั๊มน้ำมัน",
	["Reward claimed"] = "รับรางวัลแล้ว", ["Safe driver bonus +฿120"] = "โบนัสขับขี่ปลอดภัย +฿120", ["Soil is already rich"] = "ดินดีอยู่แล้ว", ["Someone already owns this plot"] = "มีคนเป็นเจ้าของที่ดินนี้แล้ว",
	["Something is growing here"] = "มีผักปลูกอยู่แล้ว", ["Stand closer to a road"] = "ยืนใกล้ถนนอีกนิด", ["Stop the vehicle first"] = "หยุดรถก่อน", ["Tank is full"] = "น้ำมันเต็มถังแล้ว",
	["That piece is gone"] = "ชิ้นนี้ไม่อยู่แล้ว", ["The fare is ฿30"] = "ค่าโดยสาร ฿30", ["The fridge is full"] = "ตู้เย็นเต็มแล้ว", ["They don't buy that here"] = "ที่นี่ไม่รับซื้อของนี้",
	["This isn't your allotment. Yours is marked on the map."] = "นี่ไม่ใช่แปลงของคุณ แปลงของคุณมีเครื่องหมายบนแผนที่", ["Till the soil first"] = "พรวนดินก่อน",
	["Too far from the shop"] = "อยู่ไกลร้านเกินไป", ["Treatment costs ฿150"] = "ค่ารักษา ฿150", ["Unlock the previous bed first"] = "ปลดล็อกแปลงก่อนหน้าก่อน", ["Unlock this bed first"] = "ปลดล็อกแปลงนี้ก่อน",
	["Upgrades are fitted at KK Motors"] = "อัปเกรดได้ที่ KK Motors", ["VIP riders want a more comfortable car"] = "ลูกค้า VIP อยากได้รถที่นั่งสบายกว่านี้", ["Vehicle stored"] = "เก็บรถแล้ว",
	["Visit KK Motors to buy vehicles"] = "ไปซื้อรถที่ KK Motors", ["Visit the plot to buy it"] = "ไปที่ดินแปลงนั้นเพื่อซื้อ", ["Wait a moment"] = "รอสักครู่", ["You already own it"] = "คุณมีอยู่แล้ว",
	["You already own land. Sell it first."] = "คุณมีที่ดินแล้ว ขายก่อน", ["You already visited today"] = "วันนี้มาแล้ว", ["You can't eat that"] = "กินไม่ได้",
	["You don't have any"] = "คุณไม่มีของนี้", ["You don't have that many"] = "คุณมีไม่พอ", ["You don't own land yet"] = "คุณยังไม่มีที่ดิน", ["You don't own that vehicle"] = "คุณไม่มีรถคันนี้",
	["You feel much better"] = "รู้สึกดีขึ้นมาก", ["You have no allotment in this server"] = "คุณไม่มีแปลงผักในเซิร์ฟเวอร์นี้", ["You have no compost"] = "คุณไม่มีปุ๋ยหมัก",
	["You have no fertilizer"] = "คุณไม่มีปุ๋ย", ["You need a kitchen stove"] = "ต้องมีเตาครัว", ["You need a refrigerator"] = "ต้องมีตู้เย็น", ["You need to be in your vehicle"] = "ต้องอยู่บนรถ",
	["You stopped resting"] = "หยุดพักแล้ว", ["You're healthy already"] = "คุณแข็งแรงดีอยู่แล้ว", ["You're too tired to work. Rest or have a drink first."] = "เหนื่อยเกินไป พักหรือดื่มอะไรก่อน",
	["Your bag is full (eat something or use your fridge)"] = "กระเป๋าเต็ม (กินอะไรสักอย่างหรือใช้ตู้เย็น)", ["Your bag is full"] = "กระเป๋าเต็ม",
	["Your home isn't in this server (plots were full)"] = "บ้านของคุณไม่ได้อยู่ในเซิร์ฟเวอร์นี้ (ที่ดินเต็ม)", ["Your passenger is gone. Cancel the ride."] = "ผู้โดยสารหายไปแล้ว ยกเลิกงานได้เลย",
	["⚡ Fully rested!"] = "⚡ พักเต็มที่แล้ว!", ["🍜 You're hungry. Find something to eat!"] = "🍜 หิวแล้ว! หาอะไรกินหน่อย", ["😪 You're exhausted. Rest at a bench or your bed."] = "😪 เหนื่อยมาก พักที่ม้านั่งหรือเตียง",
	["🍜 You're hungry: new orders are paused until you eat. Follow the card at the top."] = "🍜 หิวแล้ว! หยุดรับออร์เดอร์ไว้ก่อนจนกว่าจะได้กินข้าว ทำตามแถบด้านบนได้เลย",
	["😪 You're exhausted: new orders are paused. Rest or grab a coffee."] = "😪 เหนื่อยมาก! หยุดรับออร์เดอร์ไว้ก่อน พักหรือดื่มกาแฟก่อนนะ",
	["Nothing to eat here"] = "ร้านนี้ไม่มีของกิน", ["Eat now"] = "กินเลย", ["+ Bag"] = "+ กระเป๋า", ["Unknown shop or item"] = "ไม่พบร้านหรือสินค้า",
	["🐕 A soi dog bit you!  −10 happiness"] = "🐕 โดนหมาในซอยกัด!  ความสุข −10", ["Come back tomorrow."] = "กลับมาใหม่พรุ่งนี้",
	-- dialogue
	["Is that my food? I'm starving!"] = "อาหารของฉันใช่ไหม หิวจะแย่แล้ว!", ["Extra spicy please, no veggies!"] = "เผ็ดๆ ไม่ใส่ผักนะ!", ["Over here, rider!"] = "ทางนี้จ้าไรเดอร์!",
	["I ordered ages ago..."] = "สั่งไปนานแล้วนะ...", ["This food smells amazing!"] = "หอมมากเลย!", ["Hope it's still hot!"] = "หวังว่ายังร้อนอยู่นะ!",
	["Thanks! Five stars for you!"] = "ขอบคุณ! ให้ห้าดาวเลย!", ["So fast! You're the best."] = "ไวมาก! เก่งที่สุด", ["Perfect, keep the change!"] = "เยี่ยม ไม่ต้องทอน!",
	["Khop khun der!"] = "ขอบคุณเด้อ!", ["Sep lai! Thank you!"] = "แซ่บหลาย! ขอบคุณ!", ["Thanks."] = "ขอบคุณ", ["Okay, thank you."] = "โอเค ขอบคุณ",
	["A bit late, but fine."] = "ช้าไปหน่อย แต่ไม่เป็นไร", ["Got it, thanks."] = "ได้แล้ว ขอบคุณ", ["It's cold..."] = "เย็นชืดหมดแล้ว...", ["What took you so long?"] = "ทำไมนานจัง?",
	["My soup is spilled!"] = "น้ำซุปหกหมดเลย!", ["Not happy about this."] = "ไม่ค่อยพอใจนะ", ["It's raining! Drive carefully!"] = "ฝนตก! ขับระวังนะ!",
	["You came in this rain? Here's a tip."] = "ฝนตกขนาดนี้ยังมาส่ง เอาทิปไป", ["Thank you for braving the storm!"] = "ขอบคุณที่ฝ่าพายุมาส่ง!", ["Hi! Let's go."] = "สวัสดี ไปกันเลย",
	["Hurry up! I'm late for class!"] = "เร็วๆ หน่อย จะสายแล้ว!", ["To the destination, please."] = "ไปตามจุดหมายเลยค่ะ", ["Nice ride!"] = "รถสวยนะ!", ["Sawasdee! Thanks for coming."] = "สวัสดี ขอบคุณที่มารับ",
	["Can you take the quick way?"] = "ไปทางลัดได้ไหม?", ["Khon Kaen traffic, eh?"] = "รถติดขอนแก่นเนาะ", ["Have you tried the som tam near the lake?"] = "เคยกินส้มตำแถวบึงแก่นนครไหม?",
	["I love the night market here."] = "ชอบตลาดโต้รุ่งที่นี่มาก", ["Slow down a little, please!"] = "ช้าลงหน่อยนะ!", ["The lake looks beautiful today."] = "วันนี้บึงสวยมาก",
	["My friend drives for GoDash too."] = "เพื่อนฉันก็ขับ GoDash", ["Is this your own vehicle?"] = "รถของตัวเองเหรอ?", ["Whoa! Careful!"] = "เฮ้ย! ระวัง!", ["Hey, watch the road!"] = "ดูถนนด้วย!",
	["I want to arrive alive!"] = "ขอไปถึงแบบยังหายใจนะ!", ["Too fast!"] = "เร็วไปแล้ว!", ["Thanks for the ride!"] = "ขอบคุณที่มาส่ง!", ["Smooth driving. Five stars!"] = "ขับนุ่มมาก ห้าดาว!",
	["That was quick, thank you!"] = "ไวดี ขอบคุณ!", ["See you around!"] = "แล้วเจอกัน!", ["Okay, bye."] = "โอเค บาย", ["Here's the fare."] = "นี่ค่าโดยสาร", ["Never again..."] = "ไม่เอาอีกแล้ว...",
	["That was rough."] = "หวาดเสียวมาก", ["You drive like a maniac!"] = "ขับอย่างกับบ้า!", ["Order's ready!"] = "อาหารเสร็จแล้ว!", ["Here you go, drive safe!"] = "นี่จ้า ขับปลอดภัยนะ!",
	["Hot and fresh!"] = "ร้อนๆ สดๆ!", ["One GoDash order, coming up!"] = "ออร์เดอร์ GoDash ได้แล้วจ้า!", ["Welcome! What would you like?"] = "ยินดีต้อนรับ รับอะไรดีคะ?", ["Sawasdee kha!"] = "สวัสดีค่ะ!",
	["Best food in Khon Kaen!"] = "อร่อยที่สุดในขอนแก่น!", ["Hungry? Take a look."] = "หิวไหม ดูก่อนได้", ["Welcome!"] = "ยินดีต้อนรับ!", ["Take your time."] = "ค่อยๆ เลือกนะ",
	["Everything's fresh today."] = "วันนี้ของสดทุกอย่าง", ["Need anything else?"] = "เอาอะไรเพิ่มไหม?", ["Good soil this year."] = "ปีนี้ดินดี", ["Water them every day!"] = "รดน้ำทุกวันนะ!",
	["Rain is coming, I can feel it."] = "ฝนกำลังมา รู้สึกได้", ["Market prices change daily, check your phone."] = "ราคาตลาดเปลี่ยนทุกวัน ดูในมือถือนะ", ["Sawasdee!"] = "สวัสดี!",
	["Nice bike!"] = "รถเท่จัง!", ["Hot today, isn't it?"] = "วันนี้ร้อนเนาะ", ["Are you a GoDash rider?"] = "เป็นไรเดอร์ GoDash เหรอ?", ["Have you eaten yet?"] = "กินข้าวยัง?",
	["Careful on Mittraphap Road."] = "ระวังถนนมิตรภาพนะ", ["The night market opens soon."] = "ตลาดโต้รุ่งใกล้เปิดแล้ว", ["Beautiful evening."] = "เย็นนี้อากาศดี",
	["I'm off to the lake."] = "จะไปบึงแก่นนคร", ["Rain again? Mai pen rai."] = "ฝนอีกแล้ว ไม่เป็นไร", ["I forgot my umbrella!"] = "ลืมร่ม!", ["So much rain!"] = "ฝนตกหนักมาก!",
	["Run for cover!"] = "หลบฝนเร็ว!",
}

---------------------------------------------------------------------------------------------------
-- patterns: { lua pattern, replacement }. "%1" in a replacement is the capture, translated as a
-- noun when it is one. A function replacement gets the raw captures.
---------------------------------------------------------------------------------------------------
local function n(s: string): string
	return N[s] or E[s] or s
end

local P = {
	-- HUD / jobs
	{ "^Collect at (.+)$", "รับอาหารที่ %1" }, { "^Deliver to (.+)$", "ส่งที่ %1" }, { "^Pick up (.+)$", "รับ %1" }, { "^Drive to (.+)$", "ไปส่งที่ %1" },
	{ "^Go to (.+) · (.+)$", "ไปที่ %1 · %2" }, { "^Go to (.+)$", "ไปที่ %1" },
	{ "^late (.+)$", "สาย %1" }, { "^🧍 Pick up: (.+)$", "🧍 รับที่: %1" }, { "^🍱 From: (.+)$", "🍱 รับที่: %1" }, { "^📍 To: (.+)$", "📍 ส่งที่: %1" },
	{ "^(.+) trip · (.+) to pick%-up · (.+) · %+(%d+) EXP$", function(a, b, c, d) return ("ระยะส่ง %s · ไปร้าน %s · %s · +%s EXP"):format(a, b, n(c), d) end },
	{ "^(.-) · (.-) · (฿[%d,]+)$", function(a, b, c) return n(a) .. " · " .. n(b) .. " · " .. c end },
	{ "^(%d+) / (%d+) EXP$", "%1 / %2 EXP" },
	{ "^🌧 Rain bonus %+(%d+)%%(.*)$", function(a, rest) return "🌧 โบนัสฝน +" .. a .. "%" .. rest:gsub("🌙 Night %+10%%", "🌙 กลางคืน +10%") end },
	{ "^🌙 Night %+10%%$", "🌙 กลางคืน +10%" },
	{ "^🚦 Ran a red light! Fine (.+)$", function(a) return "🚦 ฝ่าไฟแดง! โดนปรับ " .. (a == "(no cash)" and "(ไม่มีเงินสด)" or a) end },
	{ "^🚸 Didn't stop for people on the zebra crossing! Fine (.+)$", function(a) return "🚸 ไม่หยุดให้คนข้ามทางม้าลาย! โดนปรับ " .. (a == "(no cash)" and "(ไม่มีเงินสด)" or a) end },
	{ "^No rides: (.+)$", "รับคนไม่ได้: %1" },
	{ "^Ride%-hailing unlocks at level (%d+)$", "งานรับส่งคนปลดล็อกที่เลเวล %1" },
	{ "^This order needs a vehicle with cargo (%d+)%+ %(a car or pickup%)$", "ออร์เดอร์นี้ต้องใช้รถที่บรรทุกได้ %1+ (รถยนต์หรือกระบะ)" },
	{ "^Needs (%d+) passenger seats$", "ต้องมีที่นั่งผู้โดยสาร %1 ที่" },
	-- rewards and banners
	{ "^LEVEL UP!  Lv (%d+)$", "เลเวลอัป!  Lv %1" }, { "^Bonus %+(฿[%d,]+) · new jobs may be unlocked$", "โบนัส +%1 · อาจมีงานใหม่ปลดล็อก" },
	{ "^Sawasdee, (.+)!$", "สวัสดี %1!" }, { "^Sawasdee, (.+)$", "สวัสดี %1" },
	{ "^Welcome to (.+)%. Open your phone %(M%) and go Online%.$", function(city) return "ยินดีต้อนรับสู่" .. (city == "Khon Kaen" and "ขอนแก่น" or city) .. " ทำตามแถบด้านบนได้เลย" end },
	{ "^⏱ (.+)   🛣 Smooth (.+)   🛡 Safe (.+)$", "⏱ %1   🛣 นุ่มนวล %2   🛡 ปลอดภัย %3" },
	{ "^💰 (.+)  (.+)$", function(a, b) return "💰 " .. n(a) .. "  " .. b end },
	{ "^Late by (.+)$", "ส่งช้า %1" },
	{ "^⚡ Fast delivery bonus %+(%d+)$", "⚡ โบนัสส่งไว +%1" }, { "^🛵🛵 Convoy x(%d+) %+(%d+)$", "🛵🛵 ขบวนไรเดอร์ %1 คัน +%2" }, { "^🍜 Not a drop spilled %+(%d+)$", "🍜 อาหารไม่หกเลยสักหยด +%1" }, { "^🙂 Smooth ride bonus %+(%d+)$", "🙂 ขับนุ่ม ผู้โดยสารชอบ +%1" },
	{ "^🍜 Spilled a little: (%d+) jolts$", "🍜 อาหารกระฉอก %1 ครั้ง" }, { "^🛡 Class (%S+): covered for (%d+) h$", "🛡 ประกันชั้น %1: คุ้มครองแล้ว %2 ชม." },
	{ "^⚠️ Broken%-down car blocking a lane on (.+)$", function(r) return "⚠️ รถเสียขวางเลนอยู่ที่" .. (r == "a street nearby" and "ถนนแถวนี้" or r) end },
	{ "^⚠️ Accident ahead on (.+): slow down$", function(r) return "⚠️ อุบัติเหตุข้างหน้า " .. (r == "a street nearby" and "ถนนแถวนี้" or r) .. " ชะลอด้วยนะ" end },
	{ "^🛍 A pop%-up market has closed (.+)$", function(r) return "🛍 ตลาดนัดปิดถนน " .. (r == "a street nearby" and "ถนนแถวนี้" or r) end },
	{ "^You are covered for 3 days already$", "ซื้อล่วงหน้าได้สูงสุด 3 วันนะ" }, { "^Repaired: insurance paid (.+), you paid (.+)$", "ซ่อมแล้ว: ประกันจ่าย %1 คุณจ่าย %2" }, { "^🤢 Rough ride: (%d+) jolts$", "🤢 ขับกระชาก %1 ครั้ง" }, { "^🚦 (%d+) red lights? on this trip$", "🚦 ฝ่าไฟแดง %1 ครั้งในรอบนี้" },
	-- server toasts with names
	{ "^Arrived at (.+)$", "ถึง %1 แล้ว" }, { "^Ate (.+)$", "กิน%1แล้ว" }, { "^Buy (.+) at the seed shop$", "ซื้อ%1ที่ร้านเมล็ดพันธุ์" },
	{ "^Cooked (.+)$", "ทำ%1แล้ว" }, { "^Costs (.+)$", "ราคา %1" }, { "^Missing (.+)$", "ขาด%1" }, { "^Painted (.+)$", "ทำสี %1 แล้ว" },
	{ "^Placed (.+)$", "วาง%1แล้ว" }, { "^Reach level (%d+) first$", "ต้องถึงเลเวล %1 ก่อน" }, { "^Removed %((.+)%)$", "เอาออกแล้ว (%1)" },
	{ "^Repair costs (.+)$", "ค่าซ่อม %1" }, { "^Repaired for (.+)$", "ซ่อมแล้ว %1" }, { "^Sold for (.+)$", "ขายได้ %1" }, { "^Sold your land for (.+)$", "ขายที่ดินได้ %1" },
	{ "^That's (.+)'s vehicle$", "นี่เป็นรถของ %1" }, { "^Unlock bed %((.+)%)$", "ปลดล็อกแปลง (%1)" }, { "^You bought a (.+)$", "ซื้อ%1แล้ว" }, { "^You bought the (.+)$", "ซื้อ %1 แล้ว" },
	{ "^All (.+) plots are occupied in this server%. Your home is safe; rejoin later to visit it%.$", "ที่ดิน %1 เต็มในเซิร์ฟเวอร์นี้ บ้านคุณยังอยู่ เข้าใหม่ภายหลังเพื่อไปบ้าน" },
	{ "^✨ (.+): (.+)$", function(a, b) return "✨ " .. n(a) .. ": " .. ({ ["+12% tips"] = "ทิป +12%", ["-35% energy drain"] = "พลังงานลดช้าลง 35%" })[b] or b end },
	{ "^🎯 Mission complete: (.+) — claim it in Missions$", "🎯 ภารกิจสำเร็จ: %1 — ไปรับรางวัลในแอปภารกิจ" },
	{ "^📅 Daily done: (.+) — claim it in Missions$", "📅 ภารกิจรายวันสำเร็จ: %1 — ไปรับรางวัลในแอปภารกิจ" },
	{ "^🏦 Bank interest %+(.+)$", "🏦 ดอกเบี้ยธนาคาร +%1" }, { "^😴 (.+)… stay close to keep resting$", "😴 %1… อยู่ใกล้ๆ เพื่อพักต่อ" },
	{ "^🚨 Police checkpoint! Fine (.+)$", function(a) return "🚨 ด่านตรวจ! โดนปรับ " .. (a == "(no cash)" and "(ไม่มีเงินสด)" or a) end },
	{ "^📍 Route set to (.+)$", "📍 ตั้งเส้นทางไป %1" },
	{ "^🧊 Picked up ice for the customer %+(%d+)$", "🧊 แวะซื้อน้ำแข็งให้ลูกค้า +%1" }, { "^📸 Photo stop for the passenger %+(%d+)$", "📸 แวะถ่ายรูปให้ผู้โดยสาร +%1" },
	{ "^🛵 Taxi%-stand bonus %+(%d+)$", "🛵 โบนัสพี่วิน +%1" }, { "^👀 The stand boss didn't like that pick%-up −(%d+)$", "👀 พี่วินมองค้อน รับลูกค้าในถิ่น −%1" },
	{ "^Paid off: ฿(%d+)$", "ปิดยอดแล้ว ฿%1" }, { "^Paid: ฿(%d+)$", "จ่ายแล้ว ฿%1" }, { "^Paid%. The vehicle is released: ฿(%d+)$", "จ่ายแล้ว รถได้คืนแล้ว ฿%1" },
	{ "^Drove off in the (.+): (%d+) × ฿(%d+)$", "ออกรถ %1 แล้ว: ผ่อน %2 × ฿%3" }, { "^(%d+) passengers$", "ผู้โดยสาร %1 คน" }, { "^📍 Route set$", "📍 ตั้งเส้นทางแล้ว" },
	{ "^Daily Reward · Day (%d+)$", "รางวัลประจำวัน · วันที่ %1" }, { "^Daily reward claimed$", "รับรางวัลประจำวันแล้ว" },
	{ "^Fitted for (฿[%d,]+)$", "ติดตั้งแล้ว %1" }, { "^Collected (฿[%d,]+)$", "เก็บเงินแล้ว %1" }, { "^Code (.+)$", "โค้ด %1" },
	{ "^Season (%d+) · tier (%d+)$", "ซีซัน %1 · ขั้น %2" }, { "^Rush Hour #(%d)!$", "ชั่วโมงเร่งด่วน อันดับ %1!" }, { "^Not enough money %((฿[%d,]+)%)$", "เงินไม่พอ (%1)" }, { "^Up to (%d+) characters$", "ไม่เกิน %1 ตัวอักษร" },
	-- phone composites
	{ "^Lv (%d+) · (.+) · ★ (.+)$", "เลเวล %1 · %2 · ★ %3" },
	{ "^Level (%d+) GoDash Rider · ★ (.+) %((%d+) ratings%)$", "ไรเดอร์ GoDash เลเวล %1 · ★ %2 (%3 รีวิว)" },
	{ "^(%d+) / (%d+) EXP to level (%d+)$", "%1 / %2 EXP สู่เลเวล %3" },
	{ "^🔒 Lv (%d+)$", "🔒 Lv %1" }, { "^🔒 Level (%d+) · (.+)$", "🔒 เลเวล %1 · %2" }, { "^🔒 Level (%d+)$", "🔒 เลเวล %1" }, { "^🔒 Reach level (%d+)$", "🔒 ต้องถึงเลเวล %1" },
	{ "^Unlocks at level (%d+)$", "ปลดล็อกที่เลเวล %1" },
	{ "^฿(%d+) %+ distance · %+(%d+) EXP(.*)$", function(a, b, rest)
		rest = rest:gsub(" · cargo (%d+)%+", " · บรรทุก %1+"):gsub(" · (%d+) seats", " · %1 ที่นั่ง"):gsub(" · rain only", " · เฉพาะตอนฝนตก")
		return "฿" .. a .. " + ตามระยะทาง · +" .. b .. " EXP" .. rest
	end },
	{ "^(.+) · (.+) away$", function(a, b) return n(a) .. " · ห่าง " .. b end }, { "^(.+) away$", "ห่าง %1" }, { "^(.+) by road$", "%1 ตามถนน" },
	{ "^Navigating to (.+)$", "กำลังนำทางไป %1" }, { "^My Allotment %((.+)%)$", "แปลงผักของฉัน (%1)" }, { "^Allotment (.+)$", "แปลงผัก %1" },
	{ "^Fuel (.-)/(.-) L · Condition (%d+)%%$", "น้ำมัน %1/%2 ลิตร · สภาพ %3%%" }, { "^Fuel (.-) / (.-) L$", "น้ำมัน %1 / %2 ลิตร" },
	{ "^Condition (%d+)%%$", "สภาพ %1%%" }, { "^Restore to 100%% · home workshop −50%%$", "ซ่อมให้กลับเป็น 100% · ที่บ้านลด 50%" },
	{ "^Tune your (.+)$", "แต่ง %1" }, { "^Buy for (.+)$", "ซื้อ %1" }, { "^Need (.+) more$", "ขาดอีก %1" },
	{ "^📦 Cargo (%d+)   🧍 Seats (%d+)   ⛽ (.+)$", function(a, b, c) return ("📦 บรรทุก %s   🧍 ที่นั่ง %s   ⛽ %s"):format(a, b, c == "pedal power" and "ใช้แรงปั่น" or c:gsub(" L$", " ลิตร")) end },
	{ "^PAINT · (.+)$", "ทำสี · %1" }, { "^(%d+) / (%d+) furniture · lot (%d+) × (%d+)$", "เฟอร์นิเจอร์ %1 / %2 · ที่ดิน %3 × %4" },
	{ "^(.+) · (.+) · (%d+)×(%d+) studs$", function(a, b, c, d) return a .. " · " .. b .. " · " .. c .. "×" .. d end },
	{ "^(.+) · (%d+) × (%d+) studs · house included$", "%1 · %2 × %3 · รวมบ้าน" }, { "^(%d+) pieces$", "%1 ชิ้น" },
	{ "^(%d+) × (%d+) studs, walls (%d+) high$", "%1 × %2 · ผนังสูง %3" }, { "^(.+) for sale$", "%1 ขาย" },
	{ "^(.+) ready! Grade (.+)$", "%1 พร้อมเก็บ! เกรด %2" }, { "^(.+) (%d+)%% · needs water(.*)$", function(a, b, f) return n(a) .. " " .. b .. "% · ต้องรดน้ำ" .. (f ~= "" and " · ใส่ปุ๋ยแล้ว" or "") end },
	{ "^(.+) (%d+)%% · ~(.+)$", function(a, b, t) return n(a) .. " " .. b .. "% · ~" .. t:gsub(" · fertilized", " · ใส่ปุ๋ยแล้ว") end },
	{ "^Bed (%d+)$", "แปลง %1" }, { "^Plant bed (%d+)$", "ปลูกแปลง %1" }, { "^CHOOSE A SEED FOR BED (%d+)$", "เลือกเมล็ดพันธุ์สำหรับแปลง %1" },
	{ "^Grows in (%d+)s · yields (%d+) · sells ~(.+) each$", "โตใน %1 วิ · ได้ %2 ชิ้น · ขาย ~%3 ต่อชิ้น" },
	{ "^Soil quality (%d+)%%$", "คุณภาพดิน %1%%" }, { "^Fertilizer × (%d+)$", "ปุ๋ย × %1" }, { "^Compost × (%d+)$", "ปุ๋ยหมัก × %1" },
	{ "^(.-)(%-?%d+)%% vs normal · you have (%d+) · seed (.+) · (%d+)s to grow$", "%1%2% จากปกติ · มี %3 · เมล็ด %4 · โตใน %5 วิ" },
	{ "^FOOD & DRINK  (%d+) / 16$", "อาหารและเครื่องดื่ม  %1 / 16" }, { "^IN THE FRIDGE  (%d+) / 60$", "ในตู้เย็น  %1 / 60" },
	{ "^(.+) · You have (.+)$", "%1 · มีเงิน %2" }, { "^ · You have (.+)$", "มีเงิน %1" },
	{ "^(.+) each · total (.+)$", "ชิ้นละ %1 · รวม %2" }, { "^Buying at (.+) each today$", "วันนี้รับซื้อชิ้นละ %1" },
	{ "^(.+) × (%d+)$", "%1 × %2" }, { "^(.+) ×(%d+)$", "%1 ×%2" }, { "^(.+) · (฿[%d,]+) each$", "%1 · ชิ้นละ %2" }, { "^(.+) · (฿[%d,]+)$", "%1 · %2" },
	{ "^(.+)  ✓$", "%1  ✓" }, { "^(.+)  ♪$", "%1  ♪" },
	{ "^(.+) → sells (.+)$", "%1 → ขาย %2" },
	{ "^Cash (.+) · 1%% interest per day %(max ฿2,500%)$", "เงินสด %1 · ดอกเบี้ย 1% ต่อวัน (สูงสุด ฿2,500)" },
	-- KK Bank, down payments, the hospital (2026-11-18)
	{ "^Approved! (.+) now, (%d+) × ฿(%d+)$", "อนุมัติแล้ว! รับเงิน %1 ผ่อน %2 × ฿%3" },
	{ "^Paid (฿[%d,]+)$", "จ่ายแล้ว %1" }, { "^Loan closed for (.+)$", "ปิดหนี้แล้ว %1" }, { "^Your credit limit is (.+)$", "วงเงินกู้ของคุณคือ %1" },
	{ "^Not enough cash %((.+)%)$", "เงินสดไม่พอ (%1)" }, { "^Paying it off costs (.+)$", "ปิดยอดต้องใช้ %1" },
	{ "^Drove off in the (.+): (.+) down, (%d+) × ฿(%d+)$", "ออกรถ %1 แล้ว! ดาวน์ %2 ผ่อน %3 × ฿%4" },
	{ "^The down payment is (.+)$", "เงินดาวน์ %1" }, { "^Treatment costs (.+)$", "ค่ารักษา %1" },
	{ "^Pay off your current loan first$", "ปิดหนี้ก้อนเดิมก่อนนะ" }, { "^No bank loan$", "ไม่มีเงินกู้ธนาคาร" },
	{ "^The bank says no: credit score too low%. Pay your instalments on time first$", "ธนาคารไม่อนุมัติ: เครดิตต่ำไป ผ่อนให้ตรงงวดก่อนนะ" },
	{ "^Credit score too low for 0%% down: put some money down$", "เครดิตไม่พอสำหรับดาวน์ 0% ลองวางเงินดาวน์ดูนะ" },
	{ "^Claim day (%d+) · (.+) %+ item$", "รับรางวัลวันที่ %1 · %2 + ไอเทม" }, { "^Claim day (%d+) · (.+)$", "รับรางวัลวันที่ %1 · %2" },
	{ "^Reward: (.+)$", function(a) return "รางวัล: " .. a:gsub(" · ([^·]+) ×(%d+)", function(x, y) return " · " .. n(x) .. " ×" .. y end) end },
	{ "^(.+) · (.+) tracks$", "%1 · %2 เพลง" },
	{ "^Plant at your allotment$", "ปลูกที่แปลงผักของคุณ" },
	-- mission descriptions ("<desc> · <progress>")
	{ "^Deliver (%d+) food orders? · (.+)$", "ส่งอาหาร %1 ออร์เดอร์ · %2" }, { "^Complete (%d+) passenger rides · (.+)$", "รับส่งผู้โดยสาร %1 ครั้ง · %2" },
	{ "^Drive (%d+) km · (.+)$", "ขับ %1 กม. · %2" }, { "^Earn ฿(%d+) from jobs · (.+)$", "หาเงิน ฿%1 จากงาน · %2" }, { "^Get (%d+) five%-star ratings · (.+)$", "ได้ห้าดาว %1 ครั้ง · %2" },
	{ "^Harvest (%d+) crops · (.+)$", "เก็บเกี่ยว %1 ครั้ง · %2" }, { "^Plant (%d+) crops · (.+)$", "ปลูกผัก %1 ครั้ง · %2" }, { "^Sell (%d+) crops · (.+)$", "ขายผลผลิต %1 ชิ้น · %2" },
	{ "^Water crops (%d+) times · (.+)$", "รดน้ำผัก %1 ครั้ง · %2" }, { "^Eat (%d+) meals · (.+)$", "กินอาหาร %1 มื้อ · %2" }, { "^Cook (%d+) meals at home · (.+)$", "ทำอาหารที่บ้าน %1 มื้อ · %2" },
	{ "^Place (%d+) pieces of furniture · (.+)$", "วางเฟอร์นิเจอร์ %1 ชิ้น · %2" }, { "^Buy (%d+) vehicle upgrades · (.+)$", "อัปเกรดรถ %1 ครั้ง · %2" },
	{ "^Buy a new vehicle · (.+)$", "ซื้อรถใหม่ · %1" }, { "^Buy a plot of land · (.+)$", "ซื้อที่ดิน · %1" },
}

---------------------------------------------------------------------------------------------------
-- units: run on everything in Thai mode
---------------------------------------------------------------------------------------------------
local function units(s: string): string
	if not s:find("%d") then return s end
	s = s:gsub("(%d) km/h", "%1 กม./ชม."):gsub("(%d) km", "%1 กม."):gsub("(%d) m(%f[%W])", "%1 ม.%2"):gsub("(%d) m$", "%1 ม.")
	s = s:gsub("(%d+)h (%d+)m", "%1 ชม. %2 นาที"):gsub("(%d+)m (%d+)s", "%1:%2"):gsub("(%d+)s(%f[%W])", "%1 วิ%2"):gsub("(%d+)s$", "%1 วิ")
	s = s:gsub("(%d) EXP", "%1 EXP"):gsub("(%d%.?%d*) L(%f[%W])", "%1 ลิตร%2")
	return s
end

local cache = {} :: { [string]: string }
local cacheN = 0

function Lang.t(s: any): any
	if Lang.code ~= "th" or type(s) ~= "string" or s == "" then return s end
	local hit = cache[s]
	if hit then return hit end
	local out = E[s] or N[s]
	if not out then
		if not s:find("%a") then
			out = s
		else
			for _, p in ipairs(P) do
				local caps = table.pack(s:match(p[1]))
				if caps[1] ~= nil then
					local rep = p[2]
					if type(rep) == "function" then
						out = rep(table.unpack(caps, 1, caps.n))
					else
						out = (rep:gsub("%%(%d)", function(i) return n(caps[tonumber(i)] or "") end):gsub("%%%%", "%%"))
					end
					break
				end
			end
			out = units(out or s)
		end
	end
	if cacheN > 4000 then cache = {}; cacheN = 0 end
	cache[s] = out
	cacheN += 1
	return out
end

-- Pick the English or Thai text directly (for new text written for this release).
function Lang.pick(en: string, th: string): string
	return Lang.code == "th" and th or en
end

---------------------------------------------------------------------------------------------------
-- automatic translation of GUI text
--   Each text object keeps its own state in a closure (Roblox instances must not be weak table
--   keys: an entry can vanish while the instance still lives). The registry below is strong and
--   drops an entry when its object is destroyed; it is only walked when the language changes.
---------------------------------------------------------------------------------------------------
-- Roblox draws Thai with a fallback face that comes out about a fifth smaller than the Latin
-- text around it, so Thai text gets a larger size (and a larger cap when it scales to fit).
local THAI = "\224[\184\185]" -- first two bytes of a Thai letter in UTF-8 (U+0E00..U+0E7F)
local THAI_SCALE = 1.2

local registry = {} :: { [Instance]: () -> () } -- object -> re-translate

local function hook(o: Instance)
	if not (o:IsA("TextLabel") or o:IsA("TextButton")) or registry[o] then return end
	local obj = o :: any
	local src, shown = nil :: string?, nil :: string?
	local base: number? = nil -- the owner's TextSize
	local written: number? = nil -- the TextSize we set
	local con: UITextSizeConstraint? = nil
	local conBase: number? = nil

	local function fitThai()
		local thai = string.find(obj.Text, THAI) ~= nil
		if not base then base = obj.TextSize end
		local want = thai and math.floor(base * THAI_SCALE + 0.5) or base
		if obj.TextSize ~= want then
			written = want
			obj.TextSize = want
		end
		local c = o:FindFirstChildOfClass("UITextSizeConstraint")
		if c ~= con then con = c; conBase = c and c.MaxTextSize or nil end
		if c and conBase then
			local wantMax = thai and math.floor(conBase * THAI_SCALE + 0.5) or conBase
			if c.MaxTextSize ~= wantMax then c.MaxTextSize = wantMax end
		end
	end

	local function apply(force: boolean?)
		if not o:GetAttribute("NoTranslate") then -- read each time: it may be set just after creation
			local cur = obj.Text
			if force or cur ~= shown then -- not our own write
				if not force then src = cur end
				local tr = Lang.t(src or cur)
				shown = tr
				if tr ~= cur then obj.Text = tr end
			end
		end
		fitThai()
	end

	registry[o] = function() apply(true) end
	apply(false)
	task.defer(fitThai) -- again once a fit-to-size constraint has been added
	o:GetPropertyChangedSignal("Text"):Connect(function() apply(false) end)
	o:GetPropertyChangedSignal("TextSize"):Connect(function()
		if obj.TextSize ~= written then
			base = obj.TextSize -- the owner changed the size: that is the new base
			fitThai()
		end
	end)
	o.Destroying:Connect(function() registry[o] = nil end)
end

-- A place or thing that carries both names ({ name, thai }): the one for the current language.
function Lang.name(obj: any): string
	if not obj then return "" end
	if Lang.code == "th" and obj.thai and obj.thai ~= "" then return obj.thai end
	return Lang.t(obj.name or "")
end

function Lang.watch(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do hook(d) end
	root.DescendantAdded:Connect(hook)
end

function Lang.set(code: string)
	if code ~= "th" and code ~= "en" then return end
	if code == Lang.code then return end
	Lang.code = code
	cache = {}
	cacheN = 0
	for o, redo in pairs(registry) do
		if o.Parent then redo() end
	end
	for _, fn in ipairs(listeners) do task.spawn(fn) end
end

-- Thai until the player picks a language (the Welcome card asks once); then their saved choice.
function Lang.start()
	local Players = game:GetService("Players")
	local State = require(script.Parent.State)
	Lang.watch(Players.LocalPlayer:WaitForChild("PlayerGui"))
	local function follow()
		local s = State.data and State.data.settings
		if s and s.langChosen and (s.lang == "en" or s.lang == "th") then Lang.set(s.lang) end
	end
	State.onData(function(keys) if keys.settings then follow() end end)
	follow()
end

return Lang
