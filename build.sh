#!/bin/bash
# Builds ClipboardBar from source and installs it to /Applications.
set -e
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Swift compiler not found. Installing Apple's Command Line Tools..."
  echo "A popup will appear. Click Install, wait for it to finish, then run this script again."
  xcode-select --install || true
  exit 1
fi

APP="build/ClipboardBar.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS"

echo "Compiling..."
swiftc -O -target "$(uname -m)-apple-macos13.0" Sources/main.swift -o "$APP/Contents/MacOS/ClipboardBar"
cp Info.plist "$APP/Contents/Info.plist"

echo "Signing (ad-hoc, local only)..."
codesign --force --deep --sign - "$APP"

echo "Installing to /Applications..."
pkill -x ClipboardBar 2>/dev/null || true
rm -rf /Applications/ClipboardBar.app
cp -R "$APP" /Applications/ClipboardBar.app
xattr -cr /Applications/ClipboardBar.app

open /Applications/ClipboardBar.app
echo ""
echo "Done. Look for the clipboard icon in your menu bar (top right)."
echo "Shortcut to open it from anywhere: Control + Option + V"
echo ""
echo "IMPORTANT (one time): to auto-paste, allow ClipboardBar in"
echo "System Settings > Privacy & Security > Accessibility."
echo "If it is already listed from an older build, remove it with the - button and add it again."
