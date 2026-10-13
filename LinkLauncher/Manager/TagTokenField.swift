import SwiftUI
import AppKit

/// Štítky jako tokeny (NSTokenField) s našeptáváním existujících štítků.
struct TagTokenField: NSViewRepresentable {
    @Binding var tags: [String]
    var suggestions: [String]
    var placeholder = "Štítky (oddělte mezerou nebo čárkou)"

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTokenField {
        let field = NSTokenField()
        field.delegate = context.coordinator
        field.tokenizingCharacterSet = CharacterSet(charactersIn: ", ")
        field.completionDelay = 0
        field.placeholderString = placeholder
        field.objectValue = tags
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTokenField, context: Context) {
        context.coordinator.parent = self
        let current = Coordinator.tags(of: field)
        if field.currentEditor() == nil, current != tags {
            field.objectValue = tags
        }
    }

    final class Coordinator: NSObject, NSTokenFieldDelegate {
        var parent: TagTokenField

        init(parent: TagTokenField) {
            self.parent = parent
        }

        static func tags(of field: NSTokenField) -> [String] {
            let raw = (field.objectValue as? [Any])?.compactMap { $0 as? String } ?? []
            return Tag.normalizeList(raw)
        }

        private func sync(_ field: NSTokenField) {
            let tags = Self.tags(of: field)
            if tags != parent.tags {
                parent.tags = tags
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTokenField { sync(field) }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if let field = obj.object as? NSTokenField { sync(field) }
        }

        func tokenField(
            _ tokenField: NSTokenField,
            completionsForSubstring substring: String,
            indexOfToken tokenIndex: Int,
            indexOfSelectedItem selectedIndex: UnsafeMutablePointer<Int>?
        ) -> [Any]? {
            let prefix = TextFolding.fold(Tag.normalize(substring))
            guard !prefix.isEmpty else { return [] }
            let existing = Set(Self.tags(of: tokenField))
            let matches = parent.suggestions.filter {
                !existing.contains($0) && TextFolding.fold($0).hasPrefix(prefix)
            }
            selectedIndex?.pointee = matches.isEmpty ? -1 : 0
            return matches
        }

        func tokenField(_ tokenField: NSTokenField, shouldAdd tokens: [Any], at index: Int) -> [Any] {
            tokens.compactMap { token in
                guard let s = token as? String else { return nil }
                let normalized = Tag.normalize(s)
                return normalized.isEmpty ? nil : normalized
            }
        }
    }
}
