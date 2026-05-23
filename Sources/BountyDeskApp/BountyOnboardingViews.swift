import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct BountyOnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void
    @State private var selection: OnboardingPage = .verify

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        OnboardingProgressHeader(selection: selection)

                        TabView(selection: $selection) {
                            ForEach(OnboardingPage.allCases) { page in
                                OnboardingPagePanel(page: page, reduceMotion: reduceMotion)
                                    .tag(page)
                                    .padding(.horizontal, 2)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(minHeight: 540)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.36), value: selection)

                        OnboardingSetupStrip()

                        HStack(spacing: 12) {
                            Button("Skip") { finish() }
                                .buttonStyle(.bordered)
                                .controlSize(.large)
                            Spacer(minLength: 8)
                            Button {
                                advance()
                            } label: {
                                Label(selection.isFinal ? "Set Up GitHub" : "Continue", systemImage: selection.isFinal ? "key.horizontal" : "arrow.right")
                                    .frame(minWidth: 170)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("BountyDesk")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: selection)
        }
    }

    private func advance() {
        guard let next = selection.next else {
            finish()
            return
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            selection = next
        }
    }

    private func finish() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
            onComplete()
        }
    }
}

struct OnboardingProgressHeader: View {
    let selection: OnboardingPage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("First run", systemImage: "sparkle.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selection.rawValue + 1)/\(OnboardingPage.allCases.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary.opacity(0.16))
                    Capsule()
                        .fill(selection.tint.gradient)
                        .frame(width: proxy.size.width * selection.progress)
                }
            }
            .frame(height: 6)
            .accessibilityLabel("Onboarding step \(selection.rawValue + 1) of \(OnboardingPage.allCases.count)")
        }
    }
}

struct OnboardingPagePanel: View {
    let page: OnboardingPage
    let reduceMotion: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                OnboardingSignalGraphic(page: page, reduceMotion: reduceMotion)
                    .frame(width: 330, height: 330)
                pageContent
                    .frame(maxWidth: 430, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 22) {
                OnboardingSignalGraphic(page: page, reduceMotion: reduceMotion)
                    .frame(height: 280)
                pageContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(page.kicker, systemImage: page.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(page.tint)
                .symbolEffect(.bounce, value: page)
            Text(page.title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(3)
                .minimumScaleFactor(0.72)
            Text(page.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(page.evidence) { item in
                    OnboardingEvidenceTile(item: item, tint: page.tint)
                }
            }
        }
    }
}

struct OnboardingSignalGraphic: View {
    let page: OnboardingPage
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
                .overlay(alignment: .topLeading) {
                    MeshGradient(
                        width: 3,
                        height: 3,
                        points: page.meshPoints,
                        colors: page.meshColors
                    )
                    .opacity(0.46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }

            SignalPathView(tint: page.tint)
                .padding(30)

            VStack(spacing: 12) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(page.tint)
                    .frame(width: 86, height: 86)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .symbolEffect(.bounce, value: page)
                Text(page.metric)
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text(page.metricCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .phaseAnimator(reduceMotion ? [OnboardingMotionPhase.settled] : OnboardingMotionPhase.allCases, trigger: page) { content, phase in
            content
                .scaleEffect(phase.scale)
                .rotationEffect(.degrees(phase.rotationDegrees))
        } animation: { phase in
            phase.animation
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.kicker). \(page.metricCaption).")
    }
}

struct SignalPathView: View {
    let tint: Color

    private let nodes: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.18), CGPoint(x: 0.44, y: 0.12), CGPoint(x: 0.78, y: 0.22),
        CGPoint(x: 0.22, y: 0.52), CGPoint(x: 0.56, y: 0.46), CGPoint(x: 0.88, y: 0.58),
        CGPoint(x: 0.18, y: 0.82), CGPoint(x: 0.52, y: 0.78), CGPoint(x: 0.78, y: 0.86)
    ]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let mapped = nodes.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            Path { path in
                guard let first = mapped.first else { return }
                path.move(to: first)
                for point in mapped.dropFirst() {
                    path.addLine(to: point)
                }
                path.move(to: mapped[2])
                path.addLine(to: mapped[4])
                path.addLine(to: mapped[6])
                path.move(to: mapped[1])
                path.addLine(to: mapped[3])
                path.addLine(to: mapped[7])
            }
            .stroke(tint.opacity(0.34), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            ForEach(mapped.indices, id: \.self) { index in
                Circle()
                    .fill(index == 4 ? tint : Color(uiColor: .secondarySystemBackground))
                    .overlay(Circle().stroke(tint.opacity(index == 4 ? 0.8 : 0.32), lineWidth: 2))
                    .frame(width: index == 4 ? 18 : 12, height: index == 4 ? 18 : 12)
                    .position(mapped[index])
            }
        }
        .accessibilityHidden(true)
    }
}

