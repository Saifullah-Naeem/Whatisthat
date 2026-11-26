#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export PATH="$HOME/development/flutter/bin:$PATH"

if ! command -v clang++ >/dev/null 2>&1; then
  echo "Error: clang++ is required to build Flutter Linux desktop apps."
  echo "Install dependencies on Ubuntu/Debian with: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev"
  exit 1
fi

if ! pkg-config --exists gstreamer-1.0 gstreamer-app-1.0 gstreamer-video-1.0; then
  echo "Error: GStreamer development headers are required by camera_desktop on Linux."
  echo "Install them on Ubuntu/Debian with: sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev"
  exit 1
fi

echo "Running static analysis and tests..."
flutter pub get
flutter analyze
flutter test

echo "Building Linux x64 release..."
flutter build linux --release

STAGE_DIR="$ROOT_DIR/build/linux_stage/WhatIsThat"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR" "$ROOT_DIR/dist"

cp -a build/linux/x64/release/bundle/. "$STAGE_DIR/"
cp assets/icon/app_icon.png "$STAGE_DIR/whatisthat.png"
cp installer/whatisthat.desktop "$STAGE_DIR/whatisthat.desktop"

tar -czf dist/WhatIsThat-Linux-x64.tar.gz -C "$ROOT_DIR/build/linux_stage" WhatIsThat
echo "Created: $ROOT_DIR/dist/WhatIsThat-Linux-x64.tar.gz"
ls -lh dist/WhatIsThat-Linux-x64.tar.gz
