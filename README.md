# אפליקציית לחצן מצוקה – Flutter

## הרצה
```bash
flutter pub get
flutter run
```

## בניית APK להפצה
```bash
flutter build apk --release
```

הקובץ יופיע בדרך כלל ב:
`build/app/outputs/flutter-apk/app-release.apk`

## חשוב
האפליקציה משדרת TCP אל ה-IP וה-Port שהוזנו ומבנה הודעת SIA DC-09 ADM-CID עבור Contact ID 120.

לפני שימוש מבצעי יש לבדוק את הפורמט מול ה-ARC/Receiver שלך. ייתכן שהמקלט דורש ערכי Receiver/Line אחרים, ACK/Retry, TLS/הצפנה או הגדרות DC-09 ספציפיות.
