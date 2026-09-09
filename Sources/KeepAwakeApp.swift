import AppKit

/// Process entry point. Hosts the menu-bar extra and never shows a Dock icon.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Owns the menu-bar extra for the whole process lifetime.
  private let controller = KeepAwakeController()

  static func main() {
    if CommandLine.arguments.contains("--self-check") {
      PowerManager.runSelfCheck()
      return
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    controller.start()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }
}
