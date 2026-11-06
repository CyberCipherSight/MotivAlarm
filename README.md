# MotivAlarm

An Android alarm clock that plays a selected local video when an alarm rings.
Built with Flutter and a native Kotlin alarm engine.

## Features

- Video alarms with repeat days, snooze, vibration, and optional backup audio.
- Fallback system audio when selected media is unavailable.
- Alarm previews, stopwatch, countdown timer, interval sessions, and a daily timetable.
- Local backup and restore.

## Development

Use Flutter with Dart 3.11.1 or later, Java 17, and the Android SDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

The Android SDK and Flutter SDK paths belong in the untracked
`android/local.properties` file. Flutter can generate this during setup.

Flutter provides configuration screens. Native Android components handle
scheduling, background ringing, notifications, and video playback. In-app
video previews use native VideoView with Flutter hybrid composition.

## Release signing

No signing keys, signing passwords, personal configuration, or user media are
included in this repository. Create your own keystore for your own app.
Create an untracked `android/key.properties` file with these entries:

```properties
storeFile=/absolute/path/to/your/upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

```sh
flutter build appbundle --release
```

The resulting bundle is `build/app/outputs/bundle/release/app-release.aab`.
A release build without `key.properties` uses the debug signing fallback and
must not be submitted to Google Play. Verify signing before distribution.
For a separately published fork, use your own Android application ID.

## Android permissions

Alarm reliability depends on notification, exact alarm, full-screen alarm,
and battery settings. Some manufacturers require additional background and
lock-screen permissions. The app explains these during onboarding.

## License

Apache License 2.0. See [LICENSE](LICENSE).
