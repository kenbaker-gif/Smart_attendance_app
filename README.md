# 📱 Face Attend — Flutter Client (MVP)

![Flutter](https://img.shields.io/badge/Mobile-Flutter-blue?style=for-the-badge&logo=flutter)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Desktop-lightgrey?style=for-the-badge&logo=flutter)
![Status](https://img.shields.io/badge/Status-MVP-orange?style=for-the-badge)

Lightweight Flutter client that captures, compresses, and uploads face images to a separate verification backend. This repository contains only the mobile application — the verification backend (FastAPI + InsightFace + Supabase) is maintained in a separate repository.

**New Features (Latest Update):**
- 🔐 **Supabase Authentication** — Email/password login with session management
- 👆 **Biometric Login** — Fingerprint authentication support
- ⏱️ **Auto-Lock Security** — 2-minute inactivity timeout with soft-lock functionality
- 🔑 **Secure Credentials** — Environment variables via `.env` file
- 🚀 **OTA Updates** — Shorebird integration for over-the-air updates
- 🖥️ **Multi-Platform** — Support for Android, iOS, Web, Linux, macOS, and Windows

## Table of contents
- [Quickstart](#quickstart)
- [Configuration](#configuration)
- [Authentication](#authentication)
- [Security Features](#security-features)
- [Application Screens](#application-screens)
- [How it works](#how-it-works)
- [Development Scripts](#development-scripts)
- [CI/CD Pipeline](#cicd-pipeline)
- [OTA Updates](#ota-updates)
- [Platform Support](#platform-support)
- [Development notes](#development-notes)
- [Permissions](#permissions)
- [Contributing](#contributing)
- [License](#license)

---

## 🚀 Quickstart

Prerequisites
- Flutter SDK (project targets Dart SDK ^3.10.7 — see `pubspec.yaml`)
- Android SDK (or Xcode for iOS builds)
- For desktop builds: appropriate platform toolchain (Visual Studio for Windows, Xcode for macOS, etc.)

Run locally

```bash
# fetch dependencies
flutter pub get

# run on a connected device (use --release for realistic performance)
flutter run --release

# or run on specific platform
flutter run -d windows
flutter run -d macos
flutter run -d linux
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

### Configuration Management

The app uses `lib/config.dart` for centralized configuration management. This file handles:
- Environment variable loading
- API endpoint configuration
- Feature flags
- Platform-specific settings

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

### Signup Flow

New users can register through the signup screen (`lib/signup_screen.dart`):

1. **Navigate to Signup**: Tap "Create Account" on the login screen
2. **Enter Details**: Provide email and password
3. **Account Creation**: Supabase creates a new user account
4. **Automatic Login**: User is automatically logged in after successful registration
5. **Verification Screen**: User is taken directly to the attendance verification screen

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

The app uses `lib/session_gate_screen.dart` to manage session state:

- Sessions remain valid for authentication after the app is closed
- The login screen will show "Welcome Back" if a valid session exists
- On fingerprint unlock, the session is preserved
- Session gate checks authentication status before allowing access to protected screens

---

## ⏱️ Security Features

### Security Wrapper

The app implements a comprehensive security layer through `lib/security_wrapper.dart`:

- **Inactivity Detection**: Monitors user interaction across all screens
- **Background Monitoring**: Tracks when the app is backgrounded or foregrounded
- **Session Validation**: Ensures valid authentication before granting access
- **Automatic Lock**: Triggers soft-lock after timeout period

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

## 📱 Application Screens

### Core Screens

1. **Login Screen** (`lib/login_screen.dart`)
   - Email/password authentication
   - Biometric login option
   - "Welcome Back" message for existing sessions
   - Link to signup screen

2. **Signup Screen** (`lib/signup_screen.dart`)
   - New user registration
   - Email and password validation
   - Automatic login after successful registration

3. **Session Gate Screen** (`lib/session_gate_screen.dart`)
   - Session validation checkpoint
   - Redirects to login if session is invalid
   - Manages authentication state transitions

4. **Verification Screen** (`lib/verification_screen.dart`)
   - Camera interface for face capture
   - Image compression and upload
   - Real-time verification feedback
   - Attendance status display

5. **Admin Screen** (`lib/admin_screen.dart`)
   - Administrative functions
   - User management (if applicable)
   - System configuration

---

## 🧠 How it works

- **Capture**: the client uses the `camera` package to grab a single frame.
- **Compress**: `flutter_image_compress` resizes the image (recommended ~600×600px) and lowers quality to target ~50–100 KB for faster uploads on mobile networks.
- **Upload**: the compressed image is sent as a multipart/form-data POST to the verification backend.
- **Feedback**: the server's JSON response (authorized / denied) is shown on-screen.

Include the verification server's example request/response in the backend repo and link it here for full interoperability.

---

## 🛠️ Development Scripts

The `scripts/` directory contains automation scripts for common development tasks:

### build_lite.sh
Lightweight build script for quick testing:
```bash
./scripts/build_lite.sh
```
- Skips heavy optimizations
- Faster build times for development
- Suitable for testing on emulators

### full_rebuild.sh
Complete rebuild from scratch:
```bash
./scripts/full_rebuild.sh
```
- Cleans build artifacts
- Fetches fresh dependencies
- Performs full release build
- Use before production releases

### push_update.sh
Deploys OTA updates via Shorebird:
```bash
./scripts/push_update.sh
```
- Builds and pushes updates to Shorebird
- Enables over-the-air updates without app store submission
- See [OTA Updates](#ota-updates) section for details

### copy_to_drive.sh
Backup and distribution script:
```bash
./scripts/copy_to_drive.sh
```
- Copies build artifacts to specified location
- Useful for sharing builds with testers
- Can be configured for cloud storage integration

---

## 🔄 CI/CD Pipeline

### Codemagic Integration

The project uses Codemagic for continuous integration and deployment. Configuration is defined in `codemagic.yaml`:

**Features:**
- Automated builds on push/PR
- Multi-platform builds (Android, iOS, Web)
- Automated testing
- Release deployment to app stores
- Build artifact storage

**Setup:**
1. Connect your repository to Codemagic
2. Configure environment variables in Codemagic dashboard
3. Update `codemagic.yaml` with your specific build requirements
4. Push to trigger automated builds

**Build Triggers:**
- Push to `main` branch: Production builds
- Pull requests: Test builds
- Tagged releases: Store deployment

---

## 🚀 OTA Updates

### Shorebird Integration

The app supports over-the-air updates via Shorebird (`shorebird.yaml`):

**Benefits:**
- Deploy bug fixes without app store review
- Update UI and business logic instantly
- Reduce time-to-market for critical updates
- Maintain version control across deployments

**Configuration:**
```yaml
# shorebird.yaml
app_id: your_app_id_here
```

**Deploying Updates:**
```bash
# Using the provided script
./scripts/push_update.sh

# Or manually
shorebird patch android
shorebird patch ios
```

**Limitations:**
- Cannot update native code changes
- Cannot modify app permissions
- Best for Dart code and asset updates

---

## 🖥️ Platform Support

### Mobile Platforms

**Android** ✅ Fully Supported
- Minimum SDK: API 21 (Android 5.0)
- Target SDK: Latest
- Biometric authentication
- Camera access
- Full feature parity

**iOS** ✅ Fully Supported
- Minimum iOS: 12.0
- Face ID / Touch ID support
- Camera access
- Full feature parity

### Desktop Platforms

**Linux** 🟡 Experimental
- Basic functionality supported
- Camera support may vary by distribution
- Biometric authentication limited

**macOS** 🟡 Experimental
- Basic functionality supported
- Touch ID support available
- Camera access requires permissions

**Windows** 🟡 Experimental
- Basic functionality supported
- Windows Hello integration possible
- Camera access requires permissions

### Web Platform

**Web** 🟡 Limited Support
- Browser-based camera access
- No biometric authentication
- Network-dependent performance
- Best for testing and demos

**Note:** Desktop and web platforms are experimental. Mobile platforms (Android/iOS) are the primary targets and receive full testing and support.

---

## 🛠️ Development notes

- **Timeouts**: the app currently uses a 15s request timeout; adjust for your network conditions.
- **Camera preset**: `ResolutionPreset.medium` balances speed and accuracy on low-end devices.
- **Latency testing**: build with `--release` and test on real networks (3G/4G/Wi‑Fi) to measure true performance.
- **Configuration**: prefer environment or build-time flags over hard-coded URLs.
- **Platform testing**: Test on actual devices for each target platform before release.
- **Security**: Never commit `.env` file to version control.

---

## 🔒 Permissions

### Android

The app requests the following permissions in `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.USE_BIOMETRIC" />
```

### iOS

Add the following descriptions in `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required to capture face images for attendance verification.</string>

<key>NSFaceIDUsageDescription</key>
<string>Face ID is used for secure biometric authentication.</string>
```

### Desktop Platforms

Desktop platforms may require additional permissions configuration depending on the operating system. Refer to Flutter's platform-specific documentation for details.

---

## ⚠️ Known Issues

**502 Bad Gateway on first capture after server sleep**

If the verification server has been idle for ~10 minutes, it may enter sleep mode. When you capture the first face, you may receive a `502 Bad Gateway` error. This is expected — the server is waking up. Simply try the next verification and it should succeed.

**Desktop Platform Limitations**

- Camera access may require manual permission grants on some Linux distributions
- Biometric authentication is limited or unavailable on desktop platforms
- Performance may vary based on hardware capabilities

---

## 🤝 Contributing

- Open issues and pull requests are welcome.
- Run `flutter format .` before committing.
- Include a short video or screenshot for UI changes.
- Test on multiple platforms when possible.
- Update documentation for new features.

Consider adding `CONTRIBUTING.md` for PR process and code style guidelines.

---

## 📄 License

This project is open-source under the [MIT License](https://opensource.org/licenses/MIT). See [LICENSE](LICENSE) for the full text.

---

## 📧 Contact

Questions, feedback, or contributions? Reach out at **ainebyonabubaker@proton.me**

---

## 🔗 Related Repositories

**Backend Verification Service**

The server-side code (FastAPI + InsightFace + Supabase) is maintained separately:
**https://github.com/kenbaker-gif/Smart_attendance_mvp**

---

## 📂 Project Structure

```
Smart_attendance_app/
├── lib/                      # Main application code
│   ├── main.dart            # App entry point
│   ├── config.dart          # Configuration management
│   ├── login_screen.dart    # Login interface
│   ├── signup_screen.dart   # User registration
│   ├── session_gate_screen.dart  # Session validation
│   ├── security_wrapper.dart     # Security layer
│   ├── verification_screen.dart  # Face capture & verification
│   └── admin_screen.dart    # Admin functions
├── scripts/                 # Development automation
│   ├── build_lite.sh       # Quick build script
│   ├── full_rebuild.sh     # Complete rebuild
│   ├── push_update.sh      # OTA deployment
│   └── copy_to_drive.sh    # Build distribution
├── android/                 # Android platform code
├── ios/                     # iOS platform code
├── web/                     # Web platform code
├── linux/                   # Linux platform code
├── macos/                   # macOS platform code
├── windows/                 # Windows platform code
├── .env.example            # Environment template
├── codemagic.yaml          # CI/CD configuration
├── shorebird.yaml          # OTA update config
└── pubspec.yaml            # Dependencies
```
