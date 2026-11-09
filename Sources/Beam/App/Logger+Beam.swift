import os

extension Logger {
    private nonisolated static let subsystem = "dev.beam.terminal"

    nonisolated static let app = Logger(subsystem: subsystem, category: "app")
    nonisolated static let ghostty = Logger(subsystem: subsystem, category: "ghostty")
}
