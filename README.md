# Shaxmat ilovasi

Kompyuter (Windows) va Android uchun bitta Flutter kodi + Node.js server.

```
chess-app/
├── app/      Flutter ilova (registratsiya, kod tasdiqlash, shaxmat doskasi)
├── server/   Node.js server (telefon orqali kirish, foydalanuvchilar bazasi)
└── .github/workflows/build.yml   APK va Windows dasturini avtomatik yig'ish
```

## 1. Serverni ishga tushirish

Node.js 20+ kerak.

```bash
cd server
npm install
npm start
```

Server `http://localhost:3000` da ishlaydi. SMS provayder ulanmagan bo'lsa **test rejimi**
yoqilgan: bir martalik kod serverda yaratiladi va ilovada ekranda ko'rinadi.

Haqiqiy serverda albatta `JWT_SECRET` ni o'rnating:

```bash
JWT_SECRET="uzun-tasodifiy-satr" SMS_PROVIDER=http SMS_API_URL=... SMS_API_TOKEN=... npm start
```

SMS provayderni ulash uchun faqat `server/src/sms.js` dagi `sendViaHttp` funksiyasini
provayderingiz formatiga moslang.

## 2. Ilovani ishga tushirish (kompyuterda sinash)

Flutter SDK kerak: https://docs.flutter.dev/get-started/install

```bash
cd app
flutter create --platforms=windows,android --project-name chess_app .
flutter pub get
flutter run -d windows
```

`flutter create` platforma papkalarini (`windows/`, `android/`) yaratadi, mavjud `lib/` va
`pubspec.yaml` ga tegmaydi. Server boshqa manzilda bo'lsa:

```bash
flutter run -d windows --dart-define=API_URL=https://sizning-server.uz
```

Android emulyatorida kompyuterdagi serverga `http://10.0.2.2:3000` orqali ulaniladi.

## 3. Tayyor APK va .exe olish

**GitHub Actions orqali (Flutter o'rnatmasdan):**
1. Papkani GitHub'ga yuklang.
2. Actions → "Build app" → Run workflow, server manzilini kiriting.
3. Tugagach, "Artifacts" dan `shaxmat-android-apk` va `shaxmat-windows` ni yuklab oling.

**Kompyuterda:**
```bash
flutter build apk --release --dart-define=API_URL=https://sizning-server.uz
flutter build windows --release --dart-define=API_URL=https://sizning-server.uz
```

## Hozir nimalar bor (1-bosqich)

- Registratsiya oynasi: til (uz/ru/en), kunduzgi/tungi rejim, telefon raqami, "Keyingi" tugmasi
- Kod oynasi: bir martalik kod, tasdiqlash, qayta yuborish (60 soniyadan keyin)
- Asosiy oyna: klassik shaxmat doskasi, qoidalar bo'yicha yurishlar, yangi o'yin, yurishni qaytarish
- Server: foydalanuvchilar bazasi (SQLite), kod tekshirish, kirish tokeni (90 kun)

## Keyingi bosqichlar

Reyting, kun/hafta/oy bo'yicha vaqt statistikasi, bo'limlar kesimida sarflangan vaqt,
uy vazifalari va tasklar, onlayn o'yin.
