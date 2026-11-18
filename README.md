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

## 🔓 Open-Source Emergency Unlock Formula

To ensure 100% user autonomy, this Community Edition allows users to emergency-unlock active Time Lock sessions without needing any external developer keys:

### Mathematical Formula:
$$\text{Passcode} = \text{First 6 digits of } (567673 \times \text{Exact 12-Hour Clock Time})$$

### How to Calculate:
1. Look at your phone's current 12-hour clock:
   - **Example 1**: If it's **12:00** (AM or PM), the time integer is `1200`.
     $$567673 \times 1200 = 681207600 \implies \mathbf{681207}$$
   - **Example 2**: If it's **3:43** (AM or PM), the time integer is `343`.
     $$567673 \times 343 = 194711839 \implies \mathbf{194711}$$
2. Enter the resulting 6-digit code into the Unlock Dialog to unlock immediately.

---

## 🛡️ 100% Privacy & Zero-Cloud Guarantee

- **Zero Ads**: 100% ad-free, distraction-free study experience.
- **Zero Cloud Dependence**: 100% offline-first. Does not connect to any external cloud database or server.
- **Local SQLite / JSON Storage**: All routine, distraction, and consistency logs reside strictly on your own device.

---

## 📄 License & Brand Attribution

DayAura is published under the **DayAura Public License (Attribution & Noncommercial with Advertising Integrity)**.
- See [LICENSE.md](LICENSE.md) for full terms.
- Commercial redistribution, trademark infringement, or tampering with the integrated sponsorship/advertisement delivery system is strictly prohibited.
