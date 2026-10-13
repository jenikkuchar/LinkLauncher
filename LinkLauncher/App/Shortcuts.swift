import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Globální zkratka pro zobrazení/skrytí launcheru (výchozí ⌘⇧Space).
    static let toggleLauncher = Self("toggleLauncher", default: .init(.space, modifiers: [.command, .shift]))
}
