import SwiftData
import SwiftUI

let apiAccessHelpText = """
BountyDesk works best with GitHub login. Most users do not need an Algora API token.

GitHub access lets the app find your claimed PRs, linked bounty issues, checks, comments, labels, and competition.

Algora API token support is optional. Algora's docs mention Bearer-token API endpoints, but normal solver accounts may not show an API key page. If you do not see API keys in Algora, continue without one.

If you own or manage an Algora workspace, check workspace settings for API keys or contact Algora support.
"""

let algoraSupportMessage = """
Hi Algora team, I'm building/using a bounty tracking app and would like API access for my workspace. I need read access to bounties and claims so I can query bounty status, claim status, and payment status programmatically. Can you enable API token access for my account/workspace?
"""

struct LoginView: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var githubToken = ""
    @State private var algoraToken = ""
    @State private var includePrivateRepositories = false

    var body: some View {
        NavigationStack {
            ZStack {
                BountyBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        LoginHero()

                        VStack(alignment: .leading, spacing: 16) {
                            Button {
                                Task {
                                    if let url = await app.startGitHubDeviceLogin(includePrivateRepositories: includePrivateRepositories) {
                                        openURL(url)
                                    }
                                }
                            } label: {
                                Label(app.isStartingGitHubDeviceLogin ? "Preparing GitHub" : "Continue with GitHub Passkey", systemImage: "key.horizontal")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(app.isStartingGitHubDeviceLogin || app.isFinishingGitHubDeviceLogin || app.githubDeviceAuthorization != nil)
                            .symbolEffect(.bounce, value: app.githubDeviceAuthorization != nil)

                            Toggle("Include private repositories", isOn: $includePrivateRepositories)
                            Text(includePrivateRepositories ? "Request private and public repository read access." : "Request public repository read access.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            if let authorization = app.githubDeviceAuthorization {
                                GitHubDeviceLoginPanel(authorization: authorization)
                                    .padding(.vertical, 6)
                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            }

                            Divider().overlay(.secondary.opacity(0.25))

                            SecureField("GitHub personal access token", text: $githubToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button {
                                Task { await app.saveGitHubToken(githubToken) }
                            } label: {
                                Label("Use GitHub Token", systemImage: "checkmark.shield")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(githubToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(18)
                        .bountyGlassCard(cornerRadius: 8, interactive: true)

                        VStack(alignment: .leading, spacing: 12) {
                            Label("Optional Algora API", systemImage: "link.badge.plus")
                                .font(.headline)
                            SecureField("Algora API token", text: $algoraToken)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textFieldStyle(.roundedBorder)
                            Button("Save Optional Algora Token") { app.saveAlgoraToken(algoraToken) }
                                .buttonStyle(.bordered)
                            Text("Most solver accounts can continue without this. GitHub login is enough for PR, issue, comment, check, and public bounty evidence.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .bountyGlassCard(cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(apiAccessHelpText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button { app.copyToClipboard(algoraSupportMessage) } label: {
                                Label("Copy Algora Support Message", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(18)
                        .bountyGlassCard(cornerRadius: 8)

                        if let error = app.authError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .bountyGlassCard(cornerRadius: 8)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            if app.githubDeviceAuthorization != nil {
                                Button {
                                    Task { await app.finishGitHubDeviceLogin() }
                                } label: {
                                    Label("Check Sign In Again", systemImage: "arrow.clockwise.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(app.isFinishingGitHubDeviceLogin)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("BountyDesk")
            .navigationBarTitleDisplayMode(.inline)
            .animation(reduceMotion ? nil : .snappy, value: app.githubDeviceAuthorization != nil)
            .animation(reduceMotion ? nil : .snappy, value: app.authError)
        }
    }
}

struct LoginHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Circle()
                    .fill(.green.opacity(0.18))
                    .frame(width: 76, height: 76)
                Image(systemName: "target")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("BountyDesk")
                    .font(.largeTitle.weight(.bold))
                Text("Track Algora bounty PRs, claim status, checks, maintainer signals, and payout risk from GitHub.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .bountyGlassCard(cornerRadius: 8, interactive: true)
    }
}

struct GitHubDeviceLoginPanel: View {
    @EnvironmentObject private var app: BountyTrackerViewModel
    @Environment(\.openURL) private var openURL
    let authorization: GitHubDeviceAuthorization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Code") {
                Text(authorization.userCode)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
            }
            LabeledContent("Access", value: authorization.scopeDescription)
            if app.isFinishingGitHubDeviceLogin {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for GitHub approval.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("Approve in GitHub, then return here. BountyDesk keeps this code until it expires.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Expires") {
                Text(authorization.expiresAt, style: .relative)
            }
            HStack {
                Button {
                    if let url = authorization.verificationURL { openURL(url) }
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                }
                Button {
                    app.copyToClipboard(authorization.userCode)
                } label: {
                    Label("Copy Code", systemImage: "doc.on.doc")
                }
            }
            Button {
                Task { await app.finishGitHubDeviceLogin() }
            } label: {
                Label(app.isFinishingGitHubDeviceLogin ? "Waiting for GitHub" : "Check Sign In Now", systemImage: "checkmark.circle")
            }
            .disabled(app.isFinishingGitHubDeviceLogin)
            Button("Cancel", role: .cancel) { app.cancelGitHubDeviceLogin() }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}
