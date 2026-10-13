import AppKit

@main
enum LinkLauncherMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}
