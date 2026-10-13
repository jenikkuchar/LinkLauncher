import SwiftUI

/// Editor jednoho odkazu (nový / úprava). Zobrazuje se jako sheet v okně správy.
@MainActor
struct LinkEditorView: View {
    let mode: EditorMode
    @ObservedObject var store: LinkStore
    let favicons: FaviconStore
    let onClose: () -> Void

    @State private var title = ""
    @State private var urlText = ""
    @State private var tags: [String] = []
    @State private var isFetchingTitle = false
    @State private var didLoad = false
    @FocusState private var focusedField: Field?

    private enum Field { case title, url }

    private var editingID: Link.ID? {
        if case .edit(let id) = mode { return id }
        return nil
    }

    private var normalizedURL: String? { URLTools.normalize(urlText) }

    private var duplicate: Link? {
        guard let url = normalizedURL else { return nil }
        return store.duplicate(of: url, excluding: editingID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editingID == nil ? "Nový odkaz" : "Upravit odkaz")
                .font(.headline)
                .padding([.top, .horizontal], 20)

            Form {
                TextField("URL", text: $urlText, prompt: Text("https://…"))
                    .focused($focusedField, equals: .url)
                    .onSubmit { fetchTitleIfEmpty() }
                if !urlText.isEmpty && normalizedURL == nil {
                    Label("Neplatná URL", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                if let duplicate {
                    Label("Tato URL už je uložená jako „\(duplicate.displayTitle)“.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                HStack {
                    TextField("Název", text: $title, prompt: Text(isFetchingTitle ? "Načítám název stránky…" : "Název (prázdný = načíst ze stránky)"))
                        .focused($focusedField, equals: .title)
                    if isFetchingTitle {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            fetchTitle(force: true)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Načíst název ze stránky")
                        .disabled(normalizedURL == nil)
                    }
                }

                LabeledContent("Štítky") {
                    TagTokenField(tags: $tags, suggestions: store.allTags)
                        .frame(minHeight: 22)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Zrušit", role: .cancel) { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button(editingID == nil ? "Přidat" : "Uložit") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalizedURL == nil)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 520)
        .onAppear { loadInitialValues() }
        .onChange(of: focusedField) { old, _ in
            if old == .url { fetchTitleIfEmpty() }
        }
    }

    private func loadInitialValues() {
        guard !didLoad else { return }
        didLoad = true
        switch mode {
        case .edit(let id):
            if let link = store.link(withID: id) {
                title = link.title
                urlText = link.url
                tags = link.tags
            }
            focusedField = .title
        case .new(let prefill):
            urlText = prefill ?? ""
            focusedField = prefill == nil ? .url : .title
            if prefill != nil { fetchTitleIfEmpty() }
        }
    }

    private func fetchTitleIfEmpty() {
        guard title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        fetchTitle(force: false)
    }

    private func fetchTitle(force: Bool) {
        guard let url = normalizedURL, !isFetchingTitle else { return }
        isFetchingTitle = true
        Task {
            let fetched = await TitleFetcher.fetchTitle(for: url)
            isFetchingTitle = false
            if let fetched, force || title.trimmingCharacters(in: .whitespaces).isEmpty {
                title = fetched
            }
        }
    }

    private func save() {
        // Dokončit rozepsaný token ve štítcích.
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard let url = normalizedURL else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let savedID: Link.ID
        if let id = editingID, var link = store.link(withID: id) {
            link.title = cleanTitle
            link.url = url
            link.tags = tags
            store.update(link)
            savedID = id
        } else {
            let link = Link(title: cleanTitle, url: url, tags: tags)
            store.add(link)
            savedID = link.id
        }

        // Prázdný název – zkusit ho načíst ze stránky na pozadí.
        if cleanTitle.isEmpty {
            Task { @MainActor [store] in
                if let fetched = await TitleFetcher.fetchTitle(for: url) {
                    store.setFetchedTitle(fetched, for: savedID, ifCurrentTitle: "")
                }
            }
        }
        favicons.prefetch([url])
        onClose()
    }
}
