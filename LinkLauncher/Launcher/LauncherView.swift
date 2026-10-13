import SwiftUI
import AppKit

@MainActor
struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var favicons: FaviconStore
    @Namespace private var selectionNamespace

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if model.isTagPickerOpen {
                tagPicker
            } else if !model.tagSuggestions.isEmpty {
                suggestionBar
            }
            if !model.results.isEmpty {
                Divider()
                resultsList
            } else if model.isTagPickerOpen {
                Divider()
                emptyState("Žádný štítek neodpovídá · Esc zavře výběr")
            } else if !model.query.isEmpty || !model.activeTags.isEmpty {
                Divider()
                emptyState("Nic nenalezeno · ⌘N přidá nový odkaz")
            } else {
                Divider()
                emptyState("Zatím žádné odkazy · ⌘N přidá nový")
            }
        }
        .frame(width: LauncherLayout.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .environment(\.tagColors, model.tagColors)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: model.isTagPickerOpen ? "tag" : "link")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
            ForEach(model.activeTags, id: \.self) { tag in
                ActiveTagToken(tag: tag) { model.removeActiveTag(tag) }
                    .transition(.scale.combined(with: .opacity))
            }
            LauncherSearchField(
                text: $model.query,
                focusToken: model.focusToken,
                placeholder: placeholder
            )
            .frame(height: 30)
            if let flash = model.flashMessage {
                Text(flash)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: LauncherLayout.searchHeight)
        .animation(.snappy(duration: 0.2), value: model.activeTags)
        // Tažením za lištu (mimo textové pole) jde panel přesunout.
        .background(WindowDragArea())
    }

    private var placeholder: String {
        if model.isTagPickerOpen { return "Filtrovat štítky…" }
        if let last = model.activeTags.last {
            return model.activeTags.count == 1 ? "Hledat v #\(last)…" : "Hledat ve vybraných štítcích…"
        }
        return "Hledat odkazy…"
    }

    /// Řada „bublin“ se štítky (Tab), podobně jako výběr kategorie ve Spotlightu.
    private var tagPicker: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(model.pickerTags.enumerated()), id: \.element.id) { index, item in
                        TagBubble(
                            tag: item.tag,
                            count: item.count,
                            isHighlighted: index == model.pickerIndex
                        )
                        .id(item.tag)
                        .onTapGesture { model.applyTag(item.tag) }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
            }
            .frame(height: LauncherLayout.tagPickerHeight)
            .animation(.snappy(duration: 0.18), value: model.pickerIndex)
            .onChange(of: model.pickerIndex) { _, _ in
                if let tag = model.highlightedPickerTag {
                    withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo(tag, anchor: .center) }
                }
            }
        }
    }

    private var suggestionBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.tagSuggestions.enumerated()), id: \.element) { index, tag in
                Button {
                    model.completeTag(tag)
                } label: {
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                        if index == 0 {
                            Text("⇥").foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .liquidGlass(
                        in: Capsule(),
                        tint: index == 0 ? Color.accentColor.opacity(0.35) : nil,
                        interactive: true,
                        fallback: Color.accentColor.opacity(index == 0 ? 0.25 : 0.12)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(height: LauncherLayout.suggestionsHeight, alignment: .top)
    }

    private var resultsList: some View {
        let visibleRows = CGFloat(min(model.results.count, LauncherLayout.maxVisibleRows))
        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: model.results.count > LauncherLayout.maxVisibleRows) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, link in
                        LauncherRow(
                            link: link,
                            index: index,
                            isSelected: index == model.selectedIndex,
                            favicon: URLTools.host(of: link.url).flatMap { favicons.image(forHost: $0) }
                        )
                        .background {
                            if index == model.selectedIndex {
                                SelectionHighlight()
                                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                            }
                        }
                        .id(link.id)
                        .contentShape(Rectangle())
                        .onTapGesture { model.open(at: index) }
                        .task(id: link.url) { await favicons.load(for: link.url) }
                    }
                }
                .padding(LauncherLayout.listPadding)
                .animation(.easeOut(duration: 0.12), value: model.selectedIndex)
            }
            .frame(height: visibleRows * LauncherLayout.rowHeight + LauncherLayout.listPadding * 2)
            .onChange(of: model.selectedIndex) { _, index in
                guard model.results.indices.contains(index) else { return }
                proxy.scrollTo(model.results[index].id)
            }
            .onChange(of: model.query) { _, _ in
                if let first = model.results.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: LauncherLayout.emptyHeight)
    }
}

