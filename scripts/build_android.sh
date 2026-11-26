#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="$HOME/development/flutter/bin:$HOME/Android/Sdk/cmdline-tools/latest/bin:$HOME/Android/Sdk/platform-tools:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"

echo "Running static analysis and tests..."
flutter pub get
flutter analyze
flutter test

echo "Building universal release APK..."
flutter build apk --release

mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/WhatIsThat-Android.apk
echo "Created: $ROOT_DIR/dist/WhatIsThat-Android.apk"
ls -lh dist/WhatIsThat-Android.apk
