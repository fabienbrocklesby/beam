// Finding the words in an agent's reply or a tool's input that may name
// files. Only strings: whether a name is a file is for `FileResolver`, which
// drops what is not, so these lean towards keeping a word.
extension FileMention {
    /// Characters that end a word. Markdown, quotes and shell syntax, so a
    /// name comes out of `![a](b.png)`, `"b.png"` and `2>b.png` alike.
    private static let separators = Set(" \t\n\r`'\"()[]{}<>,;|&=")
    /// Characters a word cannot end with, as at the end of a sentence.
    private static let trailing = Set(".,:;!?*")

    /// Path-like words in `text`, an agent's reply or a shell command, each
    /// once, in the order written: words with a slash or a file extension,
    /// and code spans with a space that look like a file name. Fenced code
    /// blocks are skipped.
    public static func names(in text: String) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        func add(_ word: Substring) {
            var word = word
            while let last = word.last, trailing.contains(last) { word = word.dropLast() }
            while word.first == "*" { word = word.dropFirst() }
            guard looksLikeFile(word), seen.insert(String(word)).inserted else { return }
            names.append(String(word))
        }
        func addWords(_ text: Substring) {
            for word in text.split(whereSeparator: separators.contains) { add(word) }
        }

        var inFence = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.drop(while: \.isWhitespace).hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            // Odd pieces are code spans. One with a space may be a name with
            // a space in it, which only a code span keeps whole.
            for (index, piece) in line.split(separator: "`", omittingEmptySubsequences: false).enumerated() {
                if !index.isMultiple(of: 2), piece.contains(" ") { add(piece) }
                addWords(piece)
            }
        }
        return names
    }

    /// The files a Codex `apply_patch` patch adds, updates or moves to.
    public static func names(inPatch patch: String) -> [String] {
        let headers = ["*** Add File: ", "*** Update File: ", "*** Move to: "]
        return patch.split(whereSeparator: \.isNewline).compactMap { line in
            headers.first(where: line.hasPrefix).map { String(line.dropFirst($0.count)) }
        }
    }

    /// Whether `word` may name a file: it has a slash or starts with `~`, or
    /// ends in an extension that starts with a letter, and it is no web
    /// address.
    private static func looksLikeFile(_ word: Substring) -> Bool {
        guard word.count <= 1024, word.contains(where: \.isLetter), !isWeb(word) else { return false }
        if word.contains("/") || word.hasPrefix("~") { return true }
        guard let dot = word.lastIndex(of: "."), dot != word.startIndex else { return false }
        let ext = word[word.index(after: dot)...].prefix { $0 != ":" }
        return (1...8).contains(ext.count) && ext.first?.isLetter == true
            && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
