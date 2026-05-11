# Build instructions

Two artefacts get built:

1. `ScreensaverStub.exe` — Windows PE compiled on macOS with mingw-w64.
2. `ImageToScreensaver` — macOS SwiftUI app built with SwiftPM (or Xcode).

The Windows stub must be built **before** the macOS app so SwiftPM can bundle
it as a resource.

## 1. Prerequisites

```bash
# Xcode CLT (Swift toolchain)
xcode-select --install

# mingw-w64 (cross-compiles 64-bit Windows binaries from macOS)
brew install mingw-w64

# Optional: Wine, only if you want to preview .scr files on macOS
brew install --cask --no-quarantine wine-stable
```

## 2. Build the Windows stub

```bash
cd stub
./build_stub.sh
```

`build_stub.sh` invokes `x86_64-w64-mingw32-g++`, statically links libgcc,
libstdc++ and the C runtime, and links against `gdiplus`, `shcore`, `ole32`,
`uuid`, `comctl32`, `gdi32`, `user32`, `kernel32`. The resulting
`ScreensaverStub.exe` depends only on standard Windows system DLLs that ship
with Windows 7 and later (we target Windows 10 / 11).

Outputs:

- `stub/prebuilt/ScreensaverStub.exe`
- `ImageToScreensaver/Sources/ImageToScreensaver/Resources/ScreensaverStub.exe` (auto-copied)

Verify:

```bash
file stub/prebuilt/ScreensaverStub.exe
# → PE32+ executable (GUI) x86-64, for MS Windows
```

## 3. Build & run the macOS app

### Via SwiftPM (no Xcode project required)

```bash
cd ImageToScreensaver
swift build -c release
swift run                    # launches the app
```

### Via Xcode

```bash
cd ImageToScreensaver
open Package.swift           # opens in Xcode; pick "My Mac" and ⌘R
```

Xcode picks up SwiftPM packages natively. The `Resources/ScreensaverStub.exe`
file is bundled into the app via the `.copy` rule in `Package.swift`.

## 4. Package as a redistributable `.app` (optional)

`swift build` produces a CLI-style binary. To wrap it as a `.app` bundle:

```bash
cd ImageToScreensaver
swift build -c release
APP=./dist/ImageToScreensaver.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ImageToScreensaver "$APP/Contents/MacOS/ImageToScreensaver"
cp -R .build/release/ImageToScreensaver_ImageToScreensaver.bundle \
      "$APP/Contents/Resources/" 2>/dev/null || true
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>            <string>ImageToScreensaver</string>
  <key>CFBundleIdentifier</key>            <string>com.example.imagetoscreensaver</string>
  <key>CFBundleName</key>                  <string>Image to Screensaver</string>
  <key>CFBundleShortVersionString</key>    <string>1.0.0</string>
  <key>CFBundleVersion</key>               <string>1</string>
  <key>LSMinimumSystemVersion</key>        <string>13.0</string>
  <key>NSHighResolutionCapable</key>       <true/>
  <key>CFBundlePackageType</key>           <string>APPL</string>
</dict>
</plist>
PLIST
open "$APP"
```

For Gatekeeper-clean distribution you can codesign + notarize:

```bash
codesign --deep --force --options runtime \
  --sign "Developer ID Application: Your Name (TEAMID)" "$APP"
xcrun notarytool submit "$APP.zip" --apple-id ... --wait
xcrun stapler staple "$APP"
```

(Signing is optional for local use; the unsigned binary runs after the usual
`Open Anyway` prompt in System Settings → Privacy & Security.)

## 5. Clean

```bash
rm -rf ImageToScreensaver/.build ImageToScreensaver/.swiftpm
rm -f  stub/prebuilt/ScreensaverStub.exe
rm -f  ImageToScreensaver/Sources/ImageToScreensaver/Resources/ScreensaverStub.exe
```

## Troubleshooting

| Symptom | Cause / Fix |
| --- | --- |
| App alerts "Bundled ScreensaverStub.exe is missing" | You haven't run `stub/build_stub.sh`, or the file is still the text placeholder. Run the script and rebuild. |
| `x86_64-w64-mingw32-g++: command not found` | Run `brew install mingw-w64`. On Apple Silicon ensure `/opt/homebrew/bin` is in PATH. |
| Generated `.scr` shows "no embedded slideshow payload" on Windows | Footer wasn't appended — usually the macOS export failed mid-way. Re-export. |
| Wine preview fails with codec errors | Older Wine builds lack GDI+ support. `brew upgrade --cask wine-stable` or test directly on Windows. |
| Windows SmartScreen warns about an unsigned `.scr` | Expected for unsigned executables. To remove the warning, codesign with a real Authenticode certificate before distributing. |
