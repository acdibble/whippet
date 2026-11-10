import AppKit
import ScreenCaptureKit
import WhippetCore

/// Capture Text: picks an area of the screen and copies the text in it, or what a QR code or barcode in it encodes.
/// The screen is pictured first and the area picked on that picture, so menus and tooltips open at the time stay in
/// it, and nothing Whippet draws while picking ends up in it.
@MainActor
enum ScreenCapture {
    /// Opens Screen Recording settings, where Whippet is turned on.
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
    private static let hasAskedKey = "screenCaptureHasAsked"
    private static var session: SelectionSession?

    /// Whether an area is being picked, which keeps Capture Text on until it's picked or cancelled.
    static var isCapturing: Bool {
        session != nil
    }

    /// Screen Recording permission, which macOS needs before Whippet can see other apps' windows.
    static var isAllowed: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// The first time, macOS's own prompt, which leads to System Settings. After that macOS doesn't ask again, so
    /// System Settings opens straight away.
    static func requestAccess() {
        if UserDefaults.standard.bool(forKey: hasAskedKey) {
            NSWorkspace.shared.open(settingsURL)
        } else {
            UserDefaults.standard.set(true, forKey: hasAskedKey)
            CGRequestScreenCaptureAccess()
        }
    }

    /// Lets an area be picked and copies its text. `excludedWindows` are window numbers left out of the picture, such
    /// as the launcher while it closes.
    static func captureText(excludingWindows excludedWindows: [Int] = []) async {
        guard PermissionGate.shared.allows(.screenRecording, for: .captureText) else {
            NSSound.beep()
            return
        }
        guard isAllowed else {
            requestAccess()
            Toast.shared.show(String(localized: "Allow Screen Recording to Capture Text"), symbol: "text.viewfinder")
            return
        }
        guard session == nil, let image = await pickArea(excludingWindows: excludedWindows) else { return }
        let recognized = await Task.detached(priority: .userInitiated) { TextRecognition.recognize(in: image) }
            .value
        guard !recognized.content.isEmpty else {
            NSSound.beep()
            Toast.shared.show(String(localized: "No Text Found"), symbol: "text.viewfinder")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            TextRecognition.forCopying(recognized.content, isCode: recognized.isCode), forType: .string)
        Toast.shared.show(
            recognized.isLink ? String(localized: "Copied Link") : String(localized: "Copied Text"),
            symbol: recognized.isLink ? "link" : "text.viewfinder"
        )
    }

    /// The picked part of the screen at full resolution, or nil when picking was cancelled or the screen couldn't be
    /// pictured.
    private static func pickArea(excludingWindows excludedWindows: [Int]) async -> CGImage? {
        let pictures = await picturesOfScreens(excludingWindows: excludedWindows)
        guard !pictures.isEmpty else {
            NSSound.beep()
            return nil
        }
        let session = SelectionSession()
        self.session = session
        defer { self.session = nil }
        return await session.run(pictures)
    }

    /// Each screen pictured as it is now, without the pointer.
    private static func picturesOfScreens(excludingWindows excludedWindows: [Int]) async -> [(NSScreen, CGImage)] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else { return [] }
        let excluded = content.windows.filter { excludedWindows.contains(Int($0.windowID)) }
        var pictures: [(NSScreen, CGImage)] = []
        for screen in NSScreen.screens {
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                let display = content.displays.first(where: { $0.displayID == number })
            else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: excluded)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            configuration.showsCursor = false
            configuration.captureResolution = .best
            guard
                let image = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration)
            else { continue }
            pictures.append((screen, image))
        }
        return pictures
    }
}

/// The overlays an area is picked on, one on each screen, until one of them finishes or cancels.
@MainActor
private final class SelectionSession {
    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<CGImage?, Never>?
    /// Brought back to the front afterwards, since Whippet becomes active so the pointer shows a crosshair.
    private var previousApp: NSRunningApplication?

    func run(_ pictures: [(NSScreen, CGImage)]) async -> CGImage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let frontmost = NSWorkspace.shared.frontmostApplication
            previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
            panels = pictures.map { screen, image in
                SelectionPanel(screen: screen, image: image) { [weak self] picked in self?.finish(picked) }
            }
            // Straight away, rather than when the app in front lets go, so the crosshair and Escape work from the start.
            NSApp.activate(ignoringOtherApps: true)
            for panel in panels {
                panel.orderFrontRegardless()
            }
            let pointer = NSEvent.mouseLocation
            (panels.first { NSMouseInRect(pointer, $0.frame, false) } ?? panels.first)?.makeKey()
            NSCursor.crosshair.set()
        }
    }

    private func finish(_ picked: CGImage?) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = []
        previousApp?.activate()
        continuation.resume(returning: picked)
    }
}

