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
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .toggleLauncher)

    private var isDefaultShortcut: Bool {
        shortcut == KeyboardShortcuts.Name.toggleLauncher.defaultShortcut
    }

    private var defaultShortcutText: String {
        KeyboardShortcuts.Name.toggleLauncher.defaultShortcut.map { "\($0)" } ?? ""
    }

    var body: some View {
        Form {
            Section("Launcher") {
                LabeledContent("Klávesová zkratka") {
                    HStack(spacing: 8) {
                        KeyboardShortcuts.Recorder(for: .toggleLauncher) { newShortcut in
                            shortcut = newShortcut
                        }
                        .fixedSize()
                        Button("Obnovit výchozí") {
                            KeyboardShortcuts.reset(.toggleLauncher)
                            shortcut = KeyboardShortcuts.getShortcut(for: .toggleLauncher)
                        }
                        .disabled(isDefaultShortcut)
                        .help("Nastavit výchozí zkratku \(defaultShortcutText)")
                    }
                }
                if shortcut == nil {
                    Text("Zkratka není nastavená – launcher otevřete z ikony v menu baru.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Barvy štítků") {
                let tags = store.tagCounts
                if tags.isEmpty {
                    Text("Zatím žádné štítky.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(tags, id: \.tag) { item in
                                TagColorRow(
                                    tag: item.tag,
                                    count: item.count,
                                    selected: store.tagColor(for: item.tag)
                                ) { color in
                                    store.setTagColor(color, for: item.tag)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: min(CGFloat(tags.count) * 30 + 4, 240))
                }
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
        .environment(\.tagColors, store.tagColors)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            refreshLoginItem()
            shortcut = KeyboardShortcuts.getShortcut(for: .toggleLauncher)
        }
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
            let data = try LinkDatabaseCodec.encode(store.database)
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
            store.mergeTagColors(database.tagColors)
            message = "Přidáno: \(result.added), přeskočeno: \(result.skipped)."
        case .alertSecondButtonReturn:
            store.replaceAll(with: database)
            message = "Odkazy nahrazeny zálohou (\(linksCountText(database.links.count)))."
        default:
            break
        }
    }
}
