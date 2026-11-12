/// A Ghostty keybind action Beam acts on itself, parsed from the string a
/// config or a menu item names it by (`new_split:right`). A terminal runs
/// these through libghostty; a document pane has no surface to run them, so
/// Beam reads them here.
public enum BindingAction: Equatable, Sendable {
    public enum SplitTarget: Equatable, Sendable {
        case previous, next
        case neighbour(SplitTree.Direction)
    }

    public enum TabTarget: Equatable, Sendable {
        /// Counted from 0, where Ghostty's `goto_tab` counts from 1.
        case position(Int)
        case previous, next, last
    }

    /// Nil lets Beam pick the side, as Ghostty's `auto` does.
    case newSplit(SplitTree.Direction?)
    case gotoSplit(SplitTarget)
    case toggleSplitZoom
    case equalizeSplits
    /// The direction the divider moves and how far, in points.
    case resizeSplit(SplitTree.Direction, Int)
    case closeSurface

    case newTab
    case gotoTab(TabTarget)
    case closeTab
    case newWindow
    case closeWindow

    case copyToClipboard
    case pasteFromClipboard
    case selectAll
    case startSearch

    /// The actions whose keys work from a focused document, written as a
    /// config binds them, since a key is looked up by the exact action:
    /// `resize_split:up,10` and not `resize_split:up,20`. The parameters
    /// are Ghostty's macOS defaults. Copy, paste, select all and find are
    /// left out: the Edit menu sends those to the focused view itself.
    public static let documentKeys: [String] =
        ["right", "down", "left", "up", "auto"].map { "new_split:\($0)" }
        + ["previous", "next", "up", "down", "left", "right"].map { "goto_split:\($0)" }
        + ["up", "down", "left", "right"].map { "resize_split:\($0),10" }
        + ["toggle_split_zoom", "equalize_splits", "close_surface"]
        + ["new_tab", "new_window", "close_tab:this", "close_window", "previous_tab", "next_tab", "last_tab"]
        + (1...9).map { "goto_tab:\($0)" }

    /// Nil for an action Beam leaves to the terminal, or a parameter Ghostty
    /// would not take.
    public init?(_ action: String) {
        let parts = action.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let parameter = parts.count > 1 ? String(parts[1]) : nil
        switch (parts[0], parameter) {
        case ("new_split", nil), ("new_split", "auto"): self = .newSplit(nil)
        case ("new_split", let side?):
            guard let direction = SplitTree.Direction(rawValue: side) else { return nil }
            self = .newSplit(direction)
        case ("goto_split", "previous"): self = .gotoSplit(.previous)
        case ("goto_split", "next"): self = .gotoSplit(.next)
        case ("goto_split", "top"): self = .gotoSplit(.neighbour(.up))
        case ("goto_split", "bottom"): self = .gotoSplit(.neighbour(.down))
        case ("goto_split", let side?):
            guard let direction = SplitTree.Direction(rawValue: side) else { return nil }
            self = .gotoSplit(.neighbour(direction))
        case ("toggle_split_zoom", nil): self = .toggleSplitZoom
        case ("equalize_splits", nil): self = .equalizeSplits
        case ("resize_split", let move?):
            let move = move.split(separator: ",", omittingEmptySubsequences: false)
            guard move.count == 2, let direction = SplitTree.Direction(rawValue: String(move[0])),
                let points = Int(move[1]), points >= 0
            else { return nil }
            self = .resizeSplit(direction, points)
        case ("close_surface", nil): self = .closeSurface
        case ("new_tab", nil): self = .newTab
        case ("goto_tab", let number?):
            guard let number = Int(number), number >= 1 else { return nil }
            self = .gotoTab(.position(number - 1))
        case ("previous_tab", nil): self = .gotoTab(.previous)
        case ("next_tab", nil): self = .gotoTab(.next)
        case ("last_tab", nil): self = .gotoTab(.last)
        case ("close_tab", nil), ("close_tab", "this"): self = .closeTab
        case ("new_window", nil): self = .newWindow
        case ("close_window", nil): self = .closeWindow
        // The parameter picks a format, which only a terminal's text has.
        case ("copy_to_clipboard", _): self = .copyToClipboard
        case ("paste_from_clipboard", nil): self = .pasteFromClipboard
        case ("select_all", nil): self = .selectAll
        case ("start_search", nil): self = .startSearch
        default: return nil
        }
    }
}
