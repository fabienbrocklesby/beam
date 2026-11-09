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
