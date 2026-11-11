import BeamCore

/// What a terminal tells, or asks of, the window that holds it, in Beam's
/// terms rather than libghostty's.
enum TerminalEvent {
    enum SplitTarget {
        case previous, next
        case neighbour(SplitTree.Direction)
    }

    enum WorkspaceTarget {
        /// A position in the sidebar, from 0.
        case position(Int)
        case previous, next, last
    }

    case focused
    case titleChanged(String)
    case workingDirectoryChanged(String)
    /// A command run at the shell's prompt has exited. Only reported when
    /// Ghostty's shell integration marks commands, which it does by default
    /// for zsh, bash, fish and elvish.
    case commandFinished
    /// The user Cmd+clicked a link: a URL, or a path that libghostty made
    /// absolute when it found the file under the shell's directory, and left
    /// as written otherwise.
    case openLink(String)
    /// libghostty wants the pane gone: its process exited, or the user asked.
    /// `processAlive` means something is still running that closing would kill.
    case closeRequested(processAlive: Bool)

    case newSplit(SplitTree.Direction)
    case focusSplit(SplitTarget)
    case toggleSplitZoom
    case equalizeSplits
    case resizeSplit(SplitTree.Direction, points: Double)

    case newWorkspace
    case selectWorkspace(WorkspaceTarget)
    case closeWorkspace
    case closeWindow
}
