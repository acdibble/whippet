enum FuzzyMatch {
    /// Scores `candidate` against `query` as an in-order subsequence, or returns nil when it does not match.
    /// Consecutive characters and word starts score higher; longer candidates score slightly lower.
    static func score(_ query: String, in candidate: String) -> Int? {
        if query.isEmpty { return 0 }

        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate.lowercased())
        var score = 0
        var queryIndex = 0
        var lastMatch = -1

        for (index, char) in candidateChars.enumerated()
        where queryIndex < queryChars.count && char == queryChars[queryIndex] {
            score += 1
            if index == lastMatch + 1 { score += 5 }
            if index == 0 || candidateChars[index - 1] == " " { score += 10 }
            lastMatch = index
            queryIndex += 1
        }

        if queryIndex < queryChars.count { return nil }
        return score - candidateChars.count / 10
    }
}
