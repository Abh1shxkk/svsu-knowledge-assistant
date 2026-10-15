# SVSU Assistant for Android

A Flutter app with the same features as the web app in `../frontend`. It talks to the same FastAPI
backend (`../backend`), so the backend doesn't change and the server keeps enforcing every role and
access rule.

By default it connects to the test deployment, `https://svsu.54-173-64-109.sslip.io/api`. To use
another server, tap the gear on the sign-in screen, or build with `--dart-define=API_URL=https://…/api`.

## Screens

The screens match the web app's: sign-in with two-step verification, Dashboard, Ask AI, Document
Library and document records, Upload (one by one and bulk), Review & Approvals, Collections, Actions &
Deadlines, Saved Chats & Bookmarks, Reports & Feedback, Administration and My profile. The menu shows
each person only the screens their role allows.

Where a phone works differently from a browser:

| Web | App |
|---|---|
| Hover a paragraph to bookmark it | Long-press the paragraph |
| Drag and drop files | Choose files, or **Take a photo** of a paper letter (read with OCR) |
| Bulk import: choose a folder | Choose many files at once (in the picker, long-press one file, then **Select all**) |
| Download Word / Print to PDF | Open or share the Word file, or share the summary as text |
| Download the original | Opens it in a PDF, Word or image app on the phone |
| Two-step setup: scan the QR code | Scan it from another device, or copy the key into an authenticator app on this phone |

## Run and build

You need the Flutter SDK, plus the Android SDK and JDK 17 (Android Studio includes both).

```bash
flutter pub get
flutter test                 # opens every screen against the sample data in ../backend/seed.json
flutter run                  # on a connected phone or an emulator
flutter build apk --release  # build/app/outputs/flutter-apk/app-release.apk
```

## Install (for staff)

Download the APK from the latest **android-v…** release on
[GitHub Releases](https://github.com/Abh1shxkk/svsu-knowledge-assistant/releases), open it on the phone and
allow "install unknown apps" when Android asks. Most phones from the last 8 years need the **arm64** file;
if it won't install, use the **universal** one. Sign in with the Login ID and password from your administrator.

When a newer version is published, the app says so on start and offers a download link.

## Publish a new version

1. Raise `version:` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.1.0+2`; the number after `+` must always go up).
2. Build, with the release key in place (below):
   ```bash
   flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 -P force-version-code-ignoring-abi=true
   flutter build apk --release -P force-version-code-ignoring-abi=true
   ```
   `force-version-code-ignoring-abi` keeps one version number for every APK, so a phone can switch
   between the arm64 and universal files and still update.
3. Create a GitHub release tagged `android-v1.1.0` and attach the three APKs from
   `build/app/outputs/flutter-apk/`. Installed apps find it by the `android-v` prefix.

## Release signing key

Android only installs an update if it is signed with the same key as the installed app. The key is
**not** in this repository:

- `D:\svsu-signing\svsu-release.jks`, with its password in `README.txt` next to it. Back this folder up
  somewhere safe. If it is lost, every phone has to uninstall and reinstall to get a new version.
- `android/key.properties` (ignored by git) points the build at it. Without that file, release builds
  are signed with the debug key, which is fine for CI and testing but not for giving to people.

## Layout

- `lib/api.dart`: the REST client, the same calls as `frontend/lib/api.ts`, with the token kept in the phone's secure storage.
- `lib/store.dart`: app state, roles and the search scope, ported from `frontend/lib/store.ts`.
- `lib/models.dart`: thin wrappers over the server's JSON. Saving a changed record sends back every field, including ones the app doesn't show.
- `lib/screens/`: one file per screen.
- `lib/widgets/`: shared pieces (answer view, document viewer, pages, dialogs, charts).
