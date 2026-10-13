import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Zobrazuje/skrývá panel launcheru a zpracovává klávesnici.
@MainActor
final class LauncherController: NSObject, NSWindowDelegate {
    let model: LauncherModel
    private let panel: LauncherPanel
    private let store: LinkStore
    private var keyMonitor: Any?

    /// Volá se při ⌘E (úprava) a ⌘N (nový odkaz s případnou předvyplněnou URL).
    var onEdit: ((Link) -> Void)?
    var onAdd: ((String?) -> Void)?

    init(store: LinkStore, favicons: FaviconStore) {
        self.store = store
        model = LauncherModel(store: store)
        panel = LauncherPanel()
        super.init()

        let hosting = NSHostingView(rootView: LauncherView(model: model, favicons: favicons))
        hosting.sizingOptions = []
        panel.contentView = LauncherPanel.makeBackground(content: hosting)
        panel.delegate = self

        model.onOpen = { [weak self] link in self?.open(link) }
        model.onEdit = { [weak self] link in
            self?.hide()
            self?.onEdit?(link)
        }
        model.onAdd = { [weak self] prefill in
            self?.hide()
            self?.onAdd?(prefill)
        }
        model.onHeightChange = { [weak self] height in self?.resize(to: height) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible { hide() } else { show() }
    }

    func show() {
        model.isActive = true
        model.prepareForShow()

        let screen = Self.screenWithMouse()
        let visible = screen.visibleFrame
        let height = model.contentHeight
        let top = visible.maxY - visible.height * 0.2
        let frame = NSRect(
            x: (visible.midX - LauncherLayout.width / 2).rounded(),
            y: (top - height).rounded(),
            width: LauncherLayout.width,
            height: height
        )
        panel.setFrame(frame, display: false)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        guard panel.isVisible else { return }
        model.isActive = false
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    private func open(_ link: Link) {
        hide()
        guard let url = URL(string: link.url) else { return }
        NSWorkspace.shared.open(url)
        store.recordOpen(link.id)
    }

    private func resize(to height: CGFloat) {
        guard panel.isVisible, abs(panel.frame.height - height) > 0.5 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private static func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - NSWindowDelegate

    /// Klik mimo panel (jiné okno/aplikace) → zavřít.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Klávesnice

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                return self.handleKeyDown(event)
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private static let digitKeyCodes: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5,
        kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9,
    ]

    /// Vrací `true`, pokud událost zpracoval (a nemá se dál posílat).
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        if flags.contains(.command) {
            // Číslice podle fyzické klávesy – funguje i na české klávesnici (+ěščřžýáí).
            if let digit = Self.digitKeyCodes[keyCode] {
                model.open(at: digit - 1)
                return true
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                if hasTextSelection { return false }
                model.copySelected()
                return true
            case "e":
                model.editSelected()
                return true
            case "n":
                model.addNew()
                return true
            case "w":
                hide()
                return true
            // Panel nemá vlastní menu – standardní úpravy textu posíláme ručně.
            case "v":
                return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            case "x":
                return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
            case "a":
                return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
            case "z":
                let undo = flags.contains(.shift) ? Selector(("redo:")) : Selector(("undo:"))
                return NSApp.sendAction(undo, to: nil, from: self)
            default:
                return false
            }
        }

        switch keyCode {
        case kVK_DownArrow:
            model.moveSelection(by: 1)
            return true
        case kVK_UpArrow:
            model.moveSelection(by: -1)
            return true
        case kVK_PageDown:
            model.moveSelection(by: LauncherLayout.maxVisibleRows)
            return true
        case kVK_PageUp:
            model.moveSelection(by: -LauncherLayout.maxVisibleRows)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.openSelected()
            return true
        case kVK_Escape:
            hide()
            return true
        case kVK_Tab:
            model.completeTag()
            return true
        default:
            break
        }

        if flags.contains(.control) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "n", "j":
                model.moveSelection(by: 1)
                return true
            case "p", "k":
                model.moveSelection(by: -1)
                return true
            default:
                break
            }
        }
        return false
    }

    private var hasTextSelection: Bool {
        guard let editor = panel.firstResponder as? NSTextView else { return false }
        return editor.selectedRange().length > 0
    }
}
