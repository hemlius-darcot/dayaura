# DayAura ⚡ — Hardcore Focus & Digital Wellbeing Suite

<p align="center">
  <b>Uncompromised, Anti-Addiction Student Focus & Consistency Platform</b><br>
  Built with Flutter, Native Kotlin Services & Local-First Architecture.
</p>

---

## 🌟 Key Superpowers

1. **Floating Distraction Tracker**:
   - Draggable floating overlay that stays on screen across all apps.
   - 1-tap logging of social media distractions with mutual-exclusive pinned and recent chips.
   - Built-in overlay history viewer (`📜`).

2. **Hardcore Time Lock**:
   - **YouTube Shorts In-App Neutralizer**: Instantly kicks users out of YouTube Shorts feed while preserving educational long-form lectures.
   - **Chrome URL Filter**: Real-time address bar domain matching to neutralize distraction websites (`about:blank`).
   - **Anti-Uninstall & Anti-Tamper**: Device Administration protection (`<force-lock />`) preventing mid-session bypass.

3. **Financial-Grade Candlestick Consistency Charts**:
   - Visualizes daily study hours and routine execution as financial candlestick charts (Open, High, Low, Close).
   - Streak tracking, relapse counters, and consistency logs.

4. **1-Click Local Data Vault (Download & Upload)**:
   - 100% offline-first privacy. Users can export and restore their entire database with a single tap.

---

## 🛠️ Step-by-Step Android Studio Setup Guide

Follow these steps to set up, build, and run DayAura in Android Studio:

### 1. Prerequisites
- **Android Studio** (Hedgehog, Iguana, Jellyfish, or newer)
- **Flutter SDK** (v3.24+ recommended)
- **Android SDK** (API 34/35) & **JDK 17** (bundled inside Android Studio as JBR)

### 2. Open the Project in Android Studio
1. Launch Android Studio.
2. Select **Open** and browse to the `routine_app` directory.
3. Click **OK** and trust the project.

### 3. Configure Flutter & Dart SDKs
1. Go to **Settings** (`Ctrl + Alt + S` on Linux/Windows, `Cmd + ,` on macOS).
2. Under **Plugins**, verify that the **Flutter** and **Dart** plugins are installed.
3. Under **Languages & Frameworks -> Flutter**, verify that your **Flutter SDK path** is set.
4. Click **Apply**.

### 4. Configure JDK 17 for Gradle
1. Go to **Settings -> Build, Execution, Deployment -> Build Tools -> Gradle**.
2. Under **Gradle JVM**, select **Embedded JDK 17** (or Android Studio JBR).
3. Click **Apply** and **OK**.

### 5. Fetch Dependencies & Run
Open the built-in terminal (`Alt + F12`) in Android Studio and execute:

```bash
flutter pub get
```

To run on a connected Android device or emulator:
```bash
flutter run
```

---

## 📦 Building Signed Release APK

For official production builds:
```bash
flutter build apk --target-platform android-arm64 --release
```

*Note*: If `android/key.properties` is not present, the build system automatically falls back to default Android debug signing so contributors can build without configuration hurdles.

---

## 📄 License & Brand Attribution

DayAura is published under the **DayAura Public License (Attribution & Noncommercial with Advertising Integrity)**.
- See [LICENSE.md](LICENSE.md) for full terms.
- Commercial redistribution, trademark infringement, or tampering with the integrated sponsorship/advertisement delivery system is strictly prohibited.
