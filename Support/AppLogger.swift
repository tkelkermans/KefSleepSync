import OSLog

enum AppLogger {
    static let subsystem = "com.tristan.kef.KefSleepSync"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let api = Logger(subsystem: subsystem, category: "api")
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    static let login = Logger(subsystem: subsystem, category: "login")
    static let power = Logger(subsystem: subsystem, category: "power")
}