struct OnboardingEvidenceTile: View {
    let item: OnboardingEvidence
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: item.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(item.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct OnboardingSetupStrip: View {
    private let rows: [OnboardingSetupChip] = [
        .init(title: "GitHub first", systemImage: "key.horizontal", tint: .blue),
        .init(title: "Algora verified", systemImage: "checkmark.seal", tint: .green),
        .init(title: "Live competition", systemImage: "person.3", tint: .orange),
        .init(title: "No wallet tracking", systemImage: "wallet.pass", tint: .secondary)
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chips }
            VStack(alignment: .leading, spacing: 8) { chips }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }

    @ViewBuilder
    private var chips: some View {
        ForEach(rows) { row in
            StatusChip(text: row.title, systemImage: row.systemImage, tint: row.tint)
        }
    }
}

struct OnboardingSetupChip: Identifiable {
    let title: String
    let systemImage: String
    let tint: Color
    var id: String { title }
}

struct OnboardingEvidence: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

enum OnboardingMotionPhase: CaseIterable {
    case settled
    case lift
    case align

    var scale: CGFloat {
        switch self {
        case .settled: return 1.0
        case .lift: return 1.025
        case .align: return 1.0
        }
    }

    var rotationDegrees: Double {
        switch self {
        case .settled: return 0
        case .lift: return -1.2
        case .align: return 0.8
        }
    }

    var animation: Animation? {
        switch self {
        case .settled: return .smooth(duration: 0.22)
        case .lift: return .snappy(duration: 0.28)
        case .align: return .smooth(duration: 0.32)
        }
    }
}

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case verify
    case competition
    case manage
    case signIn

    var id: Int { rawValue }

    var kicker: String {
        switch self {
        case .verify: return "Verified source"
        case .competition: return "Before you build"
        case .manage: return "Daily operating view"
        case .signIn: return "Private by default"
        }
    }

    var title: String {
        switch self {
        case .verify: return "Only Algora bounties with proof make the queue."
        case .competition: return "See the claim field before spending hours."
        case .manage: return "Turn bounty work into a clear pipeline."
        case .signIn: return "Connect GitHub and let BountyDesk build the tracker."
        }
    }

    var message: String {
        switch self {
        case .verify:
            return "BountyDesk looks for Algora bot evidence, a visible amount, and the normal attempt or claim flow before it treats an issue as worth tracking."
        case .competition:
            return "Every refresh checks open, closed, merged, and rewarded claim PRs so crowded work does not look cleaner than it is."
        case .manage:
            return "Pin urgent work, stage follow-ups, watch failing checks, and keep merged-unpaid claims visible until the payout signal is real."
        case .signIn:
            return "GitHub access is enough for most solvers. The optional Algora token stays optional unless your workspace actually provides one."
        }
    }

    var systemImage: String {
        switch self {
        case .verify: return "checkmark.seal.fill"
        case .competition: return "person.3.sequence.fill"
        case .manage: return "rectangle.3.group.fill"
        case .signIn: return "key.horizontal.fill"
        }
    }

    var tint: Color {
        switch self {
        case .verify: return .green
        case .competition: return .orange
        case .manage: return .blue
        case .signIn: return .purple
        }
    }

    var metric: String {
        switch self {
        case .verify: return "Algora"
        case .competition: return "/claim"
        case .manage: return "Focus"
        case .signIn: return "GitHub"
        }
    }

    var metricCaption: String {
        switch self {
        case .verify: return "Bot, amount, claim flow"
        case .competition: return "Open PRs and reward links"
        case .manage: return "Stages, notes, follow-ups"
        case .signIn: return "Passkey or token"
        }
    }

