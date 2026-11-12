import BeamCore
import CoreGraphics
import GhosttyKit

// libghostty's goto targets in Beam's terms.
extension TerminalEvent.SplitTarget {
    init?(_ target: ghostty_action_goto_split_e) {
        switch target {
        case GHOSTTY_GOTO_SPLIT_PREVIOUS: self = .previous
        case GHOSTTY_GOTO_SPLIT_NEXT: self = .next
        case GHOSTTY_GOTO_SPLIT_LEFT: self = .neighbour(.left)
        case GHOSTTY_GOTO_SPLIT_RIGHT: self = .neighbour(.right)
        case GHOSTTY_GOTO_SPLIT_UP: self = .neighbour(.up)
        case GHOSTTY_GOTO_SPLIT_DOWN: self = .neighbour(.down)
        default: return nil
        }
    }
}

extension TerminalEvent.WorkspaceTarget {
    /// Positive values are tab numbers counted from 1.
    init(_ target: ghostty_action_goto_tab_e) {
        switch target {
        case GHOSTTY_GOTO_TAB_PREVIOUS: self = .previous
        case GHOSTTY_GOTO_TAB_NEXT: self = .next
        case GHOSTTY_GOTO_TAB_LAST: self = .last
        default: self = .position(Int(target.rawValue) - 1)
        }
    }
}

// Ghostty's keybinding actions, for a document pane, which has no surface to
// run them.
extension TerminalEvent {
    /// Nil for copy, paste, select all and find, which the Edit menu sends
    /// to the focused view itself. `size` is the pane's: `new_split:auto`
    /// splits a wide pane to the right and any other down, as Ghostty does.
    init?(_ action: BindingAction, size: CGSize) {
        switch action {
        case .newSplit(let direction): self = .newSplit(direction ?? (size.width > size.height ? .right : .down))
        case .gotoSplit(.previous): self = .focusSplit(.previous)
        case .gotoSplit(.next): self = .focusSplit(.next)
        case .gotoSplit(.neighbour(let direction)): self = .focusSplit(.neighbour(direction))
        case .toggleSplitZoom: self = .toggleSplitZoom
        case .equalizeSplits: self = .equalizeSplits
        case .resizeSplit(let direction, let points): self = .resizeSplit(direction, points: Double(points))
        case .closeSurface: self = .closeRequested(processAlive: false)
        case .newTab, .newWindow: self = .newWorkspace
        case .gotoTab(.position(let position)): self = .selectWorkspace(.position(position))
        case .gotoTab(.previous): self = .selectWorkspace(.previous)
        case .gotoTab(.next): self = .selectWorkspace(.next)
        case .gotoTab(.last): self = .selectWorkspace(.last)
        case .closeTab: self = .closeWorkspace
        case .closeWindow: self = .closeWindow
        case .copyToClipboard, .pasteFromClipboard, .selectAll, .startSearch: return nil
        }
    }
}
