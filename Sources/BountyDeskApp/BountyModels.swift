import Foundation

enum BountyStatus: String, CaseIterable, Codable, Identifiable {
    case watching = "Watching"
    case claimed = "Claimed"
    case submitted = "Submitted"
    case review = "In Review"
    case merged = "Merged"
    case paid = "Paid"
    case blocked = "Blocked"
    case skipped = "Skipped"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .watching: return "eye"
        case .claimed: return "flag"
        case .submitted: return "paperplane"
        case .review: return "text.badge.checkmark"
        case .merged: return "arrow.triangle.merge"
        case .paid: return "banknote"
        case .blocked: return "exclamationmark.triangle"
        case .skipped: return "minus.circle"
        }
    }
}

enum BountyPriority: String, CaseIterable, Codable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

struct Bounty: Codable, Identifiable, Equatable {
    var id: UUID
    var repoOwner: String
    var repoName: String
    var issueNumber: Int
    var title: String
    var amount: Int
    var currency: String
    var status: BountyStatus
    var priority: BountyPriority
    var labels: [String]
    var prURL: URL?
    var notes: String
    var competitionCount: Int
    var checkSummary: String
    var updatedAt: Date
    var createdAt: Date

    init(
        id: UUID = UUID(),
        repoOwner: String,
        repoName: String,
        issueNumber: Int,
        title: String,
        amount: Int,
        currency: String = "USD",
        status: BountyStatus = .watching,
        priority: BountyPriority = .medium,
        labels: [String] = [],
        prURL: URL? = nil,
        notes: String = "",
        competitionCount: Int = 0,
        checkSummary: String = "Not checked",
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.repoOwner = repoOwner
        self.repoName = repoName
        self.issueNumber = issueNumber
        self.title = title
        self.amount = amount
        self.currency = currency
        self.status = status
        self.priority = priority
        self.labels = labels
        self.prURL = prURL
        self.notes = notes
        self.competitionCount = competitionCount
        self.checkSummary = checkSummary
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    var repoSlug: String { "\(repoOwner)/\(repoName)" }
    var issueSlug: String { "\(repoSlug)#\(issueNumber)" }
    var githubIssueURL: URL { URL(string: "https://github.com/\(repoOwner)/\(repoName)/issues/\(issueNumber)")! }
    var algoraIssueURL: URL { URL(string: "https://algora.io/\(repoOwner)/\(repoName)/issues/\(issueNumber)")! }

    var payoutText: String {
        guard amount > 0 else { return "TBD" }
        return amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    var riskScore: Int {
        var score = priority.rank * 20
        score += min(competitionCount, 30)
        if status == .blocked { score += 40 }
        if status == .paid || status == .merged { score -= 30 }
        return max(0, score)
    }

    static func fromGitHubURL(_ text: String) -> Bounty? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased(),
              host == "github.com" || host == "www.github.com"
        else { return nil }

        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4,
              parts[2] == "issues" || parts[2] == "pull",
              let number = Int(parts[3])
        else { return nil }

        return Bounty(
            repoOwner: parts[0],
            repoName: parts[1],
            issueNumber: number,
            title: "New bounty candidate",
            amount: 0,
            labels: ["Algora", "GitHub"],
            notes: "Created from \(trimmed). Add payout, status, PR, and notes after triage."
        )
    }
}

extension Bounty {
    static let samples: [Bounty] = [
        Bounty(repoOwner: "tscircuit", repoName: "kicad-component-converter", issueNumber: 114, title: "Four-sided KiCad symbol conversion regressions", amount: 50, status: .submitted, priority: .high, labels: ["Algora", "Bounty", "$50"], prURL: URL(string: "https://github.com/tscircuit/kicad-component-converter/pull/220"), notes: "Mergeable clean. Vercel, test, type-check, and format-check passed. PR has bounty-claim label.", competitionCount: 22, checkSummary: "All checks passed"),
        Bounty(repoOwner: "Dokploy", repoName: "templates", issueNumber: 152, title: "Add production-ready app templates", amount: 1000, status: .review, priority: .high, labels: ["Algora", "Bounty", "$1000 pool"], prURL: URL(string: "https://github.com/Dokploy/templates/pull/883"), notes: "Main Dokploy template claim. Mergeable but review-blocked.", competitionCount: 19, checkSummary: "Preview and validation passed"),
        Bounty(repoOwner: "Dokploy", repoName: "templates", issueNumber: 152, title: "Wallabag template claim", amount: 1000, status: .review, priority: .high, labels: ["Algora", "Bounty", "$1000 pool"], prURL: URL(string: "https://github.com/Dokploy/templates/pull/900"), notes: "Same bounty pool as the main template claim. Waiting on review.", competitionCount: 19, checkSummary: "Compose and metadata checks passed"),
        Bounty(repoOwner: "amithmandassociates-oss", repoName: "hash-report-tool", issueNumber: 2, title: "Add SHA-3/Keccak reporting outputs", amount: 50, status: .submitted, priority: .medium, labels: ["Algora", "Bounty", "$50"], prURL: URL(string: "https://github.com/amithmandassociates-oss/hash-report-tool/pull/28"), notes: "No checks configured. Broad output support and system-console digest logging added.", competitionCount: 18, checkSummary: "No CI configured"),
        Bounty(repoOwner: "getdozer", repoName: "dozer", issueNumber: 1659, title: "Support IN clause in streaming SQL", amount: 600, status: .submitted, priority: .medium, labels: ["Algora", "Bounty", "$600"], prURL: URL(string: "https://github.com/getdozer/dozer/pull/2495"), notes: "PR has bounty-claim label. No check runs reported by GitHub.", competitionCount: 6, checkSummary: "No checks reported"),
        Bounty(repoOwner: "Feel-ix-343", repoName: "markdown-oxide", issueNumber: 269, title: "Markdown Oxide bounty claim", amount: 5, status: .watching, priority: .low, labels: ["Algora", "Bounty", "$5"], prURL: URL(string: "https://github.com/Feel-ix-343/markdown-oxide/pull/456"), notes: "Low payout and unclear payment signal. Keep only as a watch item.", competitionCount: 15, checkSummary: "No checks reported")
    ]
}
