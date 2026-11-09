import BeamCore
import GhosttyKit

// libghostty's split and resize directions in Beam's terms.
extension SplitTree.Direction {
    init?(_ direction: ghostty_action_split_direction_e) {
        switch direction {
        case GHOSTTY_SPLIT_DIRECTION_RIGHT: self = .right
        case GHOSTTY_SPLIT_DIRECTION_DOWN: self = .down
        case GHOSTTY_SPLIT_DIRECTION_LEFT: self = .left
        case GHOSTTY_SPLIT_DIRECTION_UP: self = .up
        default: return nil
        }
    }

    init?(_ direction: ghostty_action_resize_split_direction_e) {
        switch direction {
        case GHOSTTY_RESIZE_SPLIT_RIGHT: self = .right
        case GHOSTTY_RESIZE_SPLIT_DOWN: self = .down
        case GHOSTTY_RESIZE_SPLIT_LEFT: self = .left
        case GHOSTTY_RESIZE_SPLIT_UP: self = .up
        default: return nil
        }
    }
}
