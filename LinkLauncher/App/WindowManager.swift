import AppKit
import SwiftUI

/// Vytváří a zobrazuje standardní okna aplikace (správa odkazů, import, nastavení).
@MainActor
final class WindowManager: NSObject {
    private let store: LinkStore
    private let favicons: FaviconStore
    let managerState: ManagerState

    private var managerWindow: NSWindow?
    private var importWindow: NSWindow?
    private var settingsWindow: NSWindow?

    init(store: LinkStore, favicons: FaviconStore) {
        self.store = store
        self.favicons = favicons
        managerState = ManagerState()
        super.init()
    }

    func showManager(request: EditorRequest? = nil) {
        let window: NSWindow
        if let existing = managerWindow {
            window = existing
        } else {
            window = makeWindow(
                title: "Spravovat odkazy",
                size: NSSize(width: 960, height: 580),
                autosaveName: "LinkLauncher.Manager",
                resizable: true,
                rootView: ManagerView(
                    store: store,
                    favicons: favicons,
                    state: managerState,
                    onImport: { [weak self] in self?.showImport() }
                )
            )
            managerWindow = window
        }
        if let request {
            managerState.editorRequest = request
        }
        present(window)
    }

    func showImport() {
        let window: NSWindow
        if let existing = importWindow {
            window = existing
        } else {
            window = makeWindow(
                title: "Import z Chrome",
                size: NSSize(width: 640, height: 600),
                autosaveName: "LinkLauncher.Import",
                resizable: true,
                rootView: ChromeImportView(store: store, favicons: favicons)
            )
            importWindow = window
        }
        present(window)
    }

    func showSettings() {
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = makeWindow(
                title: "Nastavení",
                size: NSSize(width: 520, height: 420),
                autosaveName: "LinkLauncher.Settings",
                resizable: false,
                rootView: SettingsView(store: store)
            )
            settingsWindow = window
        }
        present(window)
    }

    private func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        autosaveName: String,
        resizable: Bool,
        rootView: Content
    ) -> NSWindow {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = resizable ? [.minSize] : [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        if resizable {
            window.setContentSize(size)
        }
        window.center()
        window.setFrameAutosaveName(autosaveName)
        return window
    }
}
