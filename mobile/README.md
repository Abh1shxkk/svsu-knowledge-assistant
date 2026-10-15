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

Release builds are currently signed with the debug key, which is fine for installing directly on
phones. To publish on Google Play, create an upload key and set `signingConfig` in
`android/app/build.gradle.kts`.

## Layout

- `lib/api.dart`: the REST client, the same calls as `frontend/lib/api.ts`, with the token kept in the phone's secure storage.
- `lib/store.dart`: app state, roles and the search scope, ported from `frontend/lib/store.ts`.
- `lib/models.dart`: thin wrappers over the server's JSON. Saving a changed record sends back every field, including ones the app doesn't show.
- `lib/screens/`: one file per screen.
- `lib/widgets/`: shared pieces (answer view, document viewer, pages, dialogs, charts).
