import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
struct SettingsView: View {
    @ObservedObject var store: LinkStore

    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemNeedsApproval = LoginItem.requiresApproval
    @State private var message: String?

    var body: some View {
        Form {
            Section("Launcher") {
                KeyboardShortcuts.Recorder("Klávesová zkratka:", name: .toggleLauncher)
            }

            Section("Systém") {
                Toggle("Spouštět po přihlášení", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if loginItemNeedsApproval {
                    HStack {
                        Text("Spouštění je potřeba povolit v Nastavení systému.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Otevřít Nastavení systému") {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                }
            }

            Section("Data") {
                LabeledContent("Umístění:") {
                    Text(store.fileURL.path)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Zobrazit ve Finderu") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                    }
                    Spacer()
                    Button("Exportovat zálohu…") { exportBackup() }
                    Button("Importovat zálohu…") { importBackup() }
                }
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { refreshLoginItem() }
    }

    private func refreshLoginItem() {
        launchAtLogin = LoginItem.isEnabled || LoginItem.requiresApproval
        loginItemNeedsApproval = LoginItem.requiresApproval
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            message = nil
        } catch {
            message = "Nepodařilo se změnit spouštění po přihlášení: \(error.localizedDescription)"
        }
        refreshLoginItem()
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let date = Date().formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "LinkLauncher-zaloha-\(date).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try LinkDatabaseCodec.encode(LinkDatabase(links: store.links))
            try data.write(to: url, options: .atomic)
            message = "Exportováno: \(linksCountText(store.links.count))."
        } catch {
            message = "Export se nezdařil: \(error.localizedDescription)"
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let database: LinkDatabase
        do {
            database = try LinkDatabaseCodec.decode(Data(contentsOf: url))
        } catch {
            message = "Soubor nelze načíst: \(LinkDatabaseCodec.describe(error))"
            return
        }

        let alert = NSAlert()
        alert.messageText = "Importovat \(linksCountText(database.links.count))?"
        alert.informativeText = "Sloučit: přidá odkazy s URL, které ještě nemáte.\nNahradit: smaže všechny současné odkazy a nahradí je zálohou."
        alert.addButton(withTitle: "Sloučit")
        alert.addButton(withTitle: "Nahradit vše")
        alert.addButton(withTitle: "Zrušit")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let result = store.merge(database.links)
            message = "Přidáno: \(result.added), přeskočeno: \(result.skipped)."
        case .alertSecondButtonReturn:
            store.replaceAll(with: database.links)
            message = "Odkazy nahrazeny zálohou (\(linksCountText(database.links.count)))."
        default:
            break
        }
    }
}