    var evidence: [OnboardingEvidence] {
        switch self {
        case .verify:
            return [
                .init(id: "bot", title: "Algora bot", detail: "Required on issue comments", systemImage: "checkmark.seal"),
                .init(id: "amount", title: "Payout amount", detail: "$50, $600, $1,000", systemImage: "dollarsign.circle"),
                .init(id: "claim", title: "Claim flow", detail: "/attempt and /claim", systemImage: "arrow.triangle.branch"),
                .init(id: "exclude", title: "Strict exclude", detail: "No manual wallet tasks", systemImage: "xmark.shield")
            ]
        case .competition:
            return [
                .init(id: "open", title: "Open claims", detail: "Serious active PRs", systemImage: "person.2"),
                .init(id: "merged", title: "Merged claims", detail: "Closed and merged state", systemImage: "arrow.triangle.merge"),
                .init(id: "reward", title: "Reward links", detail: "Paid or winner signals", systemImage: "banknote"),
                .init(id: "checks", title: "Checks", detail: "Pass, fail, pending", systemImage: "checklist")
            ]
        case .manage:
            return [
                .init(id: "stage", title: "Stages", detail: "Inbox to payout", systemImage: "square.stack.3d.up"),
                .init(id: "priority", title: "Priority", detail: "Urgent work rises", systemImage: "flag"),
                .init(id: "follow", title: "Follow-ups", detail: "Dates stay visible", systemImage: "calendar.badge.clock"),
                .init(id: "notes", title: "Notes", detail: "Decision context", systemImage: "note.text")
            ]
        case .signIn:
            return [
                .init(id: "passkey", title: "Passkey", detail: "GitHub device flow", systemImage: "key"),
                .init(id: "private", title: "Private repos", detail: "Only if enabled", systemImage: "lock"),
                .init(id: "keychain", title: "Keychain", detail: "Tokens stay on device", systemImage: "lock.shield"),
                .init(id: "refresh", title: "Refresh", detail: "Live GitHub state", systemImage: "arrow.clockwise")
            ]
        }
    }

    var meshPoints: [SIMD2<Float>] {
        switch self {
        case .verify:
            return [.init(0, 0), .init(0.52, 0.04), .init(1, 0), .init(0.02, 0.50), .init(0.52, 0.48), .init(0.98, 0.42), .init(0, 1), .init(0.50, 0.96), .init(1, 1)]
        case .competition:
            return [.init(0, 0), .init(0.44, 0.0), .init(1, 0), .init(0.05, 0.44), .init(0.62, 0.50), .init(0.95, 0.56), .init(0, 1), .init(0.44, 0.92), .init(1, 1)]
        case .manage:
            return [.init(0, 0), .init(0.60, 0.03), .init(1, 0), .init(0.02, 0.40), .init(0.48, 0.54), .init(0.98, 0.48), .init(0, 1), .init(0.58, 0.98), .init(1, 1)]
        case .signIn:
            return [.init(0, 0), .init(0.48, 0.06), .init(1, 0), .init(0.04, 0.52), .init(0.56, 0.44), .init(0.96, 0.52), .init(0, 1), .init(0.52, 0.92), .init(1, 1)]
        }
    }

    var meshColors: [Color] {
        switch self {
        case .verify:
            return [.green.opacity(0.35), .mint.opacity(0.55), .yellow.opacity(0.28), .teal.opacity(0.45), .green.opacity(0.68), .blue.opacity(0.32), .black.opacity(0.24), .teal.opacity(0.36), .green.opacity(0.44)]
        case .competition:
            return [.orange.opacity(0.48), .red.opacity(0.30), .purple.opacity(0.32), .yellow.opacity(0.30), .orange.opacity(0.64), .pink.opacity(0.28), .black.opacity(0.24), .orange.opacity(0.34), .blue.opacity(0.28)]
        case .manage:
            return [.blue.opacity(0.44), .cyan.opacity(0.34), .green.opacity(0.28), .indigo.opacity(0.30), .blue.opacity(0.64), .teal.opacity(0.34), .black.opacity(0.24), .blue.opacity(0.38), .purple.opacity(0.30)]
        case .signIn:
            return [.purple.opacity(0.42), .blue.opacity(0.32), .pink.opacity(0.28), .indigo.opacity(0.30), .purple.opacity(0.62), .green.opacity(0.28), .black.opacity(0.24), .purple.opacity(0.36), .blue.opacity(0.32)]
        }
    }

    var progress: CGFloat {
        CGFloat(rawValue + 1) / CGFloat(Self.allCases.count)
    }

    var next: OnboardingPage? {
        Self(rawValue: rawValue + 1)
    }

    var isFinal: Bool {
        next == nil
    }
}
