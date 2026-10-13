import AppKit

/// Plovoucí panel ve stylu Spotlightu – neaktivuje aplikaci, je nad ostatními okny i nad fullscreenem.
final class LauncherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: LauncherLayout.width, height: 300),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        // Přesouvá se tažením za lištu s vyhledáváním (`WindowDragArea`), ne za celé pozadí.
        isMovable = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        // Liquid Glass má vlastní okraj i hloubku. Stín okna by se počítal z obdélníku
        // celého panelu a v rozích a kolem skla by prosvítal jako tmavý rámeček.
        hasShadow = !Self.usesLiquidGlass
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Zda se pozadí kreslí jako Liquid Glass (macOS 26 a sestavení v Xcode 26).
    static var usesLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Pozadí panelu se zaoblenými rohy: na macOS 26 Liquid Glass, jinak vibrancy.
    static func makeBackground(content: NSView) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]

        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let radius: CGFloat = 22
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.autoresizingMask = [.width, .height]
            glass.contentView = content
            // Obsah (pole, ikona) se jinak neořezává podle zaoblení a v rozích prosvítá.
            content.wantsLayer = true
            content.layer?.cornerRadius = radius
            content.layer?.cornerCurve = .continuous
            content.layer?.masksToBounds = true
            // Ořezat i celý panel – nic nesmí kreslit mimo zaoblený tvar skla.
            let container = NSView()
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.clear.cgColor
            container.layer?.cornerRadius = radius
            container.layer?.cornerCurve = .continuous
            container.layer?.masksToBounds = true
            glass.frame = container.bounds
            container.addSubview(glass)
            return container
        }
        #endif

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: 14)
        content.frame = effect.bounds
        effect.addSubview(content)
        return effect
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
