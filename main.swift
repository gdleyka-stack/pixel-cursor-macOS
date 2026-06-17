import Cocoa
import ApplicationServices

// MARK: - Private CGS API

typealias CGSConnectionID = Int32

@_silgen_name("_CGSDefaultConnection")
func _CGSDefaultConnection() -> CGSConnectionID

@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(_ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ key: CFString, _ value: CFTypeRef) -> Int32

@_silgen_name("CGSGetGlobalCursorData")
func CGSGetGlobalCursorData(
    _ cid: CGSConnectionID,
    _ outData: UnsafeMutableRawPointer?,
    _ outDataSize: UnsafeMutablePointer<Int32>?,
    _ outRowBytes: UnsafeMutablePointer<Int32>?,
    _ outRect: UnsafeMutablePointer<CGRect>?,
    _ outHotSpot: UnsafeMutablePointer<CGPoint>?,
    _ outDepth: UnsafeMutablePointer<Int32>?,
    _ outComponents: UnsafeMutablePointer<Int32>?,
    _ outBitsPerComponent: UnsafeMutablePointer<Int32>?
) -> Int32

// MARK: - Pixel-perfect image view

class PixelImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        super.draw(dirtyRect)
    }
}

// MARK: - Slider embedded in menu item

class SliderMenuView: NSView {
    var slider: NSSlider!
    var label: NSTextField!
    var onChanged: ((CGFloat) -> Void)?

    init(initialScale: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: 230, height: 56))

        label = NSTextField(frame: NSRect(x: 16, y: 36, width: 198, height: 16))
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        updateLabel(scale: initialScale)
        addSubview(label)

        slider = NSSlider(frame: NSRect(x: 14, y: 10, width: 202, height: 22))
        slider.minValue = 1.5
        slider.maxValue = 5.0
        slider.doubleValue = Double(initialScale)
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateLabel(scale: CGFloat) {
        let pct = Int((scale / 2.5) * 100)
        label.stringValue = "Cursor Size: \(pct)%"
    }

    @objc func sliderMoved(_ sender: NSSlider) {
        let v = CGFloat(sender.doubleValue)
        updateLabel(scale: v)
        onChanged?(v)
    }
}

// MARK: - Main application delegate

// Cursor index -> assets/ file mapping (verified by visual inspection):
//  0  arrow.png           Default arrow
//  1  resize d.png        Diagonal resize NW-SE
//  2  02_resize_h.png     Horizontal resize
//  3  03_resize_v.png     Vertical resize
//  4  04_resize d2.png    Diagonal resize NE-SW
//  5  finger.png          Pointing hand
//  6  drag cross.png      Move / 4-way drag
//  7  07_hand_closed.png  Closed hand / grab
//  8  08_zoom_in.png      Zoom in
//  9  09_zoom_out.png     Zoom out
// 10  10_ibeam.png        Text I-beam
// 11  11_crosshair.png    Crosshair
// 12  12_forbidden.png    Not allowed
// 13  13_busy.png         Busy / spinning

