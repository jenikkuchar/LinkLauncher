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
            if !model.tagSuggestions.isEmpty {
                suggestionBar
            }
            if !model.results.isEmpty {
                Divider()
                resultsList
            } else if !model.query.isEmpty {
                Divider()
                emptyState("Nic nenalezeno · ⌘N přidá nový odkaz")
            } else {
                Divider()
                emptyState("Zatím žádné odkazy · ⌘N přidá nový")
            }
        }
        .frame(width: LauncherLayout.width)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            LauncherSearchField(text: $model.query, focusToken: model.focusToken)
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
        // Tažením za lištu (mimo textové pole) jde panel přesunout.
        .background(WindowDragArea())
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

    var body: some View {
        Text(tag)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(inverted ? Color.white.opacity(0.25) : Color.secondary.opacity(0.15))
            )
    }
}

/// Jednořádkové pole bez rámečku. Klávesy (šipky, Enter, Esc, Tab, ⌘…) zachytává `LauncherController`.
struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 22, weight: .light)
        field.placeholderString = "Hledat odkazy…   (#štítek filtruje)"
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
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
