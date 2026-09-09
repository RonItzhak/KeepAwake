import AppKit
import Carbon

/// Process entry point. Menu-bar extra by default; a control window appears
/// when the app is opened from Applications.
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
    if !Self.launchedAsLoginItem {
      controller.showControlWindow()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    controller.showControlWindow()
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// Indicates whether this launch came from a login item rather than Finder.
  private static var launchedAsLoginItem: Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
    let prop = event.attributeDescriptor(forKeyword: AEKeyword(keyAEPropData))
    return prop?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
  }
}
