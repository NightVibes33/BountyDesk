import Foundation

struct BountyTrackerService {
    var github = GitHubClient()
    var algoraPublic = AlgoraPublicClient()
    var riskScoring = RiskScoringService()

    func refreshCurrentBounties(githubToken: String, algoraToken: String?, watchedOrgs: [String]) async -> TrackerRefreshResult {
        var result = TrackerRefreshResult()
        do {
            let user = try await github.validateToken(githubToken)
            result.user = user
            let claimPRs = try await github.searchClaimPullRequests(username: user.login, token: githubToken)
            for item in claimPRs.prefix(40) {
                do {
                    let built = try await buildTrackedBounty(from: item, username: user.login, token: githubToken)
                    result.bounties.append(built.bounty)
                    result.pullRequests.append(built.pullRequest)
                    result.issues.append(built.issue)
                    result.ruleSets.append(built.ruleSet)
                    result.competitors.append(contentsOf: built.competitors)
                    result.riskSnapshots.append(built.riskSnapshot)
                } catch {
                    result.warnings.append("Skipped \(item.htmlUrl): \(error.localizedDescription)")
                }
            }
        } catch {
            result.warnings.append(error.localizedDescription)
        }

        await mergeAlgoraData(into: &result, algoraToken: algoraToken, watchedOrgs: watchedOrgs)
        result.bounties = dedupe(result.bounties, by: \.stableID)
        result.pullRequests = dedupe(result.pullRequests, by: \.stableID)
        result.issues = dedupe(result.issues, by: \.stableID)
        result.ruleSets = dedupe(result.ruleSets, by: \.stableID)
        result.competitors = dedupe(result.competitors, by: \.stableID)
        return result
    }

    func discoverBounties(filters: DiscoverFilters, githubToken: String?) async -> DiscoverResult {
        var result = DiscoverResult()
        do {
            let items = try await github.searchOpenBountyIssues(token: githubToken, org: filters.org.nilIfBlank, repo: filters.repo.nilIfBlank, language: filters.language.nilIfBlank, perPage: 50)
            for item in items {
                guard let snapshot = openIssueSnapshot(from: item) else { continue }
                if filters.matches(snapshot: snapshot, commentCount: item.comments ?? 0) {
                    result.bounties.append(snapshot)
                }
            }
        } catch {
            result.warnings.append("GitHub discovery failed: \(error.localizedDescription)")
        }

        if let org = filters.org.nilIfBlank {
            do {
                let algoraBounties = try await algoraPublic.bounties(org: org, limit: 100)
                for dto in algoraBounties.compactMap({ algoraSnapshot(from: $0, source: .algoraPublic) }) where filters.matches(snapshot: dto, commentCount: 0) {
                    result.bounties.append(dto)
                }
            } catch {
                result.warnings.append("Public Algora discovery failed for \(org): \(error.localizedDescription)")
            }
        }

        result.bounties = dedupe(result.bounties, by: \.stableID).sorted { $0.updatedAt > $1.updatedAt }
        return result
    }

