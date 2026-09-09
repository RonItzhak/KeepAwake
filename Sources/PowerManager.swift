import Foundation

/// Reads and writes the lid-closed keep-awake power settings (`pmset`).
///
/// ON matches the Desktop "Keep Awake - ON" script: no lid-close sleep, and no
/// AC system/disk sleep. OFF restores the AC values saved when keep-awake was
/// turned on, or Apple defaults if no backup exists.
enum PowerManager {
  /// Current sleep values parsed from `pmset`.
  struct ACSettings: Equatable {
    /// Minutes of inactivity before system sleep. `0` means never.
    let sleep: Int
    /// Minutes of inactivity before disk sleep. `0` means never.
    let disksleep: Int
    /// `1` when lid-close sleep is disabled; `0` when the lid can sleep the Mac.
    /// `-1` when `pmset` did not print the key (treated as unknown, not off).
    let disablesleep: Int

    /// Indicates whether keep-awake is active: lid-close sleep disabled, or the
    /// AC profile is set to never sleep. Live battery idle values are ignored,
    /// so the mode stays correct while unplugged.
    var isKeepAwakeOn: Bool {
      disablesleep == 1 || (sleep == 0 && disksleep == 0)
    }
  }

  /// Failure while reading or changing power settings.
  enum PowerError: LocalizedError {
    case pmsetReadFailed
    case pmsetWriteFailed(String)
    case userCanceled

    var errorDescription: String? {
      switch self {
      case .pmsetReadFailed:
        return "Could not read current energy settings."
      case .pmsetWriteFailed(let detail):
        return detail
      case .userCanceled:
        return nil
      }
    }
  }

