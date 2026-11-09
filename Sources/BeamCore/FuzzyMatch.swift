/// How well a typed query matches a piece of text, for the switcher. Every
/// query character must appear in the text in order, ignoring case. Of the
/// ways to place them, the best scoring one counts: matches score more at
/// the start of a word and in unbroken runs, and less across gaps.
public struct FuzzyMatch: Equatable, Sendable {
    public let score: Int
    /// Where the query's characters landed, as offsets into the text's
    /// characters, for highlighting.
    public let positions: [Int]

    private static let matchScore = 16
    private static let wordStartBonus = 12
    private static let humpBonus = 10
    private static let runBonus = 12
    private static let separators: Set<Character> = [" ", "/", "-", "_", ".", ":"]

    /// Nil when `text` does not contain `query`'s characters in order. An
    /// empty query matches anything, with no score and nothing highlighted.
    public init?(query: String, in text: String) {
        let query = query.map { $0.lowercased() }
        let characters = Array(text)
        let lowered = characters.map { $0.lowercased() }
        let (m, n) = (query.count, characters.count)
        guard m > 0 else {
            score = 0
            positions = []
            return
        }
        guard m <= n else { return nil }
        let bonus = characters.indices.map { Self.bonus(at: $0, in: characters) }

        // best[i][j] is the best score with query[i] placed on text[j], and
        // from[i][j] where query[i - 1] went on that placement. A gap of g
        // characters costs g + 1, so for each row the best earlier placement
        // to jump from is tracked as score + index, and the cost of the jump
        // to j comes out as that minus j.
        var best = [[Int?]](repeating: [Int?](repeating: nil, count: n), count: m)
        var from = [[Int]](repeating: [Int](repeating: 0, count: n), count: m)
        for i in 0..<m {
            var jump: (value: Int, index: Int)?
            for j in i..<n {
                if i > 0, j >= 2, let previous = best[i - 1][j - 2], previous + j - 2 > jump?.value ?? Int.min {
                    jump = (previous + j - 2, j - 2)
                }
                guard lowered[j] == query[i] else { continue }
                guard i > 0 else {
                    best[i][j] = Self.matchScore + bonus[j]
                    continue
                }
                var placement: (score: Int, from: Int)?
                if let run = best[i - 1][j - 1] {
                    placement = (run + Self.matchScore + max(bonus[j], Self.runBonus), j - 1)
                }
                if let jump, jump.value - j + Self.matchScore + bonus[j] > placement?.score ?? Int.min {
                    placement = (jump.value - j + Self.matchScore + bonus[j], jump.index)
                }
                if let placement {
                    best[i][j] = placement.score
                    from[i][j] = placement.from
                }
            }
        }

        var end: (score: Int, index: Int)?
        for j in 0..<n {
            if let score = best[m - 1][j], score > end?.score ?? Int.min { end = (score, j) }
        }
        guard let end else { return nil }
        var positions = [end.index]
        for i in stride(from: m - 1, to: 0, by: -1) {
            positions.append(from[i][positions[positions.count - 1]])
        }
        score = end.score
        self.positions = positions.reversed()
    }

    /// The items whose text matches `query`, best first. Equal scores keep
    /// the order the items came in.
    public static func rank<Item>(
        _ items: [Item], by query: String, text: (Item) -> String
    ) -> [(item: Item, match: FuzzyMatch)] {
        items.enumerated()
            .compactMap { offset, item in
                FuzzyMatch(query: query, in: text(item)).map { (offset: offset, item: item, match: $0) }
            }
            .sorted { $0.match.score != $1.match.score ? $0.match.score > $1.match.score : $0.offset < $1.offset }
            .map { (item: $0.item, match: $0.match) }
    }

    private static func bonus(at index: Int, in characters: [Character]) -> Int {
        guard index > 0 else { return wordStartBonus }
        let previous = characters[index - 1]
        if separators.contains(previous) { return wordStartBonus }
        if previous.isLowercase && characters[index].isUppercase { return humpBonus }
        return 0
    }
}