@MainActor
struct LauncherRow: View {
    let link: Link
    let index: Int
    let isSelected: Bool
    let favicon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(image: favicon)
            VStack(alignment: .leading, spacing: 1) {
                Text(link.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(link.domain)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(link.tags.prefix(4), id: \.self) { tag in
                    TagChip(tag: tag, inverted: isSelected)
                }
            }
            .layoutPriority(-1)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.white.opacity(0.8)) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: LauncherLayout.rowHeight)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
    }
}

@MainActor
struct FaviconView: View {
    let image: NSImage?
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

@MainActor
struct TagChip: View {
    let tag: String
    var inverted = false
    @Environment(\.tagColors) private var tagColors

    var body: some View {
        let color = tagColors.tagColor(for: tag)?.color
        HStack(spacing: 4) {
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().strokeBorder(Color.white.opacity(inverted ? 0.7 : 0), lineWidth: 0.5))
            }
            Text(tag)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(
                inverted
                    ? Color.white.opacity(0.25)
                    : (color?.opacity(0.2) ?? Color.secondary.opacity(0.15))
            )
        )
    }
}

/// Jednořádkové pole bez rámečku. Klávesy (šipky, Enter, Esc, Tab, ⌘…) zachytává `LauncherController`.
struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var placeholder = "Hledat odkazy…"

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .light)
        field.placeholderString = placeholder
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.placeholderString != placeholder {
            field.placeholderString = placeholder
        }
        if field.stringValue != text {
            field.stringValue = text
            if let editor = field.currentEditor() {
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LauncherSearchField
        var lastFocusToken = -1

        init(parent: LauncherSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }
    }
}

/// Oblast, za kterou jde okno přetáhnout (panel jinak nemá titulek).
/// Pozice se nepamatuje – při dalším otevření je launcher opět ve výchozím místě.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

/// Štítek zvolený přes Tab – token vlevo ve vyhledávacím poli (klik na × ho odebere).
@MainActor
struct ActiveTagToken: View {
    let tag: String
    let onRemove: () -> Void
    @Environment(\.tagColors) private var tagColors

    var body: some View {
        // Bez nastavené barvy neutrální šedá (ne modrá).
        let tint = tagColors.tagColor(for: tag)?.color ?? Color.gray
        HStack(spacing: 4) {
            Image(systemName: "tag.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(tag)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .help("Odebrat štítek (⌫)")
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .liquidGlass(in: Capsule(), tint: tint.opacity(0.25), fallback: tint.opacity(0.2))
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
        .fixedSize()
    }
}

/// Bublina se štítkem v řadě výběru (Tab). Zvýrazněná je tónovaná a mírně zvětšená.
@MainActor
struct TagBubble: View {
    let tag: String
    let count: Int
    let isHighlighted: Bool
    @Environment(\.tagColors) private var tagColors

    var body: some View {
        let tagColor = tagColors.tagColor(for: tag)?.color
        HStack(spacing: 6) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(
                    tagColor.map { AnyShapeStyle($0) }
                        ?? (isHighlighted ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                )
            Text(tag)
                .font(.system(size: 13, weight: isHighlighted ? .semibold : .medium))
                .lineLimit(1)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(isHighlighted ? Color.primary : Color.secondary)
        .padding(.horizontal, 12)
        .frame(height: 30)
        // Zvýraznění jen jemně (obrys), aby se nebilo s modrým výběrem odkazu.
        .liquidGlass(
            in: Capsule(),
            tint: isHighlighted ? Color.white.opacity(0.12) : nil,
            interactive: true,
            fallback: Color.secondary.opacity(isHighlighted ? 0.22 : 0.1)
        )
        // Obrys v barvě štítku; štítky bez barvy mají neutrální obrys.
        .overlay(
            Capsule().strokeBorder(
                (tagColor ?? Color.primary).opacity(isHighlighted ? (tagColor == nil ? 0.45 : 0.9) : 0),
                lineWidth: 1.5
            )
        )
        .fixedSize()
    }
}
