import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

enum Logger {
    static func log(_ message: String, level: LogLevel = .info) {
        let line = "[\(level.rawValue)] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    static func info(_ message: String) { log(message, level: .info) }
    static func warning(_ message: String) { log(message, level: .warning) }
    static func error(_ message: String) { log(message, level: .error) }

    /// Prints a visually prominent failure banner to stderr so the user
    /// cannot miss it, even in a scrolled terminal.
    static func failure(_ message: String) {
        let isTTY = isatty(fileno(stderr)) != 0
        let red = isTTY ? "\u{001B}[1;31m" : ""
        let reset = isTTY ? "\u{001B}[0m" : ""
        let bar = String(repeating: "!", count: 60)
        let banner = """
            \(red)\(bar)
            !! FAILURE: \(message)
            \(bar)\(reset)

            """
        FileHandle.standardError.write(Data(banner.utf8))
    }
}
