import SwiftData
import SwiftUI

func workPullRequestText(_ count: Int) -> String {
    count == 1 ? "1 work PR" : "\(count) work PRs"
}

struct BountyRow: View {
    let bounty: Bounty

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(bounty.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(bounty.issueSlug)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    if bounty.isPinned {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Pinned")
                    }
                    Text(bounty.payoutText)
                        .font(.headline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { managementChips }
                VStack(alignment: .leading, spacing: 6) { managementChips }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { statusChips }
                VStack(alignment: .leading, spacing: 6) { statusChips }
            }
            BountyProgressRail(level: bounty.riskLevel, chance: bounty.payoutChance)
            Text(bounty.nextAction)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if bounty.userTags.isEmpty == false || bounty.userNotes.isEmpty == false || bounty.followUpAt != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if bounty.userTags.isEmpty == false {
                        TagCloud(tags: Array(bounty.userTags.prefix(4)))
                    }
                    Text(bounty.managementSummary)
                        .font(.caption)
                        .foregroundStyle(bounty.isFollowUpDue ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var managementChips: some View {
        StageChip(stage: bounty.managementStage)
        PriorityChip(priority: bounty.userPriority)
        if let followUpAt = bounty.followUpAt {
            StatusChip(
                text: bounty.isFollowUpDue ? "Follow-up due" : followUpAt.formatted(date: .abbreviated, time: .omitted),
                systemImage: bounty.isFollowUpDue ? "calendar.badge.exclamationmark" : "calendar",
                tint: bounty.isFollowUpDue ? .red : .secondary
            )
        }
    }

    @ViewBuilder
    private var statusChips: some View {
        StatusChip(text: bounty.workflowStatus.rawValue, systemImage: bounty.workflowStatus.systemImage, tint: bounty.workflowStatus.tint)
        StatusChip(text: bounty.checkState.rawValue, systemImage: bounty.checkState.systemImage, tint: bounty.checkState.tint)
        RiskChip(level: bounty.riskLevel)
        if bounty.competitionCount > 0 {
            StatusChip(text: workPullRequestText(bounty.competitionCount), systemImage: "person.3", tint: bounty.competitionLevel.tint)
        }
        if bounty.rewardedClaims > 0 {
            StatusChip(text: "Reward Links Seen: \(bounty.rewardedClaims)", systemImage: "banknote", tint: .purple)
        }
        if bounty.recommendation == .notWorthIt || bounty.recommendation == .alreadyRewardedOrSaturated {
            StatusChip(text: "Do Not Pursue", systemImage: "hand.raised", tint: .red)
        }
    }
}

struct BountyCompactRow: View {
    let bounty: Bounty

    var body: some View {
        NavigationLink {
            BountyDetailView(bounty: bounty)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                    Text(bounty.title).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 6) {
                        StageChip(stage: bounty.managementStage)
                        PriorityChip(priority: bounty.userPriority)
                        if bounty.competitionCount > 0 {
                            StatusChip(text: workPullRequestText(bounty.competitionCount), systemImage: "person.3", tint: bounty.competitionLevel.tint)
                        }
                        if bounty.recommendation == .notWorthIt || bounty.recommendation == .alreadyRewardedOrSaturated {
                            StatusChip(text: "Do Not Pursue", systemImage: "hand.raised", tint: .red)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    Text(bounty.payoutText)
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(.green)
                        .contentTransition(.numericText())
                    RiskChip(level: bounty.riskLevel)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bountyGlassCard(cornerRadius: 8, interactive: true)
        }
        .buttonStyle(.plain)
    }
}

struct BountySnapshotRow: View {
    let snapshot: TrackedBountySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(snapshot.title).font(.headline.weight(.semibold)).lineLimit(2)
                    Text("\(snapshot.repoOwner)/\(snapshot.repoName)#\(snapshot.issueNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(snapshot.amount > 0 ? snapshot.amount.formatted(.currency(code: snapshot.currency).precision(.fractionLength(0))) : "TBD")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
            }
            HStack {
                StatusChip(text: "Verified Algora", systemImage: "checkmark.seal", tint: .green)
                RiskChip(level: snapshot.riskLevel)
                StatusChip(text: workPullRequestText(snapshot.competitionCount), systemImage: "person.3", tint: snapshot.competitionCount > 0 ? snapshot.competitionLevel.tint : .secondary)
                StatusChip(text: snapshot.recommendation.label, systemImage: snapshot.recommendation.systemImage, tint: snapshot.recommendation.tint)
            }
            Text(snapshot.nextAction).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .bountyGlassCard(cornerRadius: 8)
    }
}

struct ActionRow: View {
    let bounty: Bounty

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: bounty.riskLevel == .high ? "exclamationmark.triangle.fill" : bounty.workflowStatus.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(bounty.riskLevel.tint)
                .frame(width: 32, height: 32)
                .background(bounty.riskLevel.tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(bounty.issueSlug).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(bounty.payoutText)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.green)
                }
                Text(bounty.nextAction).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    StageChip(stage: bounty.managementStage)
                    PriorityChip(priority: bounty.userPriority)
                    if bounty.isPinned { StatusChip(text: "Pinned", systemImage: "star.fill", tint: .yellow) }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: Circle())
                Spacer()
            }
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: value)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
        .accessibilityElement(children: .combine)
    }
}

