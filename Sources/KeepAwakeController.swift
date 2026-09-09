import AppKit
import ServiceManagement

/// Menu-bar extra that toggles lid-closed keep-awake on left-click.
///
/// The status icon is the mode: an orange coffee cup means keep-awake is on;
/// a moon means normal sleep. Right-click (or Control-click) opens a small menu.
@MainActor
final class KeepAwakeController: NSObject {
  /// Status item shown in the menu bar for the lifetime of the app. Nil only
  /// before `start()`; after that it stays retained so the extra does not vanish.
  private var statusItem: NSStatusItem?
  /// Indicates whether a toggle is already waiting on Touch ID / `pmset`.
  private var isBusy = false
  /// Timer that re-reads `pmset` so the icon stays correct if settings change
  /// elsewhere. Nil until `start()`, then repeating.
  private var refreshTimer: Timer?
  /// Last icon mode written to the debug log, so the 30s refresh does not spam.
  private var lastLoggedOn: Bool?

  /// Creates the menu-bar extra, paints the current mode, and opens at login.
  func start() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    if let button = item.button {
      button.imagePosition = .imageOnly
      button.target = self
      button.action = #selector(statusItemClicked(_:))
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    statusItem = item
    KeepAwakeLog.info("Keep Awake launched")
    refresh()
    enableLaunchAtLoginIfPossible()
    refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }

  @objc
  private func statusItemClicked(_ sender: Any?) {
    guard let event = NSApp.currentEvent else { return }
    if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
      showMenu()
    } else {
      toggle()
    }
  }

  @objc
  private func toggleMenuItemClicked(_ sender: Any?) {
    toggle()
  }

  @objc
  private func toggleLaunchAtLogin(_ sender: Any?) {
    let service = SMAppService.mainApp
    do {
      if service.status == .enabled {
        try service.unregister()
      } else {
        try service.register()
      }
    } catch {
      present(error)
    }
  }

  @objc
  private func openLog(_ sender: Any?) {
    NSWorkspace.shared.open(KeepAwakeLog.fileURL)
  }

  @objc
  private func quit(_ sender: Any?) {
    NSApp.terminate(nil)
  }

  private func toggle() {
    guard !isBusy else { return }
    isBusy = true
    Task { @MainActor in
      defer { isBusy = false }
      do {
        let currentlyOn = try PowerManager.currentSettings(logRaw: true).isKeepAwakeOn
        let reason = currentlyOn
          ? "Turn Keep Awake off and restore normal sleep."
          : "Turn Keep Awake on so the Mac stays awake with the lid closed."
        KeepAwakeLog.info("toggle clicked; currentlyOn=\(currentlyOn)")
        try await TouchAuth.confirm(reason: reason)
        try PowerManager.setKeepAwake(!currentlyOn)
        refresh()
      } catch PowerManager.PowerError.userCanceled {
        KeepAwakeLog.info("toggle canceled by user")
        refresh()
      } catch {
        KeepAwakeLog.error("toggle failed: \(error)")
        refresh()
        present(error)
      }
    }
  }

  private func refresh() {
    let isOn: Bool
    do {
      isOn = try PowerManager.currentSettings().isKeepAwakeOn
    } catch {
      isOn = false
    }
    if lastLoggedOn != isOn {
      KeepAwakeLog.info("icon \(isOn ? "ON" : "OFF")")
      lastLoggedOn = isOn
    }
    applyIcon(isOn: isOn)
  }

  private func applyIcon(isOn: Bool) {
    guard let button = statusItem?.button else { return }
    button.image = statusImage(isOn: isOn)
    button.toolTip = isOn
      ? "Keep Awake ON — Mac will not sleep with the lid closed. Click to restore normal sleep."
      : "Keep Awake OFF — normal sleep. Click to stay awake with the lid closed."
    button.setAccessibilityLabel(isOn ? "Keep Awake, on" : "Keep Awake, off")
  }

  private func statusImage(isOn: Bool) -> NSImage? {
    let symbolName = isOn ? "cup.and.saucer.fill" : "moon.zzz.fill"
    let description = isOn ? "Keep Awake on" : "Keep Awake off"
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    else {
      return nil
    }

    let sized = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
    let configured: NSImage.SymbolConfiguration
    if isOn {
      configured = sized.applying(.init(paletteColors: [.systemOrange]))
    } else {
      configured = sized
    }

    let image = base.withSymbolConfiguration(configured) ?? base
    image.isTemplate = !isOn
    return image
  }

  private func showMenu() {
    guard let button = statusItem?.button else { return }
    let isOn = (try? PowerManager.currentSettings().isKeepAwakeOn) ?? false

    let menu = NSMenu()
    let stateItem = NSMenuItem(
      title: isOn ? "Keep Awake is ON" : "Keep Awake is OFF",
      action: nil,
      keyEquivalent: ""
    )
    stateItem.isEnabled = false
    menu.addItem(stateItem)

    let toggleTitle = isOn ? "Restore Normal Sleep" : "Stay Awake with Lid Closed"
    menu.addItem(NSMenuItem(
      title: toggleTitle,
      action: #selector(toggleMenuItemClicked(_:)),
      keyEquivalent: ""
    ))
    menu.addItem(.separator())

    let loginItem = NSMenuItem(
      title: "Open at Login",
      action: #selector(toggleLaunchAtLogin(_:)),
      keyEquivalent: ""
    )
    loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    menu.addItem(loginItem)
    menu.addItem(NSMenuItem(
      title: "Open Debug Log",
      action: #selector(openLog(_:)),
      keyEquivalent: ""
    ))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit Keep Awake", action: #selector(quit(_:)), keyEquivalent: "q"))

    for item in menu.items where item.action != nil {
      item.target = self
    }

    let location = NSPoint(x: 0, y: button.bounds.height + 2)
    menu.popUp(positioning: nil, at: location, in: button)
  }

  private func enableLaunchAtLoginIfPossible() {
    guard SMAppService.mainApp.status != .enabled else { return }
    try? SMAppService.mainApp.register()
  }

  private func present(_ error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Could not change Keep Awake"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
