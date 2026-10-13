import SwiftUI

enum TagSheet: Identifiable, Hashable {
    case rename(String)
    case merge(String)
    case addToSelection

    var id: String {
        switch self {
        case .rename(let tag): return "rename-\(tag)"
        case .merge(let tag): return "merge-\(tag)"
        case .addToSelection: return "add"
        }
    }
}

/// Přejmenování, sloučení štítku a hromadné přidání štítku vybraným odkazům.
@MainActor
struct TagSheetView: View {
    let sheet: TagSheet
    @ObservedObject var store: LinkStore
    let selection: Set<Link.ID>
    /// Parametr = štítek, který se má vybrat v sidebaru (po přejmenování/sloučení).
    let onClose: (String?) -> Void

    @State private var text = ""
    @State private var mergeTarget = ""

    private var normalized: String { Tag.normalize(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { onClose(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            switch sheet {
            case .rename(let tag): text = tag
            case .merge(let tag): mergeTarget = store.allTags.first { $0 != tag } ?? ""
            case .addToSelection: break
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .rename(let tag):
            Text("Přejmenovat štítek „\(tag)“").font(.headline)
            TextField("Nový název", text: $text)
                .textFieldStyle(.roundedBorder)
            if normalized != tag, store.allTags.contains(normalized) {
                Label("Štítek „\(normalized)“ už existuje – štítky se sloučí.", systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .merge(let tag):
            Text("Sloučit štítek „\(tag)“").font(.headline)
            let others = store.allTags.filter { $0 != tag }
            if others.isEmpty {
                Text("Žádný jiný štítek neexistuje.").foregroundStyle(.secondary)
            } else {
                Picker("Do štítku:", selection: $mergeTarget) {
                    ForEach(others, id: \.self) { Text($0).tag($0) }
                }
                Text("Odkazy se štítkem „\(tag)“ dostanou štítek „\(mergeTarget)“ a štítek „\(tag)“ zanikne.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .addToSelection:
            Text("Nový štítek pro \(linksCountText(selection.count))").font(.headline)
            TextField("Štítek", text: $text)
                .textFieldStyle(.roundedBorder)
            let suggestions = store.allTags.filter {
                normalized.isEmpty || TextFolding.fold($0).hasPrefix(TextFolding.fold(normalized))
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions.prefix(30), id: \.self) { tag in
                            Button { text = tag } label: { TagChip(tag: tag) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var confirmTitle: String {
        switch sheet {
        case .rename: return "Přejmenovat"
        case .merge: return "Sloučit"
        case .addToSelection: return "Přidat"
        }
    }

    private var isValid: Bool {
        switch sheet {
        case .rename(let tag): return !normalized.isEmpty && normalized != tag
        case .merge(let tag): return !mergeTarget.isEmpty && mergeTarget != tag
        case .addToSelection: return !normalized.isEmpty && !selection.isEmpty
        }
    }

    private func apply() {
        guard isValid else { return }
        switch sheet {
        case .rename(let tag):
            store.renameTag(tag, to: normalized)
            onClose(normalized)
        case .merge(let tag):
            store.mergeTag(tag, into: mergeTarget)
            onClose(mergeTarget)
        case .addToSelection:
            store.addTag(normalized, to: selection)
            onClose(nil)
        }
    }
}
