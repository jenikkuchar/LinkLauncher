import AppKit
import Combine
import KeyboardShortcuts

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: LinkStore?
    private var windows: WindowManager?
    private var launcher: LauncherController?
    private var statusBar: StatusBarController?
    private var cancellables = Set<AnyCancellable>()
    private var lastShownError: String?

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }

        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = MainMenu.make()

        let store = LinkStore()
        store.load()
        store.startWatching()
        self.store = store

        let favicons = FaviconStore()
        let windows = WindowManager(store: store, favicons: favicons)
        self.windows = windows

        let launcher = LauncherController(store: store, favicons: favicons)
        launcher.onEdit = { [weak windows] link in
            windows?.showManager(request: EditorRequest(mode: .edit(link.id)))
        }
        launcher.onAdd = { [weak windows] prefill in
            windows?.showManager(request: EditorRequest(mode: .new(prefillURL: prefill)))
        }
        self.launcher = launcher

        KeyboardShortcuts.onKeyDown(for: .toggleLauncher) { [weak launcher] in
            MainActor.assumeIsolated {
                launcher?.toggle()
            }
        }

        statusBar = StatusBarController(actions: .init(
            openLauncher: { [weak launcher] in launcher?.show() },
            manageLinks: { [weak windows] in windows?.showManager() },
            importChrome: { [weak windows] in windows?.showImport() },
            settings: { [weak windows] in windows?.showSettings() }
        ))

        store.$fileError
            .removeDuplicates()
            .sink { [weak self] error in
                // Zobrazit až po dokončení aktuální změny stavu.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.showFileError(error) }
                }
            }
            .store(in: &cancellables)

        LoginItem.enableOnFirstLaunch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windows?.showManager()
        return true
    }

    @objc func showSettings(_ sender: Any?) {
        windows?.showSettings()
    }

    private func showFileError(_ error: String?) {
        guard let error, error != lastShownError, let store else {
            if error == nil { lastShownError = nil }
            return
        }
        lastShownError = error
        launcher?.hide()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Problém se souborem s odkazy"
        alert.informativeText = error
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Zobrazit ve Finderu")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        }
    }
}
