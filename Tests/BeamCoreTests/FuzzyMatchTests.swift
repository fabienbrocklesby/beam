import BeamCore
import Testing

struct FuzzyMatchTests {
    func score(_ query: String, _ text: String) -> Int? {
        FuzzyMatch(query: query, in: text)?.score
    }

    func ranked(_ query: String, _ texts: [String]) -> [String] {
        FuzzyMatch.rank(texts, by: query) { $0 }.map { $0.item }
    }

    @Test func everyQueryLetterMustAppearInOrder() {
        #expect(FuzzyMatch(query: "bm", in: "beam") != nil)
        #expect(FuzzyMatch(query: "mb", in: "beam") == nil)
        #expect(FuzzyMatch(query: "beams", in: "beam") == nil)
    }

    @Test func caseIsIgnored() {
        #expect(FuzzyMatch(query: "BEAM", in: "beam") != nil)
        #expect(FuzzyMatch(query: "sv", in: "SidebarView") != nil)
    }

    @Test func matchedPositionsAreReportedForHighlighting() {
        #expect(FuzzyMatch(query: "cb", in: "Code/beam")?.positions == [0, 5])
        #expect(FuzzyMatch(query: "eam", in: "beam")?.positions == [1, 2, 3])
    }

    @Test func anEmptyQueryMatchesEverythingWithoutHighlights() {
        let match = FuzzyMatch(query: "", in: "beam")
        #expect(match?.positions == [])
        #expect(match?.score == 0)
    }

    @Test func aPrefixBeatsTheSameLettersInsideAWord() throws {
        #expect(try #require(score("be", "beam")) > #require(score("be", "website")))
    }

    @Test func wordStartsBeatScatteredLetters() throws {
        #expect(try #require(score("cv", "CellView")) > #require(score("cv", "curve")))
        #expect(try #require(score("db", "docs/build")) > #require(score("db", "dashboard")))
    }

    @Test func aRunOfLettersBeatsTheSameLettersSpreadOut() throws {
        #expect(try #require(score("term", "terminal")) > #require(score("term", "the-error-machine")))
    }

    @Test func theBestAlignmentWinsOverTheFirstOneFound() {
        // A greedy match takes the first "b" and spreads; the best match is
        // the word "beam".
        #expect(FuzzyMatch(query: "beam", in: "big-beam")?.positions == [4, 5, 6, 7])
    }

    @Test func rankingOrdersByScoreThenKeepsTheGivenOrder() {
        #expect(ranked("be", ["website", "beam", "bed"]) == ["beam", "bed", "website"])
        #expect(ranked("", ["two", "one"]) == ["two", "one"])
        #expect(ranked("zz", ["two", "one"]).isEmpty)
    }
}