  private static let pmset = "/usr/bin/pmset"
  private static let backupURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".pmset-lidclosed-backup")
  private static let defaultSleep = 5
  private static let defaultDisksleep = 10

  /// Current sleep settings. Used to choose the menu-bar icon and to snapshot
  /// values before keep-awake is turned on. Unknown `disablesleep` is `-1`.
  ///
  /// - Parameter logRaw: When true, dumps full `pmset` output into the debug log.
  static func currentSettings(logRaw: Bool = false) throws -> ACSettings {
    let custom = try run(executable: pmset, arguments: ["-g", "custom"])
    let live = try run(executable: pmset, arguments: ["-g"])
    if logRaw {
      KeepAwakeLog.info("pmset -g custom:\n\(custom)")
      KeepAwakeLog.info("pmset -g:\n\(live)")
    }
    return merge(custom: parseCustom(custom), live: parseLive(live))
  }

  /// Indicates whether `/usr/bin/pmset` can already run via passwordless sudo.
  /// Used to skip Touch ID on a machine that still needs the one-time admin setup.
  static var hasPasswordlessAccess: Bool {
    let result = spawn(executable: "/usr/bin/sudo", arguments: ["-n", pmset])
    return !result.output.lowercased().contains("password is required")
  }

  /// Turns lid-closed keep-awake on or off after Touch ID. Runs `pmset` via the
  /// installed passwordless sudoers rule. If that rule is missing, prompts once
  /// with the system admin dialog to install it.
  static func setKeepAwake(_ on: Bool) throws {
    KeepAwakeLog.info("setKeepAwake(\(on))")
    if on {
      try turnOn()
    } else {
      try turnOff()
    }
    let after = try currentSettings(logRaw: true)
    KeepAwakeLog.info(
      "after toggle: sleep=\(after.sleep) disksleep=\(after.disksleep) " +
        "disablesleep=\(after.disablesleep) on=\(after.isKeepAwakeOn)"
    )
  }

  /// Parses `pmset -g custom` output. Exposed for `--self-check`.
  static func parseCustom(_ output: String) -> ACSettings {
    parseBlocks(output, startWhenLineEquals: "AC Power:")
  }

  /// Parses `pmset -g` live output. Exposed for `--self-check`.
  static func parseLive(_ output: String) -> ACSettings {
    parseBlocks(output, startWhenLineEquals: nil)
  }

  /// Runs parser assertions. Used by `build.sh` as a smoke check.
  static func runSelfCheck() {
    let withFlag = parseCustom(
      """
      AC Power:
       sleep                5
       disksleep            10
       disablesleep         1
      Battery Power:
       sleep                1
      """
    )
    let omitted = parseCustom(
      """
      AC Power:
       Sleep On Power Button 1
       sleep                1
       disksleep            10
      Battery Power:
       sleep                1
      """
    )
    let live = parseLive(
      """
      Currently in use:
       sleep                0
       disksleep            0
      """
    )
    let unplugged = parseLive(
      """
      System-wide power settings:
       SleepDisabled		1
      Currently in use:
       sleep                1
       disksleep            10
      """
    )
    let mergedUnplugged = merge(
      custom: ACSettings(sleep: 0, disksleep: 0, disablesleep: -1),
      live: unplugged
    )
    precondition(withFlag == ACSettings(sleep: 5, disksleep: 10, disablesleep: 1))
    precondition(omitted == ACSettings(sleep: 1, disksleep: 10, disablesleep: -1))
    precondition(live == ACSettings(sleep: 0, disksleep: 0, disablesleep: -1))
    precondition(live.isKeepAwakeOn)
    precondition(unplugged.disablesleep == 1)
    precondition(unplugged.isKeepAwakeOn)
    precondition(mergedUnplugged == ACSettings(sleep: 0, disksleep: 0, disablesleep: 1))
    precondition(mergedUnplugged.isKeepAwakeOn)
    fputs("keepawake self-check ok\n", stdout)
  }

  private static func merge(custom: ACSettings, live: ACSettings) -> ACSettings {
    let disablesleep: Int
    if custom.disablesleep == 1 || live.disablesleep == 1 {
      disablesleep = 1
    } else if custom.disablesleep != -1 {
      disablesleep = custom.disablesleep
    } else {
      disablesleep = live.disablesleep
    }
    return ACSettings(
      sleep: custom.sleep,
      disksleep: custom.disksleep,
      disablesleep: disablesleep
    )
  }

  private static func parseBlocks(_ output: String, startWhenLineEquals: String?) -> ACSettings {
    var inSection = startWhenLineEquals == nil
    var sleep = defaultSleep
    var disksleep = defaultDisksleep
    var disablesleep = -1

    for rawLine in output.components(separatedBy: .newlines) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if let startWhenLineEquals, line == startWhenLineEquals {
        inSection = true
        continue
      }
      if startWhenLineEquals != nil, line.hasSuffix(":") {
        inSection = false
        continue
      }
      guard inSection else { continue }

      let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard parts.count >= 2, let value = Int(parts[1]) else { continue }
      switch parts[0] {
      case "sleep":
        sleep = value
      case "disksleep":
        disksleep = value
      case "disablesleep", "SleepDisabled":
        disablesleep = value
      default:
        break
      }
    }

    return ACSettings(sleep: sleep, disksleep: disksleep, disablesleep: disablesleep)
  }

  /// Parses the Battery Power block of `pmset -g custom`.
  static func parseBattery(_ output: String) -> ACSettings {
    parseBlocks(output, startWhenLineEquals: "Battery Power:")
  }

  private static func turnOn() throws {
    try saveBackupIfNeeded()
    try runPmset([
      ["-a", "disablesleep", "1"],
      ["-a", "sleep", "0"],
      ["-a", "disksleep", "0"],
    ])
  }

  private static func turnOff() throws {
    let restored = loadBackup()
    let ac = restored?.ac ?? ACSettings(
      sleep: defaultSleep,
      disksleep: defaultDisksleep,
      disablesleep: 0
    )
    let battery = restored?.battery ?? ACSettings(
      sleep: 1,
      disksleep: defaultDisksleep,
      disablesleep: 0
    )
    try runPmset([
      ["-a", "disablesleep", "0"],
      ["-c", "sleep", String(ac.sleep)],
      ["-c", "disksleep", String(ac.disksleep)],
      ["-b", "sleep", String(battery.sleep)],
      ["-b", "disksleep", String(battery.disksleep)],
    ])
    try? FileManager.default.removeItem(at: backupURL)
  }

  private static func saveBackupIfNeeded() throws {
    guard !FileManager.default.fileExists(atPath: backupURL.path) else {
      KeepAwakeLog.info("backup already exists at \(backupURL.path)")
      return
    }
    let custom = try run(executable: pmset, arguments: ["-g", "custom"])
    let ac = parseCustom(custom)
    let battery = parseBattery(custom)
    let body = [
      "sleep=\(ac.sleep)",
      "disksleep=\(ac.disksleep)",
      "disablesleep=\(max(ac.disablesleep, 0))",
      "battery_sleep=\(battery.sleep)",
      "battery_disksleep=\(battery.disksleep)",
      "",
    ].joined(separator: "\n")
    try body.write(to: backupURL, atomically: true, encoding: .utf8)
    KeepAwakeLog.info("wrote backup:\n\(body)")
  }

  private static func loadBackup() -> (ac: ACSettings, battery: ACSettings)? {
    guard let raw = try? String(contentsOf: backupURL, encoding: .utf8) else { return nil }
    KeepAwakeLog.info("loaded backup:\n\(raw)")
    var sleep = defaultSleep
    var disksleep = defaultDisksleep
    var disablesleep = 0
    var batterySleep = 1
    var batteryDisksleep = defaultDisksleep
    for line in raw.components(separatedBy: .newlines) {
      let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
      guard parts.count == 2, let value = Int(parts[1]) else { continue }
      switch parts[0] {
      case "sleep":
        sleep = value
      case "disksleep":
        disksleep = value
      case "disablesleep":
        disablesleep = value
      case "battery_sleep":
        batterySleep = value
      case "battery_disksleep":
        batteryDisksleep = value
      default:
        break
      }
    }
    return (
      ACSettings(sleep: sleep, disksleep: disksleep, disablesleep: disablesleep),
      ACSettings(sleep: batterySleep, disksleep: batteryDisksleep, disablesleep: 0)
    )
  }

  private static func runPmset(_ commands: [[String]]) throws {
    if tryRunPasswordless(commands) {
      KeepAwakeLog.info("pmset ran via passwordless sudo")
      return
    }
    KeepAwakeLog.info("passwordless sudo missing; installing sudoers via admin dialog")
    try installSudoersViaAdminDialog()
    if tryRunPasswordless(commands) {
      KeepAwakeLog.info("pmset ran via passwordless sudo after sudoers install")
      return
    }
    throw PowerError.pmsetWriteFailed(
      "Could not change energy settings. Admin setup did not stick."
    )
  }

  private static func installSudoersViaAdminDialog() throws {
    guard let helper = Bundle.main.url(forResource: "install-pmset-sudoers", withExtension: "sh")
    else {
      throw PowerError.pmsetWriteFailed("Keep Awake is missing its setup helper.")
    }
    let command = "/bin/bash \(shQuote(helper.path))"
    let source =
      "do shell script \(asQuote(command)) with prompt " +
      asQuote("Keep Awake needs a one-time admin approval to change energy settings.") +
      " with administrator privileges"
    KeepAwakeLog.info("NSAppleScript sudoers install: \(source)")

    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      throw PowerError.pmsetWriteFailed("Could not build the privilege prompt.")
    }
    _ = script.executeAndReturnError(&error)
    if let error {
      KeepAwakeLog.error("NSAppleScript sudoers error: \(error)")
      let code = (error[NSAppleScript.errorNumber] as? Int)
        ?? (error["NSAppleScriptErrorNumber"] as? Int)
        ?? 0
      if code == -128 {
        throw PowerError.userCanceled
      }
      let message = (error[NSAppleScript.errorMessage] as? String)
        ?? (error["NSAppleScriptErrorMessage"] as? String)
        ?? "Could not complete admin setup."
      throw PowerError.pmsetWriteFailed(message)
    }
  }

  private static func shQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
  }

  private static func asQuote(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  private static func tryRunPasswordless(_ commands: [[String]]) -> Bool {
    for args in commands {
      let result = spawn(executable: "/usr/bin/sudo", arguments: ["-n", pmset] + args)
      KeepAwakeLog.info(
        "sudo -n pmset \(args.joined(separator: " ")): status=\(result.status)\n\(result.output)"
      )
      if result.status != 0 { return false }
    }
    return true
  }

  private static func run(executable: String, arguments: [String]) throws -> String {
    let result = spawn(executable: executable, arguments: arguments)
    guard result.status == 0 else {
      KeepAwakeLog.error("\(executable) \(arguments) failed: \(result.status)\n\(result.output)")
      throw PowerError.pmsetReadFailed
    }
    return result.output
  }

  private static func spawn(executable: String, arguments: [String]) -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
      try process.run()
    } catch {
      return (1, error.localizedDescription)
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
  }
}
