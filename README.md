Pocket Option Simulator (Flutter)
================================

هذا مشروع تعليمي لتطبيق محاكاة تداول بسيط (Pocket Option Simulator) يعتمد على EMA crossover.
يعمل على Android و iOS باستخدام Flutter.

ملفات مهمة:
- lib/main.dart   -> الكود الرئيسي للتطبيق
- pubspec.yaml    -> التبعيات

تشغيل محلي (بعد تثبيت Flutter):
1. انسخ المشروع:
   cd pocket_sim_flutter
2. احصل على الحزم:
   flutter pub get
3. شغّل على جهاز متصل أو محاكي:
   flutter run

بناء APK (Android):
flutter build apk --release

ملاحظة هامة:
- التطبيق محاكاة فقط ولا يتصل بأي منصة تداول.
- يستخدم Yahoo Finance endpoint المجاني لجلب أسعار EURUSD; قد يتغير الوصول مستقبلاً.