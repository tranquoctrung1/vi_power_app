# Setup hướng dẫn

## Bước 1 — Tạo Firebase project

1. Vào https://console.firebase.google.com
2. "Create project" → đặt tên → tiếp tục
3. Enable Google Analytics (tùy chọn)

## Bước 2 — Thêm Android app vào Firebase

1. Firebase Console → Project settings → "Add app" → Android
2. Package name: `com.example.webview_push_app`
3. Download `google-services.json`
4. Copy vào: `android/app/google-services.json`

## Bước 3 — Thêm iOS app vào Firebase (nếu cần)

1. Firebase Console → "Add app" → iOS
2. Bundle ID: `com.example.webviewPushApp`
3. Download `GoogleService-Info.plist`
4. Copy vào: `ios/Runner/GoogleService-Info.plist`

## Bước 4 — Enable Cloud Messaging

Firebase Console → Project settings → Cloud Messaging → Bật FCM

## Bước 5 — Cập nhật firebase_options.dart

Cách nhanh nhất dùng FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=YOUR_PROJECT_ID
```

Lệnh này tự sinh file `lib/firebase_options.dart` chính xác.

## Bước 6 — Chạy app

```bash
cd C:\Users\tranq\webview_push_app
flutter pub get
flutter run
```

## Test push notification

Lấy FCM token từ console log khi app chạy, rồi gửi test qua:

```bash
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "DEVICE_FCM_TOKEN",
    "notification": {
      "title": "Test",
      "body": "Hello từ server!"
    }
  }'
```

Server key lấy tại: Firebase Console → Project settings → Cloud Messaging → Server key
