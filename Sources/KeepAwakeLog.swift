import Foundation
import os

/// Append-only debug log at `~/Library/Logs/KeepAwake.log`, also mirrored to Console.
enum KeepAwakeLog {
  /// File written on every launch and toggle so failures can be diagnosed without a terminal.
  static let fileURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/KeepAwake.log")

  private static let logger = Logger(subsystem: "com.ron.KeepAwake", category: "main")
  private static let stamp: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  /// Records a normal event (launch, current `pmset` output, script contents).
  static func info(_ message: String) {
    logger.info("\(message, privacy: .public)")
    append("INFO", message)
  }

  /// Records a failure (AppleScript errors, non-zero `pmset` / `sudo` exits).
  static func error(_ message: String) {
    logger.error("\(message, privacy: .public)")
    append("ERROR", message)
  }

  private static func append(_ level: String, _ message: String) {
    let line = "\(stamp.string(from: Date())) [\(level)] \(message)\n"
    let path = fileURL.path
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
      }
      let handle = try FileHandle(forWritingTo: fileURL)
      defer { try? handle.close() }
      try handle.seekToEnd()
      if let data = line.data(using: .utf8) {
        try handle.write(contentsOf: data)
      }
    } catch {
      logger.error("log write failed: \(error.localizedDescription, privacy: .public)")
    }
  }
}
