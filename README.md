摩ㄒㄧㄥ# Lecture Vault

Lecture Vault is a Flutter app for recording lectures, transcribing speech, and generating study notes. It supports local extractive summaries by default, optional Android local LLM summaries, Google sign-in/Drive integration, and bundled or locally downloaded speech/LLM model assets.

## Install with OpenCode

Paste this prompt into OpenCode from the folder where you want the project installed:

```text
Clone the Lecture Vault app from https://github.com/resoak/app.git into a folder named lecture_vault, check out the main branch, run flutter pub get, then verify the install with flutter analyze. If Flutter is not installed, tell me the exact Flutter install steps for my OS before running the project. Do not commit or push anything from my machine.
```

After OpenCode finishes, run the app from the cloned folder:

```bash
cd lecture_vault
flutter run
```

For Google sign-in or Drive access, pass the OAuth IDs when running Flutter:

```bash
flutter run \
  --dart-define=GOOGLE_CLIENT_ID=your-android-or-ios-client-id \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=your-web-client-id
```

## Install with git

Prerequisites:

- Flutter SDK `>=3.3.0 <4.0.0`
- Git
- Android Studio / Android SDK for Android builds, or Xcode for iOS builds
- A configured device or emulator

Clone with HTTPS:

```bash
git clone https://github.com/resoak/app.git lecture_vault
cd lecture_vault
git checkout main
flutter pub get
flutter analyze
flutter run
```

Clone with SSH:

```bash
git clone git@github.com:resoak/app.git lecture_vault
cd lecture_vault
git checkout main
flutter pub get
flutter analyze
flutter run
```

## Model assets

Large model files are intentionally handled with Git LFS or local downloads.

- Whisper `ggml-base.bin` and `ggml-small.bin` belong in
  `assets/models/whisper/` and are tracked through Git LFS when committed.
- Android local LLM `.gguf` files are excluded from git; the app can download supported LLM models from Settings.
- If no local LLM model is available, Lecture Vault falls back to the built-in extractive summary method.

After cloning, make sure Git LFS is installed and pull LFS assets:

```bash
git lfs install
git lfs pull
```

If the Whisper models have not been committed through Git LFS yet, download them locally:

```powershell
.\scripts\download_whisper_models.ps1
```

The repository includes placeholder model directories so fresh clones can run `flutter pub get` and build without manually creating folders.

## Useful build commands

```bash
flutter pub get
flutter analyze
flutter build apk --release
flutter build web --release
```

## Google sign-in notes

The Android package name is currently `com.example.lecture_vault`. Configure the same package name and signing SHA-1 in Google Cloud or Firebase. If you use Firebase, make sure `android/app/google-services.json` matches the package name and SHA-1 used on the installed app.
