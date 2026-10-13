import AppKit
import KeyboardShortcuts

/// Ikona v menu baru s nabídkou.
@MainActor
final class StatusBarController: NSObject {
    struct Actions {
        var openLauncher: () -> Void
        var manageLinks: () -> Void
        var importChrome: () -> Void
        var settings: () -> Void
    }

    private let statusItem: NSStatusItem
    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "link", accessibilityDescription: "LinkLauncher")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "LinkLauncher"
        }

        let menu = NSMenu()
        let open = item("Otevřít launcher", #selector(openLauncher))
        // Zobrazí aktuální zkratku a aktualizuje ji po změně v Nastavení.
        open.setShortcut(for: .toggleLauncher)
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(item("Spravovat odkazy…", #selector(manageLinks)))
        menu.addItem(item("Importovat záložky (HTML)…", #selector(importChrome)))
        menu.addItem(.separator())
        let settings = item("Nastavení…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Ukončit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openLauncher() {
        // Počkat, až se zavře menu, jinak by panel hned ztratil fokus.
        DispatchQueue.main.async { [actions] in actions.openLauncher() }
    }

    @objc private func manageLinks() { actions.manageLinks() }
    @objc private func importChrome() { actions.importChrome() }
    @objc private func openSettings() { actions.settings() }
}
