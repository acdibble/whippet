enum FuzzyMatch {
    /// Scores `candidate` against `query` as an in-order subsequence, or returns nil when it does not match.
    /// Of every way the query's characters could line up with the candidate's, the best one counts: word starts and
    /// consecutive characters score higher, and longer candidates score slightly lower.
    static func score(_ query: String, in candidate: String) -> Int? {
        if query.isEmpty { return 0 }

        let queryChars = Array(query.lowercased())
        let original = Array(candidate)
        let candidateChars = Array(candidate.lowercased())
        guard original.count == candidateChars.count, queryChars.count <= candidateChars.count else {
            return greedyScore(queryChars, in: candidateChars)
        }

        // best[j] is the highest score with the current query character matched at candidate index j, or nil.
        var best = [Int?](repeating: nil, count: candidateChars.count)
        for (queryIndex, queryChar) in queryChars.enumerated() {
            var next = [Int?](repeating: nil, count: candidateChars.count)
            // The best score for the previous query character at any index up to j - 2, which leaves a gap before j.
            var bestBeforeGap: Int?
            for index in candidateChars.indices {
                if index >= 2, let earlier = best[index - 2] {
                    bestBeforeGap = max(bestBeforeGap ?? earlier, earlier)
                }
                guard candidateChars[index] == queryChar else { continue }
                let base = 1 + (isWordStart(index, in: original) ? 10 : 0)
                if queryIndex == 0 {
                    next[index] = base
                    continue
                }
                let consecutive = index >= 1 ? best[index - 1].map { $0 + 5 } : nil
                guard let previous = [consecutive, bestBeforeGap].compactMap({ $0 }).max() else { continue }
                next[index] = previous + base
            }
            best = next
        }

        guard let score = best.compactMap({ $0 }).max() else { return nil }
        return score - candidateChars.count / 10
    }

    /// The start of a word: the first character, one after a space or punctuation, or a capital after a lowercase letter.
    private static func isWordStart(_ index: Int, in characters: [Character]) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        if previous.isWhitespace || previous.isPunctuation || previous.isSymbol { return true }
        return characters[index].isUppercase && previous.isLowercase
    }

    /// For the rare text whose lowercased form changes length, such as "ß", a simple first-match scan.
    private static func greedyScore(_ queryChars: [Character], in candidateChars: [Character]) -> Int? {
        var queryIndex = 0
        for char in candidateChars where queryIndex < queryChars.count && char == queryChars[queryIndex] {
            queryIndex += 1
        }
        return queryIndex == queryChars.count ? queryIndex - candidateChars.count / 10 : nil
    }
}
