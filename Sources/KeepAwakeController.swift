import AppKit
import ServiceManagement

/// Menu-bar extra that toggles lid-closed keep-awake on left-click.
///
/// The status icon is the mode: an orange coffee cup means keep-awake is on;
/// a moon means normal sleep. Right-click (or Control-click) opens a small menu.
/// Opening the app from Applications (or clicking it again while it is running)
/// shows a control window, because the menu-bar extra is often hidden in overflow.
@MainActor
final class KeepAwakeController: NSObject, NSWindowDelegate {
  /// Status item shown in the menu bar for the lifetime of the app. Nil only
  /// before `start()`; after that it stays retained so the extra does not vanish.
  private var statusItem: NSStatusItem?
  /// Control window shown when the app is opened from Applications. Nil until
  /// the first reopen; reused after that so close does not destroy it.
  private var controlWindow: NSWindow?
  /// Large mode icon inside the control window. Nil until the window is built.
  private var windowIconView: NSImageView?
  /// Status sentence inside the control window. Nil until the window is built.
  private var windowStatusLabel: NSTextField?
  /// Toggle button inside the control window. Nil until the window is built.
  private var windowToggleButton: NSButton?
  /// Open-at-login checkbox inside the control window. Nil until the window is built.
  private var windowLoginButton: NSButton?
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

  /// Brings up the control window. Used when the menu-bar extra is hidden in
  /// the overflow, or when the user opens Keep Awake from Applications.
  func showControlWindow() {
    KeepAwakeLog.info("showing control window")
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    if controlWindow == nil {
      controlWindow = makeControlWindow()
    }
    refresh()
    controlWindow?.makeKeyAndOrderFront(nil)
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
    refresh()
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
        if PowerManager.hasPasswordlessAccess {
          try await TouchAuth.confirm(reason: reason)
        } else {
          KeepAwakeLog.info("skipping Touch ID; one-time admin setup is required")
        }
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
    applyWindow(isOn: isOn)
  }

  func windowWillClose(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }

  private func applyWindow(isOn: Bool) {
    guard controlWindow != nil else { return }
    windowIconView?.image = statusImage(isOn: isOn, pointSize: 48)
    windowStatusLabel?.stringValue = isOn
      ? "Keep Awake is ON. The Mac will not sleep with the lid closed."
      : "Keep Awake is OFF. Sleep behaves normally."
    windowToggleButton?.title = isOn ? "Restore Normal Sleep" : "Stay Awake with Lid Closed"
    windowLoginButton?.state = SMAppService.mainApp.status == .enabled ? .on : .off
  }

  private func applyIcon(isOn: Bool) {
    guard let button = statusItem?.button else { return }
    button.image = statusImage(isOn: isOn)
    button.toolTip = isOn
      ? "Keep Awake ON — Mac will not sleep with the lid closed. Click to restore normal sleep."
      : "Keep Awake OFF — normal sleep. Click to stay awake with the lid closed."
    button.setAccessibilityLabel(isOn ? "Keep Awake, on" : "Keep Awake, off")
  }

  private func statusImage(isOn: Bool, pointSize: CGFloat = 16) -> NSImage? {
    let symbolName = isOn ? "cup.and.saucer.fill" : "moon.zzz.fill"
    let description = isOn ? "Keep Awake on" : "Keep Awake off"
    guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
    else {
      return nil
    }

    let sized = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
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

  private func makeControlWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 320, height: 300),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "Keep Awake"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()

    let iconView = NSImageView()
    iconView.translatesAutoresizingMaskIntoConstraints = false
    iconView.imageScaling = .scaleProportionallyUpOrDown
    windowIconView = iconView

    let status = NSTextField(wrappingLabelWithString: "Keep Awake")
    status.alignment = .center
    status.preferredMaxLayoutWidth = 280
    status.translatesAutoresizingMaskIntoConstraints = false
    windowStatusLabel = status

    let toggle = NSButton(title: "Toggle", target: self, action: #selector(toggleMenuItemClicked(_:)))
    toggle.bezelStyle = .rounded
    toggle.translatesAutoresizingMaskIntoConstraints = false
    windowToggleButton = toggle

    let login = NSButton(
      checkboxWithTitle: "Open at Login",
      target: self,
      action: #selector(toggleLaunchAtLogin(_:))
    )
    login.translatesAutoresizingMaskIntoConstraints = false
    windowLoginButton = login

    let log = NSButton(title: "Open Debug Log", target: self, action: #selector(openLog(_:)))
    log.bezelStyle = .rounded
    log.translatesAutoresizingMaskIntoConstraints = false

    let quit = NSButton(title: "Quit Keep Awake", target: self, action: #selector(quit(_:)))
    quit.bezelStyle = .rounded
    quit.translatesAutoresizingMaskIntoConstraints = false

    let stack = NSStackView(views: [iconView, status, toggle, login, log, quit])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false

    guard let content = window.contentView else { return window }
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 48),
      iconView.heightAnchor.constraint(equalToConstant: 48),
      toggle.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])
    return window
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
