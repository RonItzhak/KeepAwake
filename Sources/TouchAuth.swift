import AppKit
import LocalAuthentication

/// Prompts with the system Touch ID sheet (`LocalAuthentication`).
///
/// The old AppleScript “administrator privileges” dialog cannot show Touch ID.
/// Privilege to run `pmset` comes from the installed sudoers rule; this only
/// proves the person at the Mac is the owner.
///
/// A successful Touch ID is reused for `LATouchIDAuthenticationMaximumAllowableReuseDuration`
/// (5 minutes). That is Apple’s ceiling for `touchIDAuthenticationAllowableReuseDuration`;
/// a longer window would be an app-only timestamp, not system credential reuse.
enum TouchAuth {
  /// Failure from `LAContext` that is not a user cancel.
  enum AuthError: LocalizedError {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .unavailable(let detail), .failed(let detail):
        return detail
      }
    }
  }

  private static let lastSuccessKey = "KeepAwake.lastTouchAuthSuccess"
  private static let reuseDuration = LATouchIDAuthenticationMaximumAllowableReuseDuration

  /// Shows Touch ID (Apple Watch counts) unless a success is still within the reuse window.
  /// Must run on the main actor so the system sheet can appear above a menu-bar app.
  @MainActor
  static func confirm(reason: String) async throws {
    if hasCachedSuccess {
      KeepAwakeLog.info("LA skipped; Touch ID still cached")
      return
    }

    let context = LAContext()
    context.localizedCancelTitle = "Cancel"
    context.localizedFallbackTitle = ""
    context.touchIDAuthenticationAllowableReuseDuration = reuseDuration

    var diagnose: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &diagnose)
    else {
      let detail = diagnose?.localizedDescription ?? "Touch ID is not available."
      KeepAwakeLog.error("LA canEvaluatePolicy failed: \(detail)")
      throw AuthError.unavailable(detail)
    }

    KeepAwakeLog.info("LA biometryType=\(context.biometryType.rawValue); prompting Touch ID")

    let previousPolicy = NSApp.activationPolicy()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    defer { NSApp.setActivationPolicy(previousPolicy) }

    do {
      try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
      rememberSuccess()
      KeepAwakeLog.info("LA Touch ID succeeded; cached for \(Int(reuseDuration))s")
    } catch let error as LAError {
      KeepAwakeLog.error("LA error \(error.code.rawValue): \(error.localizedDescription)")
      switch error.code {
      case .userCancel, .appCancel, .systemCancel:
        throw PowerManager.PowerError.userCanceled
      default:
        throw AuthError.failed(error.localizedDescription)
      }
    }
  }

  private static var hasCachedSuccess: Bool {
    let last = UserDefaults.standard.object(forKey: lastSuccessKey) as? Date
    guard let last else { return false }
    return Date().timeIntervalSince(last) < reuseDuration
  }

  private static func rememberSuccess() {
    UserDefaults.standard.set(Date(), forKey: lastSuccessKey)
  }
}
