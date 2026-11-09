/// Shell quoting for text Beam types into a terminal on the user's behalf.
public enum Shell {
    private static let metacharacters = Set(#"\ ()[]{}<>"'`!#$&;|*?"# + "\t")

    /// Quotes `path` so a dropped or pasted file path reaches the program as
    /// one argument. Backslash escapes, as Terminal does, unless the path holds
    /// a line break: a backslash before one is a line continuation, so those
    /// paths are single-quoted instead.
    public static func escape(_ path: String) -> String {
        if path.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            return "'" + path.replacing("'", with: #"'\''"#) + "'"
        }
        var escaped = ""
        escaped.reserveCapacity(path.utf8.count)
        for character in path {
            if metacharacters.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }
}
