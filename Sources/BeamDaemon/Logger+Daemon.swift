import os

extension Logger {
    nonisolated static let daemon = Logger(subsystem: "dev.beam.terminal", category: "beamd")
}
