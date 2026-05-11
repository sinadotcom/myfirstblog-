# Build instructions

**You almost certainly don't need this file.** The Windows player binary is
already prebuilt and committed at
`ImageToScreensaver/Sources/ImageToScreensaver/Resources/ScreensaverStub.exe`.
Just `cd ImageToScreensaver && swift run` and you're done.

This file is for people who want to rebuild the Windows-side stub from
source — e.g. to audit it, modify it, or change the slideshow player logic.

## Rebuild the Windows stub (only if you want to)

```bash
brew install mingw-w64
cd stub
./build_stub.sh
```

This cross-compiles `screensaver_stub.cpp` with `x86_64-w64-mingw32-g++`,
statically links the C/C++ runtime, and links against the standard Windows
system DLLs (gdi32, user32, gdiplus, etc.). The script:

1. Writes `stub/prebuilt/ScreensaverStub.exe`.
2. Copies it into the SwiftPM resources directory so the next `swift build`
   bundles the new version.

Verify:

```bash
file stub/prebuilt/ScreensaverStub.exe
# → PE32+ executable (GUI) x86-64, for MS Windows
```

## Build the macOS app

### SwiftPM

```bash
cd ImageToScreensaver
swift build -c release
swift run
```

### Xcode

```bash
cd ImageToScreensaver
open Package.swift
```

Then ⌘R.

## Package as a redistributable `.app` (optional)

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
  <key>LSMinimumSystemVersion</key>        <string>14.0</string>
  <key>NSHighResolutionCapable</key>       <true/>
  <key>CFBundlePackageType</key>           <string>APPL</string>
</dict>
</plist>
PLIST
open "$APP"
```

For Gatekeeper-clean distribution, codesign + notarize as usual.

## Clean

```bash
rm -rf ImageToScreensaver/.build ImageToScreensaver/.swiftpm
rm -f  stub/prebuilt/ScreensaverStub.exe
# Do NOT delete the committed Resources/ScreensaverStub.exe unless you plan
# to rebuild it; without it the app cannot produce .scr files.
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| App alerts "Bundled ScreensaverStub.exe is missing" | The resource was deleted. Restore from git (`git checkout -- ImageToScreensaver/Sources/ImageToScreensaver/Resources/ScreensaverStub.exe`) or rebuild via `stub/build_stub.sh`. |
| `x86_64-w64-mingw32-g++: command not found` | Run `brew install mingw-w64`. (Only needed if rebuilding the stub.) |
| Generated `.scr` shows "no embedded slideshow payload" on Windows | Footer wasn't appended — export failed mid-way. Re-export. |
| Windows SmartScreen warns about an unsigned `.scr` | Expected for unsigned binaries. Sign with an Authenticode certificate to remove it. |
