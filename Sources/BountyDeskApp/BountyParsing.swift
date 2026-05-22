import Foundation

enum BountyParsing {
    static func containsClaimMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("/claim")
            || normalized.contains("@algora-pbc /claim")
            || normalized.contains("bounty claim")
            || normalized.contains("🙋 bounty claim")
    }

    static func linkedIssueNumbers(in text: String) -> [Int] {
        var values: [Int] = []
        let patterns = [
            #"(?:fixes|fixed|close|closes|closed|resolve|resolves|resolved|refs|references|linked to|for)\s+#(\d+)"#,
            #"(?:issues|issue)/(\d+)"#,
            #"\b#(\d{1,7})\b"#
        ]
        for pattern in patterns {
            values.append(contentsOf: captureIntegers(in: text, pattern: pattern))
        }
        return Array(Set(values)).sorted()
    }

    static func bountyAmount(in text: String) -> Int? {
        let patterns = [
            #"\$\s*([0-9]+(?:\.[0-9]+)?)\s*([kKmM]?)"#,
            #"\b([0-9][0-9,]*(?:\.[0-9]+)?)\s*(usd|dollars)\b"#,
            #"\b(?:reward|bounty|prize|pool)\D{0,20}([0-9][0-9,]*(?:\.[0-9]+)?)\s*([kKmM]?)"#
        ]
        for pattern in patterns {
            guard let match = firstMatch(in: text, pattern: pattern) else { continue }
            let number = match[1].replacingOccurrences(of: ",", with: "")
            guard let value = Double(number) else { continue }
            let suffix = match.count > 2 ? match[2].lowercased() : ""
            let multiplier: Double
            switch suffix {
            case "k": multiplier = 1_000
            case "m": multiplier = 1_000_000
            default: multiplier = 1
            }
            return Int((value * multiplier).rounded())
        }
        return nil
    }

    static func claimStatus(in text: String) -> ClaimStatus? {
        let normalized = text.lowercased()
        if normalized.contains("payment_succeeded") || normalized.contains("payment succeeded") || normalized.contains("paid out") || normalized.contains("total paid") {
            return .paymentSucceeded
        }
        if normalized.contains("payment_processing") || normalized.contains("payment processing") || normalized.contains("processing payment") {
            return .paymentProcessing
        }
        if normalized.contains("status approved") || normalized.contains("claim approved") || normalized.contains("claim accepted") || normalized.contains("accepted") {
            return .accepted
        }
        if normalized.contains("status pending") || normalized.contains("claim pending") || normalized.contains("pending") {
            return .pending
        }
        if normalized.contains("claim rejected") || normalized.contains("rejected") || normalized.contains("not eligible") {
            return .rejected
        }
        return nil
    }

    static func paymentStatus(in text: String) -> ClaimStatus? {
        let normalized = text.lowercased()
        if normalized.contains("payment_succeeded") || normalized.contains("payment succeeded") || normalized.contains("total paid") {
            return .paymentSucceeded
        }
        if normalized.contains("payment_processing") || normalized.contains("payment processing") {
            return .paymentProcessing
        }
        return nil
    }

    static func hasAlgoraEvidence(labels: [String], body: String, comments: [String]) -> Bool {
        let labelHit = labels.contains { label in
            let normalized = label.lowercased()
            return normalized.contains("algora") || normalized.contains("bounty") || normalized.contains("💎") || normalized.contains("🙋")
        }
        let haystack = ([body] + comments).joined(separator: "\n").lowercased()
        return labelHit
            || haystack.contains("algora")
            || haystack.contains("/bounty")
            || haystack.contains("/claim")
            || haystack.contains("total prize pool")
            || haystack.contains("total paid")
            || haystack.contains("payment_processing")
            || haystack.contains("payment_succeeded")
    }

    static func algoraEvidence(labels: [String], body: String, comments: [String]) -> [String] {
        var evidence: [String] = []
        for label in labels where label.lowercased().contains("algora") || label.lowercased().contains("bounty") || label.contains("💎") || label.contains("🙋") {
            evidence.append("Label: \(label)")
        }
        let texts = [body] + comments
        if texts.contains(where: { $0.lowercased().contains("/bounty") }) { evidence.append("/bounty command found") }
        if texts.contains(where: { $0.lowercased().contains("/claim") }) { evidence.append("/claim marker found") }
        if texts.contains(where: { $0.lowercased().contains("total prize pool") }) { evidence.append("Total prize pool signal found") }
        if texts.contains(where: { $0.lowercased().contains("total paid") }) { evidence.append("Total paid signal found") }
        if texts.contains(where: { $0.lowercased().contains("payment_processing") }) { evidence.append("payment_processing signal found") }
        if texts.contains(where: { $0.lowercased().contains("payment_succeeded") }) { evidence.append("payment_succeeded signal found") }
        if texts.contains(where: { $0.lowercased().contains("algora") }) { evidence.append("Algora reference found") }
        return Array(NSOrderedSet(array: evidence)) as? [String] ?? evidence
    }

    static func rewardLinks(in text: String) -> [String] {
        let pattern = #"https?://[^\s)\]]+"#
        return captureStrings(in: text, pattern: pattern)
            .filter { url in
                let normalized = url.lowercased()
                return normalized.contains("algora") || normalized.contains("reward") || normalized.contains("claim") || normalized.contains("bounty")
            }
    }

    static func requiresVideo(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("demo video")
            || normalized.contains("video proof")
            || normalized.contains("record a demo")
            || normalized.contains("loom")
            || (normalized.contains("video") && normalized.contains("required"))
    }

    static func hasDemoProof(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("youtube.com")
            || normalized.contains("youtu.be")
            || normalized.contains("loom.com")
            || normalized.contains("asciinema.org")
            || normalized.contains(".mp4")
            || normalized.contains("demo:")
            || normalized.contains("demo video")
    }

    static func hasClearVerification(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("test")
            || normalized.contains("verified")
            || normalized.contains("verification")
            || normalized.contains("steps to test")
            || normalized.contains("how to test")
            || normalized.contains("screenshot")
    }

    static func hasTests(in text: String, filesChanged: [String] = []) -> Bool {
        let normalized = text.lowercased()
        if normalized.contains("npm test") || normalized.contains("pytest") || normalized.contains("swift test") || normalized.contains("xcodebuild test") || normalized.contains("cargo test") || normalized.contains("go test") {
            return true
        }
        return filesChanged.contains { file in
            let lower = file.lowercased()
            return lower.contains("test") || lower.contains("spec") || lower.hasSuffix("_test.go") || lower.hasSuffix("tests.swift")
        }
    }

    static func assignmentRequired(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("assignment required")
            || normalized.contains("assigned only")
            || normalized.contains("must be assigned")
            || normalized.contains("ask to be assigned")
    }

    static func maintainerAssignmentRequired(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("maintainer assignment")
            || normalized.contains("maintainer must assign")
            || normalized.contains("assigned by a maintainer")
    }

    static func priorRejectedSignal(in text: String, username: String) -> Bool {
        let normalized = text.lowercased()
        let login = username.lowercased()
        return normalized.contains(login)
            && (normalized.contains("rejected") || normalized.contains("blocked") || normalized.contains("not eligible") || normalized.contains("closed as not planned"))
    }

    static func latestComment(from comments: [GitHubComment]) -> String {
        comments.sorted { $0.createdAt > $1.createdAt }.first?.body.trimmedSummary(limit: 240) ?? ""
    }

    static func latestMaintainerComment(from comments: [GitHubComment], excluding login: String) -> String {
        comments
            .filter { comment in
                comment.user.login.caseInsensitiveCompare(login) != .orderedSame
                    && comment.user.type.lowercased() != "bot"
            }
            .sorted { $0.createdAt > $1.createdAt }
            .first?.body.trimmedSummary(limit: 240) ?? ""
    }

    static func latestBotComment(from comments: [GitHubComment]) -> String {
        comments
            .filter { comment in comment.user.type.lowercased() == "bot" || comment.user.login.lowercased().contains("algora") }
            .sorted { $0.createdAt > $1.createdAt }
            .first?.body.trimmedSummary(limit: 240) ?? ""
    }

    static func testCommands(in text: String) -> [String] {
        let candidates = ["npm test", "pnpm test", "yarn test", "swift test", "xcodebuild test", "pytest", "cargo test", "go test", "bundle exec"]
        let normalized = text.lowercased()
        return candidates.filter { normalized.contains($0) }
    }

    static func captureIntegers(in text: String, pattern: String) -> [Int] {
        captureStrings(in: text, pattern: pattern).compactMap(Int.init)
    }

    static func captureStrings(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1, let matchRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
}

extension String {
    func trimmedSummary(limit: Int) -> String {
        let squashed = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard squashed.count > limit else { return squashed }
        let index = squashed.index(squashed.startIndex, offsetBy: limit)
        return String(squashed[..<index]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
