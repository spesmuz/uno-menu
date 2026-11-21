# UNO Airways Restaurante — raqamli menyu

Restoran planshetlari uchun menyu va admin panel. Bitta APK ichida ishlaydi.

- **Menyu sahifasi:** `index.html`. GitHub Pages orqali ochiladi.
- **Ma'lumotlar, rasm va videolar:** Supabase'da (`uno_docs` jadvali, `uno-media` ombori).
- **Admin panel:** menyudagi logotipni 3 soniya bosib turing → login va parol.
- **O'zgarishlar:** admin paneldagi har bir o'zgarish barcha planshetlarda bir zumda yangilanadi (Realtime).

## Bir martalik sozlash

1. **Supabase → SQL Editor:** `setup.sql` faylini to'liq joylab, **Run** bosing.
2. **Supabase → Authentication → Users → Add user → Create new user:**
   - Email: `admin@uno.local`
   - Parol: o'zingiz tanlang
   - **Auto Confirm User** belgilansin.

   Admin panelda login sifatida `admin` va shu parol kiritiladi.
3. **Supabase → Authentication → Sign In / Providers:** "Allow new users to sign up" o'chirilsin. Bu tavsiya etiladi.
4. **GitHub → Settings → Pages:**
   - Source: *Deploy from a branch*
   - Branch: `main`, papka `/ (root)` → **Save**
5. **GitHub → Settings → Secrets and variables → Actions → New repository secret:** nomi `KEYSTORE_B64`, qiymati ilovaning imzo kaliti (base64). Bu kalitsiz APK yig'ilmaydi.
6. **APK:** https://github.com/spesmuz/uno-menu/releases/download/apk/UNO-Airways.apk (har yig'ishda yangilanadi).

## Yangilash

- **Menyu kodi:** `index.html` o'zgartirilsa, planshetlar keyingi ochilishda yangisini oladi. APK'ni qayta o'rnatish shart emas.
- **Taomlar, narxlar, rasmlar:** admin panel orqali o'zgartiriladi.
- **APK yangilanishi:** barcha APK'lar `KEYSTORE_B64` kaliti bilan imzolanadi, shuning uchun yangisi eskisining ustiga o'rnatiladi.

## Kiosk rejimi (mijoz ilovadan chiqa olmaydi)

**1-daraja: avtomatik.**
- Ilova ekranga mahkamlanadi (screen pinning) va bosh ekran (launcher) bo'lib ishlaydi.
- Birinchi ochilishda Android "bosh ekran ilovasini tanlang" deb so'rasa: **UNO Airways → Har doim**.
- Planshetga ekran qulfi PIN-kodini qo'ying. *Sozlamalar → Xavfsizlik → Ilovani mahkamlash* bo'limida "Yechishdan oldin PIN so'rash" yoqilgan bo'lsin.

**2-daraja: to'liq kiosk (qurilma egasi).** Bu rejimda hech qanday tugma yoki tugmalar birikmasi bilan chiqib bo'lmaydi, bildirishnomalar pardasi ham o'chadi. Har bir planshetda bir marta, kompyuter orqali bajariladi:
1. Planshetda Google va boshqa barcha hisoblarni o'chiring (*Sozlamalar → Hisoblar*).
2. *Sozlamalar → Planshet haqida* bo'limida "Build raqami" ustiga 7 marta bosing, so'ng *Dasturchi sozlamalari → USB orqali tuzatish* ni yoqing.
3. Kompyuterga [Android platform-tools](https://developer.android.com/tools/releases/platform-tools) yuklang, planshetni USB bilan ulang va quyidagi buyruqni bajaring:
   ```
   adb shell dpm set-device-owner uz.uno.airways/.AdminReceiver
   ```
4. "Success" chiqqach, ilovani oching. Endi hisoblarni qayta qo'shsangiz ham bo'ladi.

**Yashirin chiqish:** logotipni 3 soniya bosib turing yoki 7 marta bosing → admin login → *Planshet (kiosk rejimi)*:
- **Ilovadan chiqish (vaqtincha)** — ilova yopiladi. Uy tugmasi bosilsa yoki planshet qayta yoqilsa, menyu yana ochiladi.
- **Kiosk rejimini butunlay o'chirish** — ikki marta bosiladi. Ilova oddiy ilovaga aylanadi va uni o'chirib tashlash mumkin bo'ladi.

## Ofitsiant chaqiruvi va hisob so'rash

1. **Supabase → SQL Editor:** `calls.sql` faylini ishga tushiring (bir marta).
2. **Stol raqami:**
   - mijoz telefoni uchun stoldagi QR-kod (admin panel → *Stollar, xizmat haqi va QR-kodlar* → *QR-kodlarni chop etish*);
   - planshet uchun admin panelda *Shu planshetning stol raqami*.
3. **Ofitsiant telefoni:** https://github.com/spesmuz/uno-menu/releases/download/apk/UNO-Ofitsiant.apk
   - chaqiruv kelganda budilnikdek jiringlaydi va tebranadi, "Qabul qildim" bosilguncha to'xtamaydi;
   - birinchi ochilishda "batareyani tejash" cheklovidan chiqarishga ruxsat bering, ilova fonda ishlashi uchun.
   - iPhone yoki kompyuterda: https://spesmuz.github.io/uno-menu/ofitsiant.html (sahifa ochiq turganda ovoz chiqaradi).

## Sun'iy intellekt: kaloriyani suratdan hisoblash (Gemini)

1. **Supabase → SQL Editor:** `ai.sql` ni ishga tushiring (bir marta).
2. **Kalit:** https://aistudio.google.com/apikey → **Create API key** (bepul).
3. **Admin panel → "Sun'iy intellekt (AI)":** kalitni joylab, **Saqlash** ni bosing.
4. **Ishlatish:**
   - taomga surat yuklanganda AI kaloriya, oqsil, yog', uglevod va tarkibni (uch tilda) o'zi yozadi, so'ng **Saqlash** bosiladi;
   - **"Suratli barcha taomlarni hisoblash"** hammasini ketma-ket hisoblab, saqlaydi. Qo'lda kiritilgan qiymatlarga tegilmaydi.

## Xodimlar davomati
1. Supabase → SQL Editor: `attendance.sql` ni ishga tushiring.
2. Admin panel → «Xodimlar davomati» → «Xodimlar»: xodim, PIN-kod (4 raqam), smena va ish kunlarini kiriting.
3. Eshik yonidagi telefonda ilovani oching → admin panel → «Sozlamalar va terminal» → «Shu telefonni eshik terminali qilish».
   O'sha telefon endi faqat `davomat.html` (PIN klaviatura + old kamera surati) ni ko'rsatadi. Admin panelga kirish: logotipni 3 soniya bosib turish yoki 7 marta bosish.
4. Kelish/ketish, kechikish va «hali kelmadi» xabarlari Telegram guruhga boradi. Hisobot va Excel — «Hisobot» bo'limida.

## iPhone ilovasi (App Store)
- Kod: `ios/` (Swift, SwiftUI). Menyu (sayt), Bron (Telegram guruhga boradi), UNO (biz haqimizda).
- Yig'ish: `.github/workflows/ios.yml` — natija va skrinshotlar `ios-ci` branchida.
- Bron uchun Supabase'da bir marta `bookings.sql` ni ishga tushiring.
- App Store'ga yuklash uchun repo Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`.
- Maxfiylik siyosati: `privacy.html`.