struct SyncBanner: View {
    let message: String
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: warnings.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(warnings.isEmpty ? .green : .orange)
                .symbolEffect(.bounce, value: warnings.count)
            ForEach(warnings.prefix(3), id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

struct BountyProgressRail: View {
    let level: RiskLevel
    let chance: Int

    private var normalizedChance: CGFloat {
        CGFloat(min(max(chance, 0), 100)) / 100
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.16))
                Capsule()
                    .fill(level.tint.gradient)
                    .frame(width: max(8, proxy.size.width * normalizedChance))
            }
        }
        .frame(height: 5)
        .accessibilityLabel("Payout chance \(chance) percent")
    }
}

struct StatusChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
            .accessibilityLabel(text)
    }
}

struct RiskChip: View {
    let level: RiskLevel

    var body: some View {
        StatusChip(text: "\(level.rawValue) Risk", systemImage: "gauge.with.dots.needle.67percent", tint: level.tint)
    }
}

struct StageChip: View {
    let stage: BountyManagementStage

    var body: some View {
        StatusChip(text: stage.rawValue, systemImage: stage.systemImage, tint: stage.tint)
    }
}

struct PriorityChip: View {
    let priority: BountyUserPriority

    var body: some View {
        StatusChip(text: priority.rawValue, systemImage: priority.systemImage, tint: priority.tint)
    }
}

struct TagCloud: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tagViews }
            VStack(alignment: .leading, spacing: 6) { tagViews }
        }
    }

    @ViewBuilder
    private var tagViews: some View {
        ForEach(tags, id: \.self) { tag in
            Text(tag)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .foregroundStyle(.secondary)
                .background(.secondary.opacity(0.12), in: Capsule())
        }
    }
}

struct EvidenceList: View {
    let values: [String]
    let empty: String

    var body: some View {
        if values.isEmpty {
            Text(empty).foregroundStyle(.secondary)
        } else {
            ForEach(values, id: \.self) { value in
                Label(value, systemImage: "checkmark.circle")
                    .font(.footnote)
            }
        }
    }
}

struct EthicalSuggestionList: View {
    let bounty: Bounty

    var body: some View {
        EvidenceList(values: suggestions, empty: "No immediate improvement suggestions detected.")
    }

    private var suggestions: [String] {
        var values: [String] = []
        if bounty.hasTests == false { values.append("Add missing tests or explain why tests do not apply.") }
        if bounty.hasClearVerification == false { values.append("Improve the PR body with clearer verification steps.") }
        if bounty.checkState == .failing { values.append("Address failing checks before asking for review.") }
        if bounty.requiresVideo && bounty.hasDemoProof == false { values.append("Add real demo proof if the bounty requires it.") }
        if bounty.assignedOnly && bounty.userAppearsAssigned == false { values.append("Confirm assignment before expanding scope.") }
        if bounty.latestMaintainerComment.isEmpty == false { values.append("Respond to relevant maintainer feedback.") }
        if bounty.riskFactors.contains(where: { $0.lowercased().contains("contributing") }) { values.append("Mention the relevant repository rules in the PR.") }
        return values
    }
}

enum TernaryFilter: String, CaseIterable, Identifiable {
    case any = "Any"
    case yes = "Required"
    case no = "Not Required"

    var id: String { rawValue }
    var value: Bool? {
        switch self {
        case .any: return nil
        case .yes: return true
        case .no: return false
        }
    }
}

func riskRank(_ risk: RiskLevel) -> Int {
    switch risk {
    case .high: return 3
    case .medium: return 2
    case .low: return 1
    }
}

func priorityRank(_ priority: BountyUserPriority) -> Int {
    switch priority {
    case .urgent: return 4
    case .high: return 3
    case .normal: return 2
    case .low: return 1
    }
}

func stageRank(_ stage: BountyManagementStage) -> Int {
    switch stage {
    case .focus: return 6
    case .payout: return 5
    case .waiting: return 4
    case .inbox: return 3
    case .done: return 2
    case .archived: return 1
    }
}

func tags(from text: String) -> [String] {
    text.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
        .uniquedCaseInsensitive()
}

func dollars(_ amount: Int) -> String {
    amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}

extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