    func manualSnapshot(from text: String) -> TrackedBountySnapshot? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "github.com" || host == "www.github.com" {
            guard parts.count >= 4, ["issues", "pull"].contains(parts[2]), let number = Int(parts[3]) else { return nil }
            return manualSnapshot(owner: parts[0], repo: parts[1], issue: number, pull: parts[2] == "pull" ? number : nil, url: trimmed)
        }
        if host.contains("algora") {
            guard parts.count >= 4, parts[2] == "issues", let number = Int(parts[3]) else { return nil }
            return manualSnapshot(owner: parts[0], repo: parts[1], issue: number, pull: nil, url: trimmed)
        }
        return nil
    }

    private func buildTrackedBounty(from item: GitHubSearchItem, username: String, token: String) async throws -> BuiltBounty {
        guard let slug = GitHubClient.repositorySlug(from: item.repositoryUrl) else { throw GitHubAPIError.invalidURL }
        async let prTask = github.pullRequest(owner: slug.owner, repo: slug.repo, number: item.number, token: token)
        async let prIssueCommentsTask = github.issueComments(owner: slug.owner, repo: slug.repo, number: item.number, token: token)
        let pr = try await prTask
        let prIssueComments = (try? await prIssueCommentsTask) ?? []
        let prBody = pr.body ?? item.body ?? ""
        let linkedIssues = BountyParsing.linkedIssueNumbers(in: prBody + "\n" + prIssueComments.map(\.body).joined(separator: "\n"))
        let issueNumber = linkedIssues.first ?? item.number
        async let issueTask = github.issue(owner: slug.owner, repo: slug.repo, number: issueNumber, token: token)
        async let issueCommentsTask = github.issueComments(owner: slug.owner, repo: slug.repo, number: issueNumber, token: token)
        async let repositoryTask = github.repository(owner: slug.owner, repo: slug.repo, token: token)
        async let checksTask = github.checkRuns(owner: slug.owner, repo: slug.repo, ref: pr.head.sha, token: token)
        async let statusTask = github.combinedStatus(owner: slug.owner, repo: slug.repo, ref: pr.head.sha, token: token)
        let issue = (try? await issueTask) ?? fallbackIssue(from: item, owner: slug.owner, repo: slug.repo, number: issueNumber)
        let issueComments = (try? await issueCommentsTask) ?? []
        let repository = try? await repositoryTask
        let checkRuns = try? await checksTask
        let statuses = try? await statusTask
        let allComments = prIssueComments + issueComments
        let labels = Array(Set((item.labels + (pr.labels ?? []) + issue.labels).map(\.name))).sorted()
        let bodyCorpus = [issue.body, pr.body, item.body].compactMap { $0 }.joined(separator: "\n")
        let commentCorpus = allComments.map(\.body)
        let textCorpus = ([bodyCorpus] + commentCorpus).joined(separator: "\n")
        let amount = BountyParsing.bountyAmount(in: labels.joined(separator: " ") + "\n" + textCorpus) ?? 0
        let claimStatus = BountyParsing.paymentStatus(in: textCorpus) ?? BountyParsing.claimStatus(in: textCorpus) ?? .unknown
        let checkState = resolveCheckState(checkRuns: checkRuns, statuses: statuses)
        let prState = resolvePullRequestState(pr)
        let issueState = issue.state.lowercased() == "closed" ? IssueState.closed : IssueState.open
        let competitors = await competitorSnapshots(owner: slug.owner, repo: slug.repo, issueNumber: issueNumber, username: username, ownPR: pr.number, token: token)
        let competitorMerged = competitors.contains { $0.state == .merged }
        let codeOfConduct = await firstRepositoryFile(owner: slug.owner, repo: slug.repo, paths: ["CODE_OF_CONDUCT.md", ".github/CODE_OF_CONDUCT.md"], token: token)
        let contributing = await firstRepositoryFile(owner: slug.owner, repo: slug.repo, paths: ["CONTRIBUTING.md", ".github/CONTRIBUTING.md"], token: token)
        let readme = await firstRepositoryFile(owner: slug.owner, repo: slug.repo, paths: ["README.md", "readme.md"], token: token)
        let rulesCorpus = [codeOfConduct, contributing, readme, issue.body].compactMap { $0 }.joined(separator: "\n")
        let requiresVideo = BountyParsing.requiresVideo(in: rulesCorpus + "\n" + textCorpus)
        let hasDemoProof = BountyParsing.hasDemoProof(in: prBody + "\n" + prIssueComments.map(\.body).joined(separator: "\n"))
        let assignmentRequired = BountyParsing.assignmentRequired(in: rulesCorpus + "\n" + textCorpus)
        let maintainerAssignmentRequired = BountyParsing.maintainerAssignmentRequired(in: rulesCorpus + "\n" + textCorpus)
        let userAssigned = issue.assignees?.contains { $0.login.caseInsensitiveCompare(username) == .orderedSame } ?? false
        let priorRejected = BountyParsing.priorRejectedSignal(in: textCorpus, username: username)
        let hasVerification = BountyParsing.hasClearVerification(in: prBody)
        let hasTests = BountyParsing.hasTests(in: prBody)
        let latestMaintainer = BountyParsing.latestMaintainerComment(from: allComments, excluding: username)
        let latestBot = BountyParsing.latestBotComment(from: allComments)
        let rewarded = claimStatus == .paymentSucceeded || textCorpus.lowercased().contains("total paid") || textCorpus.lowercased().contains("rewarded")
        let riskInput = RiskInput(
            pullRequestState: prState,
            issueState: issueState,
            checkState: checkState,
            claimStatus: claimStatus,
            mergeableState: pr.mergeableState ?? (pr.mergeable == false ? "blocked" : "unknown"),
            hasMaintainerComment: latestMaintainer.isEmpty == false,
            competitionCount: competitors.count,
            competitorMerged: competitorMerged,
            issueAlreadyRewarded: rewarded,
            assignmentRequired: assignmentRequired || maintainerAssignmentRequired,
            userAppearsAssigned: userAssigned,
            demoVideoRequired: requiresVideo,
            demoProofPresent: hasDemoProof,
            repoArchived: repository?.archived ?? false,
            priorRejectedSignal: priorRejected,
            hasClearVerification: hasVerification,
            hasTests: hasTests,
            contributingRulesFound: contributing != nil,
            codeOfConductFound: codeOfConduct != nil
        )
        let risk = riskScoring.score(riskInput)
        let stableID = "github:\(slug.owner)/\(slug.repo)#\(issueNumber):pr\(pr.number)"
        let now = Date()
        let evidence = BountyParsing.algoraEvidence(labels: labels, body: bodyCorpus, comments: commentCorpus)
        let rewardLinks = BountyParsing.rewardLinks(in: textCorpus)
        let bounty = TrackedBountySnapshot(
            stableID: stableID,
            source: .github,
            repoOwner: slug.owner,
            repoName: slug.repo,
            issueNumber: issueNumber,
            linkedPullRequestNumber: pr.number,
            title: issue.title,
            issueBodySummary: (issue.body ?? "").trimmedSummary(limit: 420),
            pullRequestSummary: prBody.trimmedSummary(limit: 420),
            amount: amount,
            labels: labels,
            algoraEvidence: evidence,
            rewardLinks: rewardLinks,
            workflowStatus: workflowStatus(prState: prState, claimStatus: claimStatus, checkState: checkState),
            issueState: issueState,
            claimStatus: claimStatus,
            checkState: checkState,
            riskLevel: risk.level,
            payoutChance: risk.score,
            riskFactors: risk.factors,
            nextAction: risk.nextAction,
            latestMaintainerComment: latestMaintainer,
            latestBotComment: latestBot,
            competitionCount: competitors.count,
            hasRewardedSignal: rewarded,
            requiresVideo: requiresVideo,
            hasDemoProof: hasDemoProof,
            repoArchived: repository?.archived ?? false,
            assignedOnly: assignmentRequired,
            userAppearsAssigned: userAssigned,
            maintainerAssignmentRequired: maintainerAssignmentRequired,
            priorRejectedSignal: priorRejected,
            hasClearVerification: hasVerification,
            hasTests: hasTests,
            createdAt: item.createdAt,
            updatedAt: maxDate(pr.updatedAt, issue.updatedAt),
            lastRefreshedAt: now
        )
        let pull = PullRequestSnapshot(
            stableID: "github:\(slug.owner)/\(slug.repo):pr\(pr.number)",
            bountyStableID: stableID,
            repoOwner: slug.owner,
            repoName: slug.repo,
            number: pr.number,
            title: pr.title,
            authorLogin: pr.user.login,
            bodySummary: prBody.trimmedSummary(limit: 420),
            htmlURLString: pr.htmlUrl,
            state: prState,
            isDraft: pr.draft ?? false,
            mergeableState: pr.mergeableState ?? "unknown",
            headSHA: pr.head.sha,
            labels: (pr.labels ?? []).map(\.name),
            checkState: checkState,
            latestComment: BountyParsing.latestComment(from: prIssueComments),
            latestMaintainerComment: latestMaintainer,
            changedFiles: pr.changedFiles ?? 0,
            additions: pr.additions ?? 0,
            deletions: pr.deletions ?? 0,
            hasDemoProof: hasDemoProof,
            hasTests: hasTests,
            updatedAt: pr.updatedAt
        )
        let issueSnapshot = GitHubIssueSnapshot(
            stableID: "github:\(slug.owner)/\(slug.repo):issue\(issueNumber)",
            bountyStableID: stableID,
            repoOwner: slug.owner,
            repoName: slug.repo,
            number: issueNumber,
            title: issue.title,
            bodySummary: (issue.body ?? "").trimmedSummary(limit: 420),
            htmlURLString: issue.htmlUrl,
            state: issueState,
            labels: issue.labels.map(\.name),
            latestComment: BountyParsing.latestComment(from: issueComments),
            latestBotComment: latestBot,
            hasAlgoraEvidence: BountyParsing.hasAlgoraEvidence(labels: labels, body: bodyCorpus, comments: commentCorpus),
            bountyAmount: amount,
            requiresVideo: requiresVideo,
            hasRewardedSignal: rewarded,
            updatedAt: issue.updatedAt
        )
        let ruleSet = RepoRuleSetSnapshot(
            stableID: "github:\(slug.owner)/\(slug.repo):rules",
            bountyStableID: stableID,
            repoOwner: slug.owner,
            repoName: slug.repo,
            codeOfConductSummary: (codeOfConduct ?? "Not found").trimmedSummary(limit: 420),
            contributingSummary: (contributing ?? "Not found").trimmedSummary(limit: 420),
            readmeSummary: (readme ?? "Not found").trimmedSummary(limit: 420),
            testCommands: BountyParsing.testCommands(in: [contributing, readme].compactMap { $0 }.joined(separator: "\n")),
            requiresDemoVideo: requiresVideo,
            assignmentRequired: assignmentRequired,
            maintainerAssignmentRequired: maintainerAssignmentRequired,
            repoArchived: repository?.archived ?? false,
            updatedAt: now
        )
        let riskSnapshot = RiskSnapshotData(stableID: UUID().uuidString, bountyStableID: stableID, score: risk.score, level: risk.level, factors: risk.factors, nextAction: risk.nextAction, createdAt: Date())
        return BuiltBounty(bounty: bounty, pullRequest: pull, issue: issueSnapshot, ruleSet: ruleSet, competitors: competitors, riskSnapshot: riskSnapshot)
    }

    private func mergeAlgoraData(into result: inout TrackerRefreshResult, algoraToken: String?, watchedOrgs: [String]) async {
        let orgs = watchedOrgs.filter { $0.isEmpty == false }
        for org in orgs {
            do {
                let bounties = try await algoraPublic.bounties(org: org, limit: 100)
                result.bounties.append(contentsOf: bounties.compactMap { algoraSnapshot(from: $0, source: .algoraPublic) })
                let claims = try await algoraPublic.claims(org: org, limit: 100)
                result.claims.append(contentsOf: claims.compactMap { claimSnapshot(from: $0, org: org) })
            } catch {
                result.warnings.append("Public Algora data unavailable for \(org): \(error.localizedDescription). Continuing in GitHub mode.")
            }
        }

        let authenticated = AlgoraAuthenticatedClient(token: algoraToken)
        guard authenticated.isConfigured else { return }
        do {
            let authedBounties = try await authenticated.bounties(limit: 100)
            result.bounties.append(contentsOf: authedBounties.compactMap { algoraSnapshot(from: $0, source: .algoraAuthenticated) })
            let authedClaims = try await authenticated.claims(limit: 100)
            result.claims.append(contentsOf: authedClaims.compactMap { claimSnapshot(from: $0, org: "authenticated") })
        } catch {
            result.warnings.append("Authenticated Algora API failed: \(error.localizedDescription). Continuing with GitHub and public data.")
        }
    }

    private func algoraSnapshot(from dto: AlgoraBountyDTO, source: BountySource) -> TrackedBountySnapshot? {
        guard let task = dto.task, let owner = task.repoOwner, let repo = task.repoName, let number = task.number else { return nil }
        let text = [task.title, task.body, dto.rewardFormatted].compactMap { $0 }.joined(separator: "\n")
        let amount = dto.reward?.amount ?? BountyParsing.bountyAmount(in: text) ?? 0
        let claimStatuses = dto.claims?.compactMap { $0.status.map(statusFromAlgora) } ?? []
        let claim = claimStatuses.bestClaimStatus()
        let active = dto.status?.lowercased() == "active"
        let risk = riskScoring.score(RiskInput(
            pullRequestState: .unknown,
            issueState: active ? .open : .closed,
            checkState: .unknown,
            claimStatus: claim,
            mergeableState: "unknown",
            hasMaintainerComment: false,
            competitionCount: dto.claims?.count ?? 0,
            competitorMerged: false,
            issueAlreadyRewarded: claim == .paymentSucceeded,
            assignmentRequired: BountyParsing.assignmentRequired(in: text),
            userAppearsAssigned: false,
            demoVideoRequired: BountyParsing.requiresVideo(in: text),
            demoProofPresent: false,
            repoArchived: false,
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            contributingRulesFound: false,
            codeOfConductFound: false
        ))
        let updated = dto.updatedAt ?? dto.createdAt ?? Date()
        return TrackedBountySnapshot(
            stableID: "algora:\(owner)/\(repo)#\(number)",
            source: source,
            repoOwner: owner,
            repoName: repo,
            issueNumber: number,
            linkedPullRequestNumber: nil,
            title: task.title ?? "Algora bounty",
            issueBodySummary: (task.body ?? "").trimmedSummary(limit: 420),
            pullRequestSummary: "",
            amount: amount,
            labels: ["Algora", "Bounty"],
            algoraEvidence: ["Algora bounty API record"],
            rewardLinks: [task.url].compactMap { $0 },
            workflowStatus: active ? .watching : .lost,
            issueState: active ? .open : .closed,
            claimStatus: claim,
            checkState: .unknown,
            riskLevel: risk.level,
            payoutChance: risk.score,
            riskFactors: risk.factors,
            nextAction: risk.nextAction,
            latestMaintainerComment: "",
            latestBotComment: "",
            competitionCount: dto.claims?.count ?? 0,
            hasRewardedSignal: claim == .paymentSucceeded,
            requiresVideo: BountyParsing.requiresVideo(in: text),
            hasDemoProof: false,
            repoArchived: false,
            assignedOnly: BountyParsing.assignmentRequired(in: text),
            userAppearsAssigned: false,
            maintainerAssignmentRequired: BountyParsing.maintainerAssignmentRequired(in: text),
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            createdAt: dto.createdAt ?? updated,
            updatedAt: updated,
            lastRefreshedAt: Date()
        )
    }

    private func openIssueSnapshot(from item: GitHubSearchItem) -> TrackedBountySnapshot? {
        guard let slug = GitHubClient.repositorySlug(from: item.repositoryUrl) else { return nil }
        let labels = item.labels.map(\.name)
        let body = item.body ?? ""
        let evidence = BountyParsing.algoraEvidence(labels: labels, body: body, comments: [])
        let amount = BountyParsing.bountyAmount(in: labels.joined(separator: " ") + "\n" + body) ?? 0
        let claim = BountyParsing.claimStatus(in: body) ?? .unknown
        let risk = riskScoring.score(RiskInput(
            pullRequestState: .unknown,
            issueState: item.state.lowercased() == "closed" ? .closed : .open,
            checkState: .unknown,
            claimStatus: claim,
            mergeableState: "unknown",
            hasMaintainerComment: false,
            competitionCount: item.comments ?? 0,
            competitorMerged: false,
            issueAlreadyRewarded: body.lowercased().contains("total paid") || body.lowercased().contains("rewarded"),
            assignmentRequired: BountyParsing.assignmentRequired(in: body),
            userAppearsAssigned: false,
            demoVideoRequired: BountyParsing.requiresVideo(in: body),
            demoProofPresent: false,
            repoArchived: false,
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            contributingRulesFound: false,
            codeOfConductFound: false
        ))
        return TrackedBountySnapshot(
            stableID: "github-discover:\(slug.owner)/\(slug.repo)#\(item.number)",
            source: .github,
            repoOwner: slug.owner,
            repoName: slug.repo,
            issueNumber: item.number,
            linkedPullRequestNumber: nil,
            title: item.title,
            issueBodySummary: body.trimmedSummary(limit: 420),
            pullRequestSummary: "",
            amount: amount,
            labels: labels,
            algoraEvidence: evidence,
            rewardLinks: BountyParsing.rewardLinks(in: body),
            workflowStatus: .watching,
            issueState: item.state.lowercased() == "closed" ? .closed : .open,
            claimStatus: claim,
            checkState: .unknown,
            riskLevel: risk.level,
            payoutChance: risk.score,
            riskFactors: risk.factors,
            nextAction: risk.nextAction,
            latestMaintainerComment: "",
            latestBotComment: "",
            competitionCount: item.comments ?? 0,
            hasRewardedSignal: body.lowercased().contains("total paid") || body.lowercased().contains("rewarded"),
            requiresVideo: BountyParsing.requiresVideo(in: body),
            hasDemoProof: false,
            repoArchived: false,
            assignedOnly: BountyParsing.assignmentRequired(in: body),
            userAppearsAssigned: false,
            maintainerAssignmentRequired: BountyParsing.maintainerAssignmentRequired(in: body),
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            createdAt: item.createdAt,
            updatedAt: item.updatedAt,
            lastRefreshedAt: Date()
        )
    }

    private func manualSnapshot(owner: String, repo: String, issue: Int, pull: Int?, url: String) -> TrackedBountySnapshot {
        let now = Date()
        return TrackedBountySnapshot(
            stableID: "manual:\(owner)/\(repo)#\(issue):\(pull.map { String($0) } ?? "issue")",
            source: .manual,
            repoOwner: owner,
            repoName: repo,
            issueNumber: issue,
            linkedPullRequestNumber: pull,
            title: "Manual bounty candidate",
            issueBodySummary: "Imported from \(url). Refresh with GitHub token to fill live metadata.",
            pullRequestSummary: "",
            amount: 0,
            labels: ["Manual"],
            algoraEvidence: [],
            rewardLinks: [url],
            workflowStatus: .watching,
            issueState: .unknown,
            claimStatus: .unknown,
            checkState: .unknown,
            riskLevel: .medium,
            payoutChance: 50,
            riskFactors: ["Manual import has not been refreshed yet"],
            nextAction: "Refresh after signing in with GitHub to fetch live issue and PR data.",
            latestMaintainerComment: "",
            latestBotComment: "",
            competitionCount: 0,
            hasRewardedSignal: false,
            requiresVideo: false,
            hasDemoProof: false,
            repoArchived: false,
            assignedOnly: false,
            userAppearsAssigned: false,
            maintainerAssignmentRequired: false,
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            createdAt: now,
            updatedAt: now,
            lastRefreshedAt: nil
        )
    }

    private func competitorSnapshots(owner: String, repo: String, issueNumber: Int, username: String, ownPR: Int, token: String) async -> [CompetitorPRSnapshot] {
        let items = (try? await github.searchCompetitorPullRequests(owner: owner, repo: repo, issueNumber: issueNumber, token: token)) ?? []
        var snapshots: [CompetitorPRSnapshot] = []
        for item in items.prefix(12) where item.number != ownPR && item.user.login.caseInsensitiveCompare(username) != .orderedSame {
            if let pr = try? await github.pullRequest(owner: owner, repo: repo, number: item.number, token: token) {
                let state = resolvePullRequestState(pr)
                snapshots.append(CompetitorPRSnapshot(
                    stableID: "github:\(owner)/\(repo):competitor-pr\(item.number)",
                    bountyStableID: "github:\(owner)/\(repo)#\(issueNumber):pr\(ownPR)",
                    number: item.number,
                    authorLogin: item.user.login,
                    title: item.title,
                    htmlURLString: item.htmlUrl,
                    state: state,
                    checkState: .unknown,
                    changedFiles: pr.changedFiles ?? 0,
                    additions: pr.additions ?? 0,
                    deletions: pr.deletions ?? 0,
                    labels: (pr.labels ?? item.labels).map(\.name),
                    latestComment: item.body?.trimmedSummary(limit: 220) ?? "",
                    hasDemoProof: BountyParsing.hasDemoProof(in: pr.body ?? item.body ?? ""),
                    hasMaintainerApproval: (pr.labels ?? []).contains { $0.name.lowercased().contains("approved") || $0.name.lowercased().contains("reviewed") },
                    updatedAt: pr.updatedAt
                ))
            }
        }
        return snapshots
    }

    private func firstRepositoryFile(owner: String, repo: String, paths: [String], token: String) async -> String? {
        for path in paths {
            if let file = await github.repositoryFile(owner: owner, repo: repo, path: path, token: token) {
                return file
            }
        }
        return nil
    }

    private func fallbackIssue(from item: GitHubSearchItem, owner: String, repo: String, number: Int) -> GitHubIssueResponse {
        GitHubIssueResponse(
            htmlUrl: "https://github.com/\(owner)/\(repo)/issues/\(number)",
            number: number,
            state: item.state,
            title: item.title,
            body: item.body,
            labels: item.labels,
            user: item.user,
            assignees: [],
            updatedAt: item.updatedAt,
            closedAt: nil
        )
    }

    private func claimSnapshot(from dto: AlgoraClaimDTO, org: String) -> ClaimSnapshot? {
        guard let id = dto.id else { return nil }
        let status = dto.status.map(statusFromAlgora) ?? .unknown
        return ClaimSnapshot(
            stableID: "algora-claim:\(org):\(id)",
            bountyStableID: "algora-claim-unlinked:\(id)",
            status: status,
            solverLogin: dto.solver?.login,
            urlString: dto.url,
            transferAmount: dto.transferAmount ?? 0,
            transferCurrency: dto.transferCurrency ?? "USD",
            createdAt: dto.createdAt ?? Date(),
            updatedAt: dto.updatedAt ?? Date()
        )
    }

    private func resolvePullRequestState(_ pr: GitHubPullRequestResponse) -> PullRequestState {
        if pr.mergedAt != nil { return .merged }
        if pr.draft == true { return .draft }
        if pr.state.lowercased() == "closed" { return .closed }
        if pr.state.lowercased() == "open" { return .open }
        return .unknown
    }

    private func resolveCheckState(checkRuns: GitHubCheckRunsResponse?, statuses: GitHubCombinedStatusResponse?) -> CheckState {
        let runs = checkRuns?.checkRuns ?? []
        let commitStatuses = statuses?.statuses ?? []
        guard runs.isEmpty == false || commitStatuses.isEmpty == false else { return .noneConfigured }
        let runConclusions = runs.compactMap { $0.conclusion?.lowercased() }
        let runStatuses = runs.map { $0.status.lowercased() }
        let statusStates = commitStatuses.map { $0.state.lowercased() } + [statuses?.state.lowercased()].compactMap { $0 }
        if runConclusions.contains(where: { ["failure", "cancelled", "timed_out", "action_required"].contains($0) }) || statusStates.contains(where: { ["failure", "error"].contains($0) }) {
            return .failing
        }
        if runStatuses.contains(where: { ["queued", "in_progress", "waiting", "requested"].contains($0) }) || statusStates.contains("pending") {
            return .pending
        }
        if runs.isEmpty == false && runConclusions.allSatisfy({ ["success", "neutral", "skipped"].contains($0) }) {
            return .passing
        }
        if commitStatuses.isEmpty == false && statusStates.allSatisfy({ $0 == "success" }) {
            return .passing
        }
        return .unknown
    }

    private func workflowStatus(prState: PullRequestState, claimStatus: ClaimStatus, checkState: CheckState) -> BountyWorkflowStatus {
        switch claimStatus {
        case .paymentSucceeded: return .paid
        case .paymentProcessing, .accepted: return .mergedUnpaid
        case .rejected: return .lost
        default: break
        }
        switch prState {
        case .merged: return .mergedUnpaid
        case .closed: return .lost
        case .draft: return .submitted
        case .open: return checkState == .passing ? .pendingReview : .submitted
        case .unknown: return .claimed
        }
    }

    private func statusFromAlgora(_ raw: String) -> ClaimStatus {
        switch raw.lowercased() {
        case "pending": return .pending
        case "accepted", "approved": return .accepted
        case "payment_processing": return .paymentProcessing
        case "payment_succeeded", "paid": return .paymentSucceeded
        case "rejected", "declined": return .rejected
        default: return .unknown
        }
    }

    private func maxDate(_ lhs: Date, _ rhs: Date) -> Date { lhs > rhs ? lhs : rhs }

    private func dedupe<T>(_ values: [T], by keyPath: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        return values.filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

struct TrackerRefreshResult {
    var user: GitHubUser?
    var bounties: [TrackedBountySnapshot] = []
    var pullRequests: [PullRequestSnapshot] = []
    var issues: [GitHubIssueSnapshot] = []
    var ruleSets: [RepoRuleSetSnapshot] = []
    var competitors: [CompetitorPRSnapshot] = []
    var claims: [ClaimSnapshot] = []
    var riskSnapshots: [RiskSnapshotData] = []
    var warnings: [String] = []
}

struct DiscoverResult {
    var bounties: [TrackedBountySnapshot] = []
    var warnings: [String] = []
}

struct DiscoverFilters: Equatable {
    var org = ""
    var repo = ""
    var language = ""
    var minimumPayout = 0
    var maximumPayout = 25_000
    var recentlyUpdated = true
    var lowCompetition = false
    var activeOnly = true
    var noPaidSignal = true
    var finishableToday = false
    var requiresVideo: Bool?
    var assignmentRequired: Bool?
    var onlyAlgoraEvidence = true

    func matches(snapshot: TrackedBountySnapshot, commentCount: Int) -> Bool {
        if activeOnly && snapshot.issueState == .closed { return false }
        if noPaidSignal && snapshot.hasRewardedSignal { return false }
        if onlyAlgoraEvidence && snapshot.algoraEvidence.isEmpty { return false }
        if snapshot.amount > 0 && snapshot.amount < minimumPayout { return false }
        if maximumPayout > 0 && snapshot.amount > maximumPayout { return false }
        if lowCompetition && max(snapshot.competitionCount, commentCount) > 5 { return false }
        if finishableToday && snapshot.amount > 750 { return false }
        if let requiresVideo, snapshot.requiresVideo != requiresVideo { return false }
        if let assignmentRequired, snapshot.assignedOnly != assignmentRequired { return false }
        return true
    }
}

private struct BuiltBounty {
    var bounty: TrackedBountySnapshot
    var pullRequest: PullRequestSnapshot
    var issue: GitHubIssueSnapshot
    var ruleSet: RepoRuleSetSnapshot
    var competitors: [CompetitorPRSnapshot]
    var riskSnapshot: RiskSnapshotData
}

private extension Array where Element == ClaimStatus {
    func bestClaimStatus() -> ClaimStatus {
        if contains(.paymentSucceeded) { return .paymentSucceeded }
        if contains(.paymentProcessing) { return .paymentProcessing }
        if contains(.accepted) { return .accepted }
        if contains(.pending) { return .pending }
        if contains(.rejected) { return .rejected }
        return .unknown
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
