# ช่วยกันทำ GoDash / Contributing

ภาษาไทยก่อน English below.

## ขั้นตอน

1. ดึงล่าสุดก่อนเริ่มทุกครั้ง: `git checkout main && git pull`
2. แตก branch ต่อหนึ่งเรื่อง: `git checkout -b fix/red-light-grace` หรือ `feat/new-job-...`
3. แก้ไฟล์ใน `src/` (หรือ `tools/`, `docs/`) แล้วทดสอบในเครื่อง:
   `python -I tools/build_place.py` แล้วเปิด `GoDash.rbxlx` ใน Roblox Studio กด Play
   (ไฟล์ในเครื่องใช้ของแทนแบบเรียบ ๆ และไม่เซฟความคืบหน้า เป็นเรื่องปกติ)
4. Push branch แล้วเปิด Pull Request เข้า `main` เขียนว่าแก้อะไร ทดสอบอะไรแล้ว อะไรยังไม่ได้ทดสอบ
5. ทุก PR จะมีตัวตรวจ **Luau syntax** รันบน GitHub ให้อัตโนมัติ ถ้าขึ้นแดงให้แก้ก่อนขอ merge
6. เจ้าของเกมรีวิวแล้ว merge ภายในราวหนึ่งนาที ระบบ **auto sync** บนเครื่องเจ้าของเกมจะเอาสคริปต์ที่เปลี่ยนเข้า Studio เอง
   (`tools/autosync.py` + ปลั๊กอิน `tools/studio_plugin/GoDashAutoSync.lua`) จากนั้นเจ้าของเกมทดสอบแล้วกด Publish
   ผู้เล่นจะได้ของใหม่หลังกด Publish เท่านั้น

## กติกา

- ข้อความที่ผู้เล่นเห็นต้องมีภาษาไทย ใส่ในตารางของ `src/client/Lang.luau` หรือส่ง `th` มากับ toast
- ตัวเลขปรับสมดุลอยู่ใน `src/shared/Config/*` อย่าฝังตัวเลขในโค้ด service
- ค่าปรับหรือการหักเงินลงโทษทุกแบบต้องผ่าน `Fines.charge` (`src/server/Services/FineService.luau`) เพื่อให้เพดานต่อวันทำงาน
- ห้ามใช้ยี่ห้อจริง ราชวงศ์ ศาสนา หรือบุคคลจริง วัดเป็นฉากหลังได้เท่านั้น
- ของที่เอามาจากที่อื่นต้องเป็น CC0 หรือมีสิทธิ์ใช้เชิงพาณิชย์ชัดเจน และต้องจดลง `docs/ASSETS.md`
- ห้ามแก้ไฟล์แผนที่ที่สร้างอัตโนมัติด้วยมือ (`src/shared/Config/Maps/KhonKaenData/*`) ให้รัน `tools/plan_streets.py`
- ห้ามย้ายแปลงที่ดินใน `data/sites.json` เพราะผู้เล่นซื้อไปแล้ว และห้ามเปลี่ยนจุดอ้างอิงแผนที่ LAT0/LON0
- ห้ามใส่ API key, cookie หรือรหัสผ่านลง repo เพราะ repo นี้เป็น public
- โค้ด Luau ย่อหน้าด้วย tab ใส่คอมเมนต์อธิบาย "ทำไม" สำหรับกติกาเกมที่ไม่ชัด

## ทดสอบใน Studio

- ตั้ง `workspace:SetAttribute("QaMute", true)` ก่อนกด Play เพื่อปิดเสียง
- Studio ใช้ data store `GoDash_Profiles_v1_Studio` ไม่แตะข้อมูลผู้เล่นจริง
- ตัวช่วยทดสอบ (`Qa*` attributes) อธิบายไว้ใน `docs/OVERHAUL.md` ลบออกให้หมดก่อนเซฟ place

---

## Workflow (English)

1. `git checkout main && git pull` before you start.
2. One branch per topic (`fix/...`, `feat/...`).
3. Change `src/` (or `tools/`, `docs/`); test with `python -I tools/build_place.py` + Studio Play.
4. Open a PR into `main`: what changed, what you tested, what is NOT TESTED. The Luau syntax check must be green.
5. The owner reviews and merges. Auto sync puts the changed scripts into the Roblox place within about a minute;
   the owner tests and publishes.

Rules: Thai text for everything a player sees (`src/client/Lang.luau`); tuning lives in `src/shared/Config`;
every money penalty goes through `Fines.charge`; no real brands, royals, religion or real people; CC0 or
commercial-use assets only, logged in `docs/ASSETS.md`; never hand-edit generated map data, move player plots
or change LAT0/LON0; no secrets in this public repo.
