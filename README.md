# Image to Screensaver

A native macOS app (SwiftUI) that converts PNG/JPG/JPEG/WEBP images into real
Windows `.scr` screensaver files compatible with Windows 10 and 11.

The app bundles a small, pre-compiled Windows "player" executable. To build a
`.scr`, the macOS app:

1. Re-encodes your images to PNG, fitted to the chosen target resolution.
2. Copies the bundled `ScreensaverStub.exe` to the chosen output path.
3. Appends a binary payload (config JSON + PNGs) followed by a 16-byte footer.
4. Renames the result with the `.scr` extension.

The resulting file is a standards-compliant Windows screensaver — Windows
identifies `.scr` files purely by extension; the contents are a normal PE
executable. The player implements the documented screensaver command-line
protocol (`/s`, `/p HWND`, `/c`, `/a`) and exits on mouse motion, click, or
keypress.

> **Scope statement.** This tool generates **legitimate Windows screensavers
> only**. The player performs no networking, no persistence, no privilege
> escalation, no hidden execution, no obfuscation. The full source for the
> Windows-side player is in `stub/screensaver_stub.cpp`; nothing is hidden.

## Features

- Drag & drop PNG, JPG, JPEG, WEBP (or whole folders)
- Multi-image slideshow with reorderable gallery
- Adjustable per-image duration (1–30 s)
- Transition effects: None, Fade, Slide (length adjustable)
- Fit modes: Contain, Cover, Stretch
- Target resolution presets (720p / 1080p / 1440p / 4K)
- Background color picker
- Output filename customization
- Optional preview via Wine when installed (`brew install --cask wine-stable`)
- Modern macOS look, dark mode, single-window, progress bar during build

## Quick start

```bash
# 1) Install Homebrew prerequisites
brew install mingw-w64                  # cross-compiler for the Windows stub
xcode-select --install                  # if not already done

# 2) Build the Windows player stub (one time, or whenever stub source changes)
cd stub
./build_stub.sh
cd ..

# 3) Run the macOS app
cd ImageToScreensaver
swift run                               # or open Package.swift in Xcode
```

The app window appears, drop some images, click **Export .scr…**, choose
a destination, and you get a `MySlideshow.scr` you can copy to a Windows
machine.

See [BUILD.md](BUILD.md) for the full build / packaging / signing details.

## Project layout

```
.
├── README.md
├── BUILD.md
├── stub/                              # Windows screensaver player
│   ├── screensaver_stub.cpp           # ~300 lines, C++ / Win32 / GDI+
│   ├── build_stub.sh                  # mingw-w64 cross-compile script
│   └── prebuilt/ScreensaverStub.exe   # produced by build_stub.sh
└── ImageToScreensaver/                # SwiftPM package
    ├── Package.swift
    └── Sources/ImageToScreensaver/
        ├── App.swift                  # @main entry
        ├── Models/                    # plain value types
        ├── ViewModels/                # AppViewModel (MainActor ObservableObject)
        ├── Services/                  # ImageProcessor, PayloadBuilder,
        │                              # ScreensaverBuilder, WinePreview
        ├── Views/                     # SwiftUI views
        └── Resources/ScreensaverStub.exe
```

Strict clean-architecture layering:

- **Views** depend on the ViewModel only.
- **ViewModel** depends on Services and Models only.
- **Services** depend on Models and Apple frameworks only.
- **Models** depend on Foundation only.

## How a `.scr` is generated (payload format)

```
+------------------------------+
| ScreensaverStub.exe bytes    |   ← normal PE32+ executable
+------------------------------+
| u32  metadata_length         |
| utf-8 JSON metadata          |   ← duration, transition, fit, color, …
| u32  image_count             |
| repeat image_count times:    |
|   u32  png_length            |
|   PNG bytes                  |
+------------------------------+
| 8 bytes  "SCRPLD\x01\x00"    |   ← footer magic
| u64 LE   payload offset      |   ← so the stub can find the payload
+------------------------------+
```

Trailing data after a PE's last section is ignored by the Windows loader, so
this approach is fully compatible with all signature and integrity checks
Windows applies to regular screensavers.

## Example export flow

1. Launch the app: `cd ImageToScreensaver && swift run`.
2. Drop a folder containing 12 vacation photos onto the drop zone.
3. Set duration to **4 s**, transition to **Fade**, fit to **Cover**,
   resolution to **1920 × 1080**.
4. Set filename to `Vacation2026`.
5. Click **Export .scr…**, save to `~/Desktop`.
6. Result: `~/Desktop/Vacation2026.scr` (≈ stub size + sum of PNG sizes).
7. (Optional) Click **Preview with Wine** to sanity-check rendering locally.
8. Copy `Vacation2026.scr` to a Windows 10/11 PC.
9. On Windows, right-click the file → **Install** (or place it in
   `C:\Windows\System32` and select it in *Settings → Personalization → Lock
   screen → Screen saver*).

## Testing instructions

**macOS unit-level checks (no Windows needed):**

```bash
# Show that the stub locator + builder behave correctly
cd ImageToScreensaver
swift build              # must succeed
swift run                # launches GUI

# Build a screensaver to /tmp and inspect:
# After exporting MyTest.scr from the UI,
ls -l /tmp/MyTest.scr            # should be ≈ stub + payload size
xxd /tmp/MyTest.scr | tail -2    # last 16 bytes start with 'SCRPLD'
file /tmp/MyTest.scr             # "PE32+ executable (GUI) x86-64, for MS Windows"
```

**Wine round-trip on macOS** (optional):

```bash
brew install --cask --no-quarantine wine-stable
wine /tmp/MyTest.scr /s          # full-screen slideshow; move mouse to exit
wine /tmp/MyTest.scr /c          # opens the info dialog
```

**Windows 10 / 11 verification:**

1. Copy `MyTest.scr` to the Windows machine.
2. Right-click → **Test** to preview full-screen.
3. Right-click → **Install** to register it as a system screensaver, or move
   it into `C:\Windows\System32\` and pick it in *Personalization → Lock
   screen → Screen saver*.
4. Confirm it shows up in the dropdown, the **Preview** button works, and
   normal exit conditions (mouse motion / click / keypress) end the show.

## Dependencies

- macOS 13 or later (SwiftUI, async/await).
- Xcode command-line tools (for `swift build`).
- `mingw-w64` from Homebrew, *only* to compile the Windows stub one time
  (`brew install mingw-w64`). End users of the built `.app` never need it.
- Wine is **optional**; only used for in-place preview if already installed.

## License

MIT. The bundled `ScreensaverStub.exe` is built from `stub/screensaver_stub.cpp`
in this repository; nothing else is bundled.
