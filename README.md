# Image to Screensaver

A native macOS (SwiftUI) app that converts PNG/JPG/JPEG/WEBP images into real
Windows `.scr` screensaver files for Windows 10 and 11.

## Quick start (no extra tools required)

```bash
git clone <this-repo>
cd myfirstblog-/ImageToScreensaver
swift run
```

That's it. The Windows player binary is **prebuilt and committed** to the
repo at `Sources/ImageToScreensaver/Resources/ScreensaverStub.exe` (~880 KB,
PE32+ GUI). You don't need mingw-w64, you don't need Wine, you don't need to
touch any `.exe` toolchain. Just Xcode CLT / Swift.

Drop images into the window → adjust settings → **Export .scr…** → copy the
file to a Windows 10/11 machine and double-click it.

## Why is there still an `.exe` in the repo?

Because `.scr` *is* a Windows executable, by Windows' own rules. The shell
only accepts the file as a screensaver if it's a valid PE binary — the `.scr`
extension is just dressing. So one Windows binary has to exist somewhere.
We pre-compiled a tiny, self-contained one **once** (full C++ source in
`stub/screensaver_stub.cpp`, nothing hidden) and ship it as a resource. The
macOS app appends your images and a config blob to a copy of it, writes the
result as `MySlideshow.scr`, done.

If you ever want to rebuild that binary yourself from source (audit it, edit
it, change the player behaviour), see [BUILD.md](BUILD.md). Otherwise you can
ignore it entirely.

## Scope statement

This tool generates **legitimate Windows screensavers only**. The bundled
player implements only the documented Windows screensaver protocol
(`/s /p HWND /c /a`). No networking. No persistence. No privilege escalation.
No hidden execution. No obfuscation. Full source for the player is in
`stub/screensaver_stub.cpp`.

## Features

- Drag & drop PNG, JPG, JPEG, WEBP (or whole folders)
- Multi-image slideshow with reorderable gallery
- Adjustable per-image duration (1–30 s)
- Transition effects: None, Fade, Slide (length adjustable)
- Fit modes: Contain, Cover, Stretch
- Resolution presets (720p / 1080p / 1440p / 4K) — images are downscaled to
  keep the `.scr` size sane
- Background color picker
- Output filename customization
- Modern macOS UI, dark mode, single window, live progress bar

## Project layout

```
.
├── README.md
├── BUILD.md                            # only relevant if you rebuild the stub
├── stub/                               # Windows player source (audit / edit)
│   ├── screensaver_stub.cpp
│   ├── build_stub.sh                   # cross-compiles via mingw-w64
│   └── prebuilt/ScreensaverStub.exe
└── ImageToScreensaver/                 # SwiftPM macOS app (no external deps)
    ├── Package.swift
    └── Sources/ImageToScreensaver/
        ├── App.swift
        ├── Models/
        ├── ViewModels/
        ├── Services/                   # ImageProcessor, PayloadBuilder,
        │                               # ScreensaverBuilder
        ├── Views/
        └── Resources/ScreensaverStub.exe   ← prebuilt, ships with the repo
```

Strict layering: Views → ViewModels → Services → Models. Zero third-party
Swift dependencies.

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
| u64 LE   payload offset      |   ← lets the player find the payload
+------------------------------+
```

Trailing data past the PE's last section is ignored by the Windows loader,
so the result is a fully standard executable.

## Example export flow

1. `cd ImageToScreensaver && swift run`
2. Drop a folder of 12 vacation photos onto the drop zone.
3. Set duration **4 s**, transition **Fade**, fit **Cover**, resolution
   **1920 × 1080**, filename `Vacation2026`.
4. Click **Export .scr…**, save to `~/Desktop`.
5. Copy `Vacation2026.scr` to a Windows 10/11 PC.
6. Right-click → **Test** to preview, or **Install** to make it your system
   screensaver.

## Testing

```bash
cd ImageToScreensaver
swift build                 # must succeed
swift run                   # launches the app
# After exporting MyTest.scr from the UI:
file ~/Desktop/MyTest.scr   # → PE32+ executable (GUI) x86-64, for MS Windows
```

On Windows: right-click the `.scr` → **Test** (preview) or **Install**
(register).

## Requirements

- macOS 14 or later (SwiftUI features, async/await)
- Xcode command-line tools (`xcode-select --install`)
- That's it.

## License

MIT.
