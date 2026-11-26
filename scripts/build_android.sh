#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ -x "$HOME/development/jdk-21/bin/javac" ]; then
  export JAVA_HOME="$HOME/development/jdk-21"
  export PATH="$JAVA_HOME/bin:$PATH"
elif [ -x "/usr/lib/jvm/java-21-openjdk-amd64/bin/javac" ]; then
  export JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
  export PATH="$JAVA_HOME/bin:$PATH"
elif [ -x "/usr/lib/jvm/java-17-openjdk-amd64/bin/javac" ]; then
  export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

export PATH="$HOME/development/flutter/bin:$HOME/Android/Sdk/cmdline-tools/latest/bin:$HOME/Android/Sdk/platform-tools:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"

echo "Using Java: $(java -version 2>&1 | head -n 1)"
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
