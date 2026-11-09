import AppKit

/// The switcher's window: borderless, floating over the main window, able to
/// take the keyboard, and gone once it loses it.
final class SwitcherPanel: NSPanel {
    /// Called when another window takes the keyboard, such as a click
    /// outside the switcher.
    var onResignKey: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
        self.contentViewController = contentViewController
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
