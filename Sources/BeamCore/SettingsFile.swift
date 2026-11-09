import Foundation

/// Beam's own config file, in Ghostty's syntax. Beam loads it after the
/// user's Ghostty config, so a setting here changes Beam without changing
/// Ghostty.app.
public struct SettingsFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `~/.config/beam/config.ghostty`, named like Ghostty's own file.
    public static var standard: SettingsFile {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return SettingsFile(url: home.appendingPathComponent(".config/beam/config.ghostty"))
    }

    /// Writes a commented starting point unless a file is already there, so
    /// opening Settings always finds something to edit and never loses a
    /// user's file. Blocks on the disk.
    public func createIfMissing() throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try Data(Self.template.utf8).write(to: url, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            return
        }
    }

    /// Comments only, so creating the file changes nothing until the user does.
    private static let template = """
        # Beam settings, in Ghostty's config syntax: https://ghostty.org/docs/config
        # Beam reads your Ghostty config first and this file after it, so a
        # setting here applies to Beam only. Save, then reload with Cmd+Shift+,
        #
        # Beam follows macOS light and dark mode. Pick a theme for each half
        # from the names in Beam.app/Contents/Resources/ghostty/themes:
        # theme = light:Apple System Colors Light,dark:Apple System Colors
        #
        # font-family = SF Mono
        # font-size = 13

        """
}
