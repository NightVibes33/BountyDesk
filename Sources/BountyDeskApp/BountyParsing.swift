import Foundation

enum AlgoraOnlyBountySource: String, Equatable {
    case algora
    case notAlgora = "not_algora"
}

struct AlgoraBountyVerification: Equatable {
    var source: AlgoraOnlyBountySource
    var verified: Bool
    var amountUsd: Int?
    var algoraBotSeen: Bool
    var claimFlowSeen: Bool
    var rewardActionSeen: Bool
    var alreadyRewarded: Bool
    var repo: String
    var issueNumber: Int
    var issueUrl: String
    var issueState: IssueState
    var openPrsMentioningIssue: Int
    var claimPrsCount: Int
    var excludedReason: String?
    var lastCheckedAt: Date
    var evidence: [String]
}


enum BountyParsing {
    private static let algoraActors: Set<String> = ["algora-pbc", "algora-pbc[bot]"]

    static func containsClaimMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("/claim")
            || normalized.contains("@algora-pbc /claim")
            || normalized.contains("bounty claim")
            || normalized.contains("🙋 bounty claim")
    }

    static func claimIssueNumbers(in text: String) -> [Int] {
        var values: [Int] = []
        let patterns = [
            #"(?:@algora-pbc\s+)?/claim\s+#(\d{1,7})"#,
            #"(?:@algora-pbc\s+)?/attempt\s+#(\d{1,7})"#
        ]
        for pattern in patterns {
            values.append(contentsOf: captureIntegers(in: text, pattern: pattern))
        }
        return orderedUnique(values)
    }

    static func classifyAlgoraOnly(
        issue: GitHubIssueResponse,
        comments: [GitHubComment],
        repo: String,
        claimEvidenceText: String = "",
        officialEventEvidence: [String] = [],
        openPrsMentioningIssue: Int = 0,
        claimPrsCount: Int = 0,
        lastCheckedAt: Date = Date()
    ) -> AlgoraBountyVerification {
        let algoraComments = comments.filter { algoraActors.contains($0.user.login.lowercased()) }
        let issueState: IssueState = issue.state.lowercased() == "closed" ? .closed : .open

        guard algoraComments.isEmpty == false || officialEventEvidence.isEmpty == false else {
            return AlgoraBountyVerification(
                source: .notAlgora,
                verified: false,
                amountUsd: nil,
                algoraBotSeen: false,
                claimFlowSeen: false,
                rewardActionSeen: false,
                alreadyRewarded: false,
                repo: repo,
                issueNumber: issue.number,
                issueUrl: issue.htmlUrl,
                issueState: issueState,
                openPrsMentioningIssue: openPrsMentioningIssue,
                claimPrsCount: claimPrsCount,
                excludedReason: "No Algora bot comment or official Algora event found",
                lastCheckedAt: lastCheckedAt,
                evidence: []
            )
        }

        let algoraText = (algoraComments.map(\.body) + officialEventEvidence).joined(separator: "\n")
        let flowText = [algoraText, claimEvidenceText].joined(separator: "\n")
        let amount = algoraBountyAmount(in: algoraText)
        let claimFlowSeen = algoraClaimFlowSeen(in: flowText)
        let rewardActionSeen = algoraRewardActionSeen(in: flowText)
        let alreadyRewarded = algoraAlreadyRewarded(in: algoraText)
        let evidence = algoraComments.map { $0.body.trimmedSummary(limit: 700) } + officialEventEvidence

        guard amount != nil, claimFlowSeen else {
            return AlgoraBountyVerification(
                source: .notAlgora,
                verified: false,
                amountUsd: nil,
                algoraBotSeen: true,
                claimFlowSeen: claimFlowSeen,
                rewardActionSeen: rewardActionSeen,
                alreadyRewarded: false,
                repo: repo,
                issueNumber: issue.number,
                issueUrl: issue.htmlUrl,
                issueState: issueState,
                openPrsMentioningIssue: openPrsMentioningIssue,
                claimPrsCount: claimPrsCount,
                excludedReason: "Algora evidence found, but bounty amount or claim flow missing",
                lastCheckedAt: lastCheckedAt,
                evidence: evidence
            )
        }

        return AlgoraBountyVerification(
            source: .algora,
            verified: true,
            amountUsd: amount,
            algoraBotSeen: true,
            claimFlowSeen: true,
            rewardActionSeen: rewardActionSeen,
            alreadyRewarded: alreadyRewarded,
            repo: repo,
            issueNumber: issue.number,
            issueUrl: issue.htmlUrl,
            issueState: issueState,
            openPrsMentioningIssue: openPrsMentioningIssue,
            claimPrsCount: claimPrsCount,
            excludedReason: nil,
            lastCheckedAt: lastCheckedAt,
            evidence: evidence
        )
    }

    static func classifyAlgoraDiscoveryOnly(
        issue: GitHubIssueResponse,
        comments: [GitHubComment],
        repo: String,
        openPrsMentioningIssue: Int = 0,
        claimPrsCount: Int = 0,
        lastCheckedAt: Date = Date()
    ) -> AlgoraBountyVerification {
        let botComments = comments.filter(isAlgoraBotIssueComment)
        let issueState: IssueState = issue.state.lowercased() == "closed" ? .closed : .open

        guard botComments.isEmpty == false else {
            return AlgoraBountyVerification(
                source: .notAlgora,
                verified: false,
                amountUsd: nil,
                algoraBotSeen: false,
                claimFlowSeen: false,
                rewardActionSeen: false,
                alreadyRewarded: false,
                repo: repo,
                issueNumber: issue.number,
                issueUrl: issue.htmlUrl,
                issueState: issueState,
                openPrsMentioningIssue: openPrsMentioningIssue,
                claimPrsCount: claimPrsCount,
                excludedReason: "No algora-pbc issue comment found",
                lastCheckedAt: lastCheckedAt,
                evidence: []
            )
        }

        let algoraText = botComments.map(\.body).joined(separator: "\n")
        let amount = algoraBountyAmount(in: algoraText)
        let claimFlowSeen = algoraClaimFlowSeen(in: algoraText)
        let rewardActionSeen = algoraRewardActionSeen(in: algoraText)
        let alreadyRewarded = algoraAlreadyRewarded(in: algoraText)
        let evidence = botComments.map { $0.body.trimmedSummary(limit: 700) }

        guard amount != nil, claimFlowSeen else {
            return AlgoraBountyVerification(
                source: .notAlgora,
                verified: false,
                amountUsd: nil,
                algoraBotSeen: true,
                claimFlowSeen: claimFlowSeen,
                rewardActionSeen: rewardActionSeen,
                alreadyRewarded: false,
                repo: repo,
                issueNumber: issue.number,
                issueUrl: issue.htmlUrl,
                issueState: issueState,
                openPrsMentioningIssue: openPrsMentioningIssue,
                claimPrsCount: claimPrsCount,
                excludedReason: "Algora bot found, but bounty amount or claim flow missing",
                lastCheckedAt: lastCheckedAt,
                evidence: evidence
            )
        }

        return AlgoraBountyVerification(
            source: .algora,
            verified: true,
            amountUsd: amount,
            algoraBotSeen: true,
            claimFlowSeen: true,
            rewardActionSeen: rewardActionSeen,
            alreadyRewarded: alreadyRewarded,
            repo: repo,
            issueNumber: issue.number,
            issueUrl: issue.htmlUrl,
            issueState: issueState,
            openPrsMentioningIssue: openPrsMentioningIssue,
            claimPrsCount: claimPrsCount,
            excludedReason: nil,
            lastCheckedAt: lastCheckedAt,
            evidence: evidence
        )
    }

    static func algoraBountyAmount(in text: String) -> Int? {
        let patterns = [
            #"\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*([kKmM]?)(?:[^A-Za-z0-9]{0,16})(?:usd)?(?:[^A-Za-z0-9]{0,16})bounty\b"#,
            #"\bbounty\D{0,32}\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*([kKmM]?)"#,
            #"\balgora[^\n$]{0,120}\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*([kKmM]?)"#,
            #"\blabeled\s+(?:issue|pull request)\s+\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*([kKmM]?)\b"#
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

    static func algoraClaimFlowSeen(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("/attempt")
            || normalized.contains("/claim")
            || normalized.contains("steps to solve")
            || normalized.contains("start working")
            || normalized.contains("submit work")
    }

    static func algoraRewardActionSeen(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("reward") || normalized.contains("/claim")
    }

    static func algoraAlreadyRewarded(in text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("rewarded")
            || normalized.contains("payment_succeeded")
            || normalized.contains("winner")
            || normalized.contains("paid by algora")
    }

    private static func isAlgoraBotIssueComment(_ comment: GitHubComment) -> Bool {
        let login = comment.user.login.lowercased()
        return login == "algora-pbc[bot]" || login == "algora-pbc"
    }

    static func latestAlgoraBotComment(from comments: [GitHubComment]) -> String {
        comments
            .filter { algoraActors.contains($0.user.login.lowercased()) }
            .sorted { $0.createdAt > $1.createdAt }
            .first?.body.trimmedSummary(limit: 240) ?? ""
    }

    static func officialAlgoraEventEvidence(issueEvents: [GitHubIssueEvent], pullRequestEvents: [GitHubIssueEvent]) -> [String] {
        let issueEvidence = officialAlgoraEventEvidence(from: issueEvents, scope: "issue")
        let pullEvidence = officialAlgoraEventEvidence(from: pullRequestEvents, scope: "pull request")
        return orderedUnique(issueEvidence + pullEvidence)
    }

    private static func officialAlgoraEventEvidence(from events: [GitHubIssueEvent], scope: String) -> [String] {
        events.compactMap { event in
            guard let actor = event.actor?.login.lowercased(), algoraActors.contains(actor) else { return nil }
            guard let label = event.label?.name, isAlgoraEvidenceLabel(label) else { return nil }
            return "\(event.actor?.login ?? "algora-pbc") \(event.event) \(scope) \(label)"
        }
    }

    private static func isAlgoraEvidenceLabel(_ label: String) -> Bool {
        let normalized = label.lowercased()
        return normalized.contains("bounty")
            || normalized.contains("claim")
            || normalized.range(of: #"\$\s*[0-9]"#, options: .regularExpression) != nil
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
            #"\$\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*([kKmM]?)"#,
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
        let evidenceText = (comments + labels + [body]).joined(separator: "\n")
        let normalized = evidenceText.lowercased()
        let officialAlgoraSeen = normalized.contains("algora-pbc")
            || labels.contains { isAlgoraEvidenceLabel($0) }
        return officialAlgoraSeen
            && algoraBountyAmount(in: evidenceText) != nil
            && algoraClaimFlowSeen(in: evidenceText)
    }

    static func algoraEvidence(labels: [String], body: String, comments: [String]) -> [String] {
        guard hasAlgoraEvidence(labels: labels, body: body, comments: comments) else { return [] }
        return ["Verified Algora bounty", "Official Algora evidence found", "Algora claim flow found"]
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
            let captureIndex = match.numberOfRanges > 1 ? 1 : 0
            guard let matchRange = Range(match.range(at: captureIndex), in: text) else { return nil }
            return String(text[matchRange])
        }
    }

    private static func orderedUnique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
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