class CursorApp: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem!
    var overlayWindow: NSWindow!
    var cursorImageView: PixelImageView!
    var cursors: [NSImage] = []
    var currentCursorIndex = 0
    var trackingTimer: Timer?
    var scale: CGFloat = 2.5
    var lastHotspot = CGPoint.zero

    // CGDisplayHideCursor / CGDisplayShowCursor are reference-counted.
    // We call Hide exactly once and track the state so we can Show exactly once.
    var systemCursorHidden = false
    var menuIsOpen = false

    // Hotspot offsets (in sprite-pixel units from top-left of 18x18 cell).
    // These define where the "click point" is relative to the drawn image.
    let hotspots: [NSPoint] = [
        NSPoint(x: 1, y: 1),   //  0: arrow           - tip at top-left
        NSPoint(x: 9, y: 9),   //  1: resize d         - center
        NSPoint(x: 9, y: 9),   //  2: resize_h         - center
        NSPoint(x: 9, y: 9),   //  3: resize_v         - center
        NSPoint(x: 9, y: 9),   //  4: resize d2        - center
        NSPoint(x: 5, y: 2),   //  5: finger           - fingertip
        NSPoint(x: 9, y: 9),   //  6: drag cross       - center
        NSPoint(x: 9, y: 9),   //  7: hand_closed      - center
        NSPoint(x: 9, y: 9),   //  8: zoom_in          - center
        NSPoint(x: 9, y: 9),   //  9: zoom_out         - center
        NSPoint(x: 9, y: 9),   // 10: ibeam            - center
        NSPoint(x: 9, y: 9),   // 11: crosshair        - center
        NSPoint(x: 9, y: 9),   // 12: forbidden        - center
        NSPoint(x: 9, y: 9),   // 13: busy             - center
    ]

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Allow cursor hide/show from this background process
        let cid = _CGSDefaultConnection()
        _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)

        loadCursors()
        setupStatusItem()
        setupOverlayWindow()
        startTracking()

        log("Pixel Cursors started. Loaded \(cursors.count) cursors.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if systemCursorHidden {
            CGDisplayShowCursor(kCGNullDirectDisplay)
        }
    }

    // MARK: - Cursor assets

    func loadCursors() {
        let base = "/Users/artem/Desktop/projects/Pixel Cursors/assets"
        let names: [String] = [
            "arrow",
            "resize d",
            "02_resize_h",
            "03_resize_v",
            "04_resize d2",
            "finger",
            "drag cross",
            "07_hand_closed",
            "08_zoom_in",
            "09_zoom_out",
            "10_ibeam",
            "11_crosshair",
            "12_forbidden",
            "13_busy"
        ]
        for name in names {
            let path = "\(base)/\(name).png"
            if let img = NSImage(contentsOfFile: path) {
                cursors.append(img)
            } else {
                log("WARNING: missing asset: \(name).png")
            }
        }
    }

    // MARK: - Tray icon

    func makeTrayIcon() -> NSImage {
        let trayPath = "/Users/artem/Desktop/projects/Pixel Cursors/trey_ico.png"
        guard let src = NSImage(contentsOfFile: trayPath) else {
            return cursors.first ?? NSImage()
        }
        // Fit within 16pt height, preserve aspect ratio, no stretch
        let srcSize = src.size
        let targetH: CGFloat = 16
        let targetW  = targetH * (srcSize.width / srcSize.height)
        let img = NSImage(size: NSSize(width: targetW, height: targetH))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        src.draw(in: NSRect(x: 0, y: 0, width: targetW, height: targetH),
                 from: .zero, operation: .copy, fraction: 1.0)
        img.unlockFocus()
        return img
    }

    // MARK: - Status bar item

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let btn = statusItem.button {
            let icon = makeTrayIcon()
            icon.isTemplate = false
            btn.image = icon
            btn.imageScaling = .scaleProportionallyUpOrDown
        }

        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "Pixel Cursors", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let sliderView = SliderMenuView(initialScale: scale)
        sliderView.onChanged = { [weak self] newScale in
            guard let self else { return }
            self.scale = newScale
            self.resizeOverlay()
        }
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Overlay window

    func setupOverlayWindow() {
        let size = 18 * scale
        overlayWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.backgroundColor = .clear
        overlayWindow.isOpaque = false
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = .statusBar
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        cursorImageView = PixelImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        cursorImageView.imageScaling = .scaleProportionallyUpOrDown
        if !cursors.isEmpty { cursorImageView.image = cursors[0] }

        overlayWindow.contentView = cursorImageView
        overlayWindow.orderFrontRegardless()
    }

    func resizeOverlay() {
        let size = 18 * scale
        let origin = overlayWindow.frame.origin
        overlayWindow.setFrame(NSRect(x: origin.x, y: origin.y, width: size, height: size), display: false)
        cursorImageView.frame = NSRect(x: 0, y: 0, width: size, height: size)
    }

    // MARK: - Tracking

    func startTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: - Cursor type detection

    func detectCursorIndex(hotspot: CGPoint, rect: CGRect) -> Int {
        let hx = Int(hotspot.x), hy = Int(hotspot.y)
        let w  = Int(rect.width), h  = Int(rect.height)

        // I-beam: tall narrow cursor
        if (w <= 16 && h >= 17) || (h > w && hx >= 10 && hx <= 13 && hy >= 10 && hy <= 13) {
            return 10
        }
        // Pointing hand: hotspot in upper area
        if hx >= 12 && hx <= 16 && hy >= 6 && hy <= 11 {
            return 5
        }
        // Resize horizontal: wider than tall
        if w > h && w >= 18 && hx >= 7 && hx <= 11 {
            return 2
        }
        // Resize vertical: taller than wide
        if h > w && h >= 18 && hy >= 7 && hy <= 11 {
            return 3
        }
        // Diagonal NW-SE: square, hotspot on diagonal
        if w == h && w >= 14 && w <= 18 && hx == hy && hx >= 7 {
            return 1
        }
        // Diagonal NE-SW: square, hotspot anti-diagonal
        if w == h && w >= 14 && w <= 18 && (hx + hy) >= 14 && (hx + hy) <= 20 && hx != hy {
            return 4
        }
        // Crosshair: small square, centered
        if (hx == 8 || hx == 7) && (hy == 8 || hy == 7) && w >= 15 && w <= 18 && w == h {
            return 11
        }
        // Forbidden: normal square centered
        if (hx == 9 || hx == 10) && (hy == 9 || hy == 10) && w >= 18 && w == h {
            return 12
        }
        // Busy / spinning wheel: large
        if w >= 36 && h >= 36 {
            return 13
        }
        // Move / drag cross: larger square
        if w >= 20 && w == h {
            return 6
        }
        return 0
    }

    // MARK: - Per-frame tick

    func tick() {
        guard !menuIsOpen else { return }

        let mouseLoc = NSEvent.mouseLocation
        let cid = _CGSDefaultConnection()
        var rect = CGRect.zero, hotspot = CGPoint.zero
        var depth: Int32 = 0, components: Int32 = 0, bitsPerComp: Int32 = 0
        var rowBytes: Int32 = 0, dataSize: Int32 = 0

        let ok = CGSGetGlobalCursorData(cid, nil, &dataSize, &rowBytes, &rect,
                                        &hotspot, &depth, &components, &bitsPerComp)
        if ok == 0 {
            if hotspot != lastHotspot {
                lastHotspot = hotspot
                log("cursor changed: hotspot=\(hotspot) rect=\(rect)")
            }
            let idx = detectCursorIndex(hotspot: hotspot, rect: rect)
            if idx != currentCursorIndex, idx < cursors.count {
                currentCursorIndex = idx
                cursorImageView.image = cursors[idx]
            }
        }

        // Position overlay so hotspot pixel aligns with real mouse position
        let finalSize = 18 * scale
        var hx: CGFloat = 0, hy: CGFloat = 0
        if currentCursorIndex < hotspots.count {
            hx = hotspots[currentCursorIndex].x * scale
            hy = hotspots[currentCursorIndex].y * scale
        }
        overlayWindow.setFrameOrigin(NSPoint(x: mouseLoc.x - hx, y: mouseLoc.y - finalSize + hy))

        // Hide real cursor exactly once (CGDisplayHideCursor is reference-counted)
        if !systemCursorHidden {
            CGDisplayHideCursor(kCGNullDirectDisplay)
            systemCursorHidden = true
        }
    }

    // MARK: - Cursor visibility helpers

    func hideOverlayShowRealCursor() {
        menuIsOpen = true
        overlayWindow.orderOut(nil)
        if systemCursorHidden {
            CGDisplayShowCursor(kCGNullDirectDisplay)
            systemCursorHidden = false
        }
    }

    func showOverlayHideRealCursor() {
        menuIsOpen = false
        overlayWindow.orderFrontRegardless()
        // tick() will hide the real cursor on next frame
    }

    // MARK: - Logging

    func log(_ msg: String) {
        let path = "/Users/artem/Desktop/projects/Pixel Cursors/app.log"
        let line = msg + "\n"
        if !FileManager.default.fileExists(atPath: path) {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        } else if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8) ?? Data())
            fh.closeFile()
        }
    }
}

// MARK: - NSMenuDelegate

extension CursorApp: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        hideOverlayShowRealCursor()
    }
    func menuDidClose(_ menu: NSMenu) {
        showOverlayHideRealCursor()
    }
}

// MARK: - Entry point

var strongDelegate: CursorApp? = CursorApp()
let app = NSApplication.shared
app.delegate = strongDelegate
app.run()
