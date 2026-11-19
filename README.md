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
5. **GitHub → Actions → "APK yig'ish" → Run workflow.** 2–3 daqiqadan keyin pastdagi *Artifacts* bo'limidan `UNO-Airways-APK` yuklab olinadi.

## Yangilash

- **Menyu kodi:** `index.html` o'zgartirilsa, planshetlar keyingi ochilishda yangisini oladi. APK'ni qayta o'rnatish shart emas.
- **Taomlar, narxlar, rasmlar:** admin panel orqali o'zgartiriladi.
- **APK yangilanishi:** yangi APK eskisining ustiga o'rnatilishi uchun bir xil imzo kerak. Buning uchun `KEYSTORE_B64` nomli GitHub secret qo'shing. U bo'lmasa, har yig'ishda yangi imzo yaratiladi va yangi APK'dan oldin eskisini o'chirish kerak bo'ladi.
