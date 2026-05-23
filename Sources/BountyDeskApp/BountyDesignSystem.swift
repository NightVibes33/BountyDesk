import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BountyBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    SIMD2<Float>(0.00, 0.00), SIMD2<Float>(0.52, 0.02), SIMD2<Float>(1.00, 0.00),
                    SIMD2<Float>(0.02, 0.48), SIMD2<Float>(0.56, 0.50), SIMD2<Float>(0.98, 0.45),
                    SIMD2<Float>(0.00, 1.00), SIMD2<Float>(0.48, 0.96), SIMD2<Float>(1.00, 1.00)
                ],
                colors: [
                    Color(red: 0.05, green: 0.20, blue: 0.18),
                    Color(red: 0.12, green: 0.45, blue: 0.36),
                    Color(red: 0.52, green: 0.68, blue: 0.42),
                    Color(red: 0.08, green: 0.24, blue: 0.34),
                    Color(red: 0.18, green: 0.62, blue: 0.48),
                    Color(red: 0.36, green: 0.38, blue: 0.72),
                    Color(red: 0.04, green: 0.08, blue: 0.12),
                    Color(red: 0.12, green: 0.34, blue: 0.42),
                    Color(red: 0.62, green: 0.78, blue: 0.52)
                ]
            )
            .opacity(colorScheme == .dark ? 0.42 : 0.28)
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground).opacity(colorScheme == .dark ? 0.42 : 0.18),
                    Color(uiColor: .systemGroupedBackground).opacity(colorScheme == .dark ? 0.88 : 0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct BountySectionHeader: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.top, 4)
    }
}

extension View {
    @ViewBuilder
    func bountyGlassCard(cornerRadius: CGFloat = 8, interactive: Bool = false) -> some View {
        self.glassEffect(.regular.tint(.white.opacity(0.08)).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
    }

    func bountyContentCard(cornerRadius: CGFloat = 8) -> some View {
        self
            .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.86), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.secondary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 10, y: 4)
    }
}


extension BountyManagementStage {
    var tint: Color {
        switch self {
        case .inbox: return .secondary
        case .focus: return .orange
        case .waiting: return .blue
        case .payout: return .purple
        case .done: return .green
        case .archived: return .secondary
        }
    }
}

extension BountyUserPriority {
    var tint: Color {
        switch self {
        case .low: return .secondary
        case .normal: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

extension BountyWorkflowStatus {
    var tint: Color {
        switch self {
        case .watching: return .teal
        case .claimed: return .blue
        case .submitted: return .indigo
        case .pendingReview: return .orange
        case .mergedUnpaid: return .purple
        case .paid: return .green
        case .lost: return .secondary
        case .blocked: return .red
        }
    }
}

extension CheckState {
    var tint: Color {
        switch self {
        case .passing: return .green
        case .failing: return .red
        case .pending: return .orange
        case .noneConfigured: return .secondary
        case .unknown: return .secondary
        }
    }
}

extension RiskLevel {
    var tint: Color {
        switch self {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}


extension CompetitionLevel {
    var tint: Color {
        switch self {
        case .none: return .green
        case .low: return .teal
        case .medium: return .orange
        case .high: return .red
        case .extreme: return .purple
        }
    }
}

extension BountyRecommendation {
    var tint: Color {
        switch self {
        case .goodTarget: return .green
        case .possibleButContested: return .orange
        case .lowPriority: return .secondary
        case .notWorthIt: return .red
        case .alreadyRewardedOrSaturated: return .purple
        case .notAlgora: return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .goodTarget: return "target"
        case .possibleButContested: return "person.3"
        case .lowPriority: return "arrow.down.circle"
        case .notWorthIt: return "hand.raised"
        case .alreadyRewardedOrSaturated: return "exclamationmark.octagon"
        case .notAlgora: return "xmark.seal"
        }
    }
}