/// A borderless window over a whole screen, above everything including the menu bar and the Dock, showing the
/// screen's picture to pick from.
private final class SelectionPanel: NSPanel {
    init(screen: NSScreen, image: CGImage, onFinish: @escaping (CGImage?) -> Void) {
        super.init(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        hasShadow = false
        setFrame(screen.frame, display: false)
        contentView = SelectionView(image: image, onFinish: onFinish)
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
}

/// The screen's picture, dimmed, with guide lines through the pointer until dragging starts, then the area being
/// picked cut out of the dimming and outlined, with its size. Letting go finishes; Escape or a right click cancels.
/// Drawn with layers, so following the pointer never redraws the picture.
private final class SelectionView: NSView {
    private let image: CGImage
    private let onFinish: (CGImage?) -> Void
    private var start: CGPoint?
    private var selection: CGRect?
    private var pointer: CGPoint?

    private let dimming = CAShapeLayer()
    private let outline = CAShapeLayer()
    private let guides = CAShapeLayer()
    private let sizeLabel = CATextLayer()

    /// Smaller than this in either direction counts as a click rather than an area.
    private static let minimumSize: CGFloat = 4
    private static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    init(image: CGImage, onFinish: @escaping (CGImage?) -> Void) {
        self.image = image
        self.onFinish = onFinish
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize

        dimming.fillColor = NSColor.black.withAlphaComponent(0.3).cgColor
        dimming.fillRule = .evenOdd
        outline.fillColor = nil
        outline.strokeColor = NSColor.white.cgColor
        outline.lineWidth = 1
        // White lines with a dark edge, so they show on any background.
        for line in [outline, guides] {
            line.shadowColor = NSColor.black.cgColor
            line.shadowOpacity = 0.6
            line.shadowRadius = 1
            line.shadowOffset = .zero
        }
        guides.fillColor = nil
        guides.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
        guides.lineWidth = 1
        sizeLabel.font = Self.labelFont
        sizeLabel.fontSize = Self.labelFont.pointSize
        sizeLabel.foregroundColor = NSColor.white.cgColor
        sizeLabel.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        sizeLabel.cornerRadius = 4
        sizeLabel.alignmentMode = .center
        for sublayer in [dimming, outline, guides, sizeLabel] {
            layer?.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        guard let window else { return }
        window.makeFirstResponder(self)
        sizeLabel.contentsScale = window.backingScaleFactor
        let location = window.mouseLocationOutsideOfEventStream
        pointer = bounds.contains(location) ? location : nil
        update()
    }

    override func layout() {
        super.layout()
        update()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        pointer = convert(event.locationInWindow, from: nil)
        update()
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        update()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        update()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        var point = convert(event.locationInWindow, from: nil)
        point.x = min(max(point.x, bounds.minX), bounds.maxX)
        point.y = min(max(point.y, bounds.minY), bounds.maxY)
        pointer = point
        selection = CGRect(
            x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x),
            height: abs(point.y - start.y))
        update()
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
        guard let selection, selection.width >= Self.minimumSize, selection.height >= Self.minimumSize else {
            selection = nil
            update()
            return
        }
        // The picture is at the screen's full resolution and measured from its top left, this view from its bottom left.
        let scale = CGFloat(image.width) / bounds.width
        let pixels = CGRect(
            x: selection.minX * scale, y: (bounds.height - selection.maxY) * scale, width: selection.width * scale,
            height: selection.height * scale
        ).integral
        onFinish(image.cropping(to: pixels))
    }

    override func rightMouseDown(with event: NSEvent) {
        onFinish(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private func update() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for sublayer in [dimming, outline, guides] {
            sublayer.frame = bounds
        }

        let dimmed = CGMutablePath()
        dimmed.addRect(bounds)
        if let selection {
            dimmed.addRect(selection)
        }
        dimming.path = dimmed
        outline.path = selection.map { CGPath(rect: $0.insetBy(dx: -0.5, dy: -0.5), transform: nil) }

        // Through the middle of the pointer's pixel, so the lines are crisp.
        if selection == nil, let pointer {
            let x = pointer.x.rounded(.down) + 0.5
            let y = pointer.y.rounded(.down) + 0.5
            let lines = CGMutablePath()
            lines.move(to: CGPoint(x: x, y: bounds.minY))
            lines.addLine(to: CGPoint(x: x, y: bounds.maxY))
            lines.move(to: CGPoint(x: bounds.minX, y: y))
            lines.addLine(to: CGPoint(x: bounds.maxX, y: y))
            guides.path = lines
        } else {
            guides.path = nil
        }

        guard let selection else {
            sizeLabel.isHidden = true
            return
        }
        // In pixels, under the area's bottom right corner, or inside it at the bottom of the screen.
        let scale = CGFloat(image.width) / max(bounds.width, 1)
        let text = "\(Int((selection.width * scale).rounded())) × \(Int((selection.height * scale).rounded()))"
        let textSize = (text as NSString).size(withAttributes: [.font: Self.labelFont])
        let size = CGSize(width: textSize.width.rounded(.up) + 12, height: textSize.height.rounded(.up) + 4)
        var origin = CGPoint(x: max(selection.maxX - size.width, bounds.minX), y: selection.minY - size.height - 6)
        if origin.y < bounds.minY {
            origin.y = selection.minY + 6
        }
        sizeLabel.string = text
        sizeLabel.frame = CGRect(origin: origin, size: size)
        sizeLabel.isHidden = false
    }
}
