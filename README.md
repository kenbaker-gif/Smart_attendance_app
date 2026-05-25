# 📱 Smart Attendance — Flutter Client (MVP)

![Flutter](https://img.shields.io/badge/Mobile-Flutter-blue?style=for-the-badge&logo=flutter)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey?style=for-the-badge&logo=android)
![Status](https://img.shields.io/badge/Status-MVP-orange?style=for-the-badge)

Lightweight Flutter client that captures, compresses, and uploads face images to a separate verification backend. This repository contains only the mobile application — the verification backend (FastAPI + InsightFace + Supabase) is maintained in a separate repository.

**New Features (Latest Update):**
- 🔐 **Supabase Authentication** — Email/password login with session management
- 👆 **Biometric Login** — Fingerprint authentication support
- ⏱️ **Auto-Lock Security** — 2-minute inactivity timeout with soft-lock functionality
- 🔑 **Secure Credentials** — Environment variables via `.env` file

## Table of contents
- [Quickstart](#quickstart)
- [Configuration](#configuration)
- [Authentication](#authentication)
- [Security Features](#security-features)
- [How it works](#how-it-works)
- [Development notes](#development-notes)
- [Permissions](#permissions)
- [Contributing](#contributing)
- [License](#license)

---

## 🚀 Quickstart

Prerequisites
- Flutter SDK (project targets Dart SDK ^3.10.7 — see `pubspec.yaml`)
- Android SDK (or Xcode for iOS builds)

Run locally

```bash
# fetch dependencies
flutter pub get

# run on a connected device (use --release for realistic performance)
flutter run --release
```

This launches the app on the attached device or emulator. Note: the verification API is not included in this repo — the app posts images to an external verification service.

---

## ⚙️ Configuration

### Supabase Setup

Create a `.env` file in the project root with your Supabase credentials:

```env
SUPABASE_URL=https://your-supabase-project.supabase.co
SUPABASE_ANON_KEY=your_anon_key_here
GOOGLE_WEB_CLIENT_ID=your_google_web_client_id_here
API_URL=https://your-api.example.com
```

Copy the example file locally before you run the app:

```bash
cp .env.example .env
```

> Note: `.env` is used for local development only. It is not packaged as an app asset, so secrets are not bundled into release builds.
>
> `lib/main.dart` loads this file at startup with `dotenv.load(fileName: ".env")`.

A sample file is provided as `.env.example` so you can copy it locally and fill in your own values.

Get these values from your Supabase project settings.

### API Endpoint

The app posts face images to a verification backend. Update the API endpoint in `lib/verification_screen.dart`:

```dart
var request = http.MultipartRequest(
  'POST',
  Uri.parse('https://your-backend-api.example.com/verify')
);
```

Replace `https://your-backend-api.example.com/verify` with your actual backend URL.

---

## 🔐 Authentication

### Login Flow

1. **First Login**: User enters email and password
2. **Session Created**: Supabase authentication creates a session token
3. **Access Granted**: User is taken to the verification screen

### Biometric Unlock

If the device supports fingerprint/biometric authentication:

- A fingerprint button appears on the login screen
- Tap to authenticate with your device's biometric sensor
- **Note**: Biometric unlock only works if a valid session already exists (user must log in with password first)

### Session Management

- Sessions remain valid for authentication after the app is closed
- The login screen will show "Welcome Back" if a valid session exists
- On fingerprint unlock, the session is preserved

---

## ⏱️ Security Features

### Auto-Lock (Soft Lock)

- **Trigger**: 2-minute inactivity timeout or app backgrounding for >2 minutes
- **Behavior**: User is returned to login screen, but session remains valid
- **Unlock**: Fingerprint authentication (if available) or password re-entry
- **Purpose**: Prevents unauthorized access without losing the session

### Manual Logout (Hard Logout)

- **Trigger**: Clicking the red logout button (⬅️ icon, top-left)
- **Behavior**: Completely destroys the Supabase session
- **Effect**: User must log in again with email/password
- **Purpose**: Secure logout for shared or public devices

---

## 🧠 How it works

- Capture: the client uses the `camera` package to grab a single frame.
- Compress: `flutter_image_compress` resizes the image (recommended ~600×600px) and lowers quality to target ~50–100 KB for faster uploads on mobile networks.
- Upload: the compressed image is sent as a multipart/form-data POST to the verification backend.
- Feedback: the server's JSON response (authorized / denied) is shown on-screen.

Include the verification server's example request/response in the backend repo and link it here for full interoperability.

---

## 🛠️ Development notes

- Timeouts: the app currently uses a 15s request timeout; adjust for your network conditions.
- Camera preset: `ResolutionPreset.medium` balances speed and accuracy on low-end devices.
- Latency testing: build with `--release` and test on real networks (3G/4G/Wi‑Fi) to measure true performance.
- Configuration: prefer environment or build-time flags over hard-coded URLs.

---

## 🔒 Permissions

On Android, the app requests the following permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
```

For iOS, add the following descriptions in `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to capture face images for attendance verification.</string>

<key>NSFaceIDUsageDescription</key>
<string>Face ID is used for secure biometric authentication.</string>
```

---

## ⚠️ Known Issues

**502 Bad Gateway on first capture after server sleep**

If the verification server has been idle for ~10 minutes, it may enter sleep mode. When you capture the first face, you may receive a `502 Bad Gateway` error. This is expected — the server is waking up. Simply try the next verification and it should succeed.

---

## 🤝 Contributing

- Open issues and pull requests are welcome.
- Run `flutter format .` before committing.
- Include a short video or screenshot for UI changes.

Consider adding `CONTRIBUTING.md` for PR process and code style guidelines.

---

## 📄 License

This project is open-source under the [MIT License](https://opensource.org/licenses/MIT). See [LICENSE](LICENSE) for the full text.

---

## 📧 Contact

Questions, feedback, or contributions? Reach out at **ainebyonabubaker@proton.me**



**Missing backend reference**
The server-side code (FastAPI + InsightFace + Supabase) is in this repo: **https://github.com/kenbaker-gif/Smart_attendance_mvp**

**Contributing**
- Open issues and PRs are welcome. Please run `flutter format` and include a short description of platform/test steps for UI changes.