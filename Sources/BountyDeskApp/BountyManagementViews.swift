import SwiftUI

struct ManagementStageBoard: View {
    let bounties: [Bounty]
    @Binding var selectedStage: BountyManagementStage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Stage board", systemImage: "rectangle.3.group")
                    .font(.headline.weight(.semibold))
                Spacer()
                if selectedStage != nil {
                    Button("Clear") {
                        withAnimation(reduceMotion ? nil : .snappy) {
                            selectedStage = nil
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(BountyManagementStage.allCases) { stage in
                        let stageBounties = bounties.filter { $0.managementStage == stage }
                        StageBoardCard(
                            stage: stage,
                            count: stageBounties.count,
                            value: stageValue(stageBounties),
                            dueCount: stageBounties.filter(\.isFollowUpDue).count,
                            workPRCount: stageBounties.reduce(0) { $0 + $1.competitionCount },
                            isSelected: selectedStage == stage
                        ) {
                            withAnimation(reduceMotion ? nil : .snappy) {
                                selectedStage = selectedStage == stage ? nil : stage
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .bountyContentCard(cornerRadius: 8)
    }

    private func stageValue(_ values: [Bounty]) -> String {
        values.reduce(0) { $0 + $1.amount }.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}

private struct StageBoardCard: View {
    let stage: BountyManagementStage
    let count: Int
    let value: String
    let dueCount: Int
    let workPRCount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Image(systemName: stage.systemImage)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(stage.tint)
                        .frame(width: 30, height: 30)
                        .background(stage.tint.opacity(0.14), in: Circle())
                    Spacer()
                    Text("\(count)")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .contentTransition(.numericText())
                }
                Text(stage.rawValue)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { signalChips }
                    VStack(alignment: .leading, spacing: 5) { signalChips }
                }
                .frame(height: 42, alignment: .topLeading)
            }
            .padding(12)
            .frame(width: 166, height: 166, alignment: .topLeading)
            .background(stage.tint.opacity(isSelected ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? stage.tint.opacity(0.65) : Color.secondary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.rawValue), \(count) bounties, \(value)")
    }

    @ViewBuilder
    private var signalChips: some View {
        if dueCount > 0 {
            StatusChip(text: "\(dueCount) due", systemImage: "calendar.badge.exclamationmark", tint: .red)
        }
        if workPRCount > 0 {
            StatusChip(text: workPullRequestText(workPRCount), systemImage: "person.3", tint: .orange)
        }
    }
}

struct BountyDetailHero: View {
    let bounty: Bounty
    let competitorCount: Int
    let openChecklistCount: Int
    let completedChecklistCount: Int

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) {
                heroText
                Spacer(minLength: 12)
                BountySignalDial(bounty: bounty, competitorCount: competitorCount)
            }
            VStack(alignment: .leading, spacing: 18) {
                heroText
                BountySignalDial(bounty: bounty, competitorCount: competitorCount)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }

    private var heroText: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bounty.payoutText)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 8)
                if bounty.isPinned {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Pinned")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(bounty.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(bounty.issueSlug)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) { statusBadges }
                VStack(alignment: .leading, spacing: 6) { statusBadges }
            }
            Text(bounty.nextAction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { detailMetrics }
                VStack(alignment: .leading, spacing: 8) { detailMetrics }
            }
        }
    }

    @ViewBuilder
    private var detailMetrics: some View {
        DetailSignalPill(title: "Tasks", value: "\(openChecklistCount) open", systemImage: "checklist", tint: openChecklistCount > 0 ? .orange : .green)
        DetailSignalPill(title: "Done", value: "\(completedChecklistCount)", systemImage: "checkmark.circle", tint: .green)
        DetailSignalPill(title: "Work PRs", value: "\(competitorCount)", systemImage: "person.3", tint: competitorCount > 0 ? .orange : .secondary)
    }

    @ViewBuilder
    private var statusBadges: some View {
        StageChip(stage: bounty.managementStage)
        PriorityChip(priority: bounty.userPriority)
        StatusChip(text: bounty.workflowStatus.rawValue, systemImage: bounty.workflowStatus.systemImage, tint: bounty.workflowStatus.tint)
        StatusChip(text: bounty.competitionLevel.label, systemImage: "person.3", tint: bounty.competitionLevel.tint)
        StatusChip(text: bounty.recommendation.label, systemImage: bounty.recommendation.systemImage, tint: bounty.recommendation.tint)
        RiskChip(level: bounty.riskLevel)
        if bounty.isFollowUpDue {
            StatusChip(text: "Due", systemImage: "calendar.badge.exclamationmark", tint: .red)
        }
    }
}

private struct BountySignalDial: View {
    let bounty: Bounty
    let competitorCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: CGFloat {
        CGFloat(min(max(bounty.payoutChance, 0), 100)) / 100
    }

    private var trigger: Date {
        bounty.lastRefreshedAt ?? bounty.updatedAt
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.16), lineWidth: 14)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(bounty.riskLevel.tint.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(bounty.riskLevel.tint.opacity(0.12))
                .frame(width: 78, height: 78)
            VStack(spacing: 4) {
                Image(systemName: bounty.workflowStatus.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(bounty.workflowStatus.tint)
                    .symbolEffect(.bounce, value: bounty.workflowStatus.rawValue)
                Text("\(bounty.payoutChance)%")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .contentTransition(.numericText())
                if competitorCount > 0 {
                    Text("\(competitorCount) PR")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 132, height: 132)
        .phaseAnimator(reduceMotion ? [0] : [0, 1], trigger: trigger) { content, phase in
            content.scaleEffect(phase == 1 ? 1.035 : 1.0)
        } animation: { phase in
            phase == 1 ? .snappy(duration: 0.24) : .smooth(duration: 0.28)
        }
        .accessibilityLabel("Payout chance \(bounty.payoutChance) percent")
    }
}

private struct DetailSignalPill: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: 96, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
