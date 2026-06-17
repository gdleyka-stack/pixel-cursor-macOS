# Pixel Cursors

A lightweight macOS menu bar utility that replaces the system cursor with a set of pixel-art cursor sprites. The application runs entirely in the background with no Dock icon, is controlled through a single status bar icon, and requires no installation.

---

## Overview

Pixel Cursors intercepts the system cursor display by hiding the native cursor and rendering a pixel-art replacement at the exact same position in real time, at up to 120 frames per second. The correct sprite is selected automatically based on the active cursor type reported by the system (arrow, text beam, resize handles, pointing hand, etc.).

---

## Requirements

- macOS 12 Monterey or later
- Xcode Command Line Tools (for building from source)

---

## Project Structure

```
Pixel Cursors/
├── main.swift          Application source code
├── Info.plist          Bundle metadata
├── cursors.png         Original sprite sheet (5x3 grid, 18x18 px per cell)
├── trey_ico.png        Status bar icon source image
├── assets/             Individual cursor sprites (extracted from sprite sheet)
│   ├── arrow.png
│   ├── resize d.png
│   ├── 02_resize_h.png
│   ├── 03_resize_v.png
│   ├── 04_resize d2.png
│   ├── finger.png
│   ├── drag cross.png
│   ├── 07_hand_closed.png
│   ├── 08_zoom_in.png
│   ├── 09_zoom_out.png
│   ├── 10_ibeam.png
│   ├── 11_crosshair.png
│   ├── 12_forbidden.png
│   └── 13_busy.png
└── README.md
```

---

## Building

Compile with the Swift compiler from the project directory:

```bash
swiftc main.swift -o PixelCursors
```

Run:

```bash
./PixelCursors
```

The application will appear in the menu bar only. No Dock icon is shown.

---

## Usage

- **Launch** the binary. The pixel cursor becomes active immediately.
- **Menu bar icon**: click the icon to open the settings menu.
- **Cursor Size**: drag the slider to scale the cursor between 60% and 200%.
- **Quit**: select Quit from the menu or press Q.

When the menu is open, the native system cursor is restored automatically so the interface is fully usable.

---

## How It Works

The application uses two private CoreGraphics APIs:

- `_CGSDefaultConnection` — obtains the current graphics server connection.
- `CGSGetGlobalCursorData` — reads the active system cursor geometry and hotspot at runtime.
- `CGSSetConnectionProperty` with the key `SetsCursorInBackground` — enables cursor manipulation from a background process.

The native cursor is hidden with `CGDisplayHideCursor` exactly once when the overlay becomes active, and shown again with `CGDisplayShowCursor` when the menu opens. These calls are reference-counted by the OS, so they are carefully balanced to prevent the cursor from remaining hidden permanently.

A transparent, click-through `NSWindow` at `.statusBar` window level follows the mouse at 120 Hz and renders the appropriate sprite via a custom `NSImageView` subclass with pixel interpolation disabled, preserving the sharp pixel-art appearance at any scale.

---

## Cursor Detection

The active cursor type is determined by inspecting the hotspot coordinates and bounding rectangle returned by `CGSGetGlobalCursorData`:

| Cursor | Detection heuristic |
|---|---|
| Arrow | Default fallback |
| Text I-beam | Tall narrow rect (height > width, h >= 17) |
| Pointing hand | Hotspot in upper center region |
| Resize horizontal | Rect wider than tall, centered hotspot |
| Resize vertical | Rect taller than wide, centered hotspot |
| Diagonal NW-SE | Square rect, hotspot on main diagonal |
| Diagonal NE-SW | Square rect, hotspot on anti-diagonal |
| Crosshair | Small square, hotspot near center |
| Not allowed | Normal square, centered hotspot |
| Busy | Large rect (>= 36x36) |
| Move / drag | Larger square (>= 20x20) |

---

## Customization

To use your own cursor sprites, replace the PNG files in the `assets/` folder. Each image should be 18x18 pixels. The file name to cursor index mapping is documented in `main.swift` at the top of the `CursorApp` class.

To use a different status bar icon, replace `trey_ico.png` with any PNG image. The application will scale it to fit the menu bar height while preserving its aspect ratio.

---

## License

MIT License. See LICENSE for details.
