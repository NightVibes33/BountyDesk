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
            let claimPRs: [GitHubSearchItem]
            do {
                claimPRs = try await github.searchClaimPullRequests(username: user.login, token: githubToken)
            } catch {
                claimPRs = []
                result.warnings.append("Claim PR search failed: \(error.localizedDescription). Continuing with linked-issue evidence checks.")
            }
            let recentPRs: [GitHubSearchItem]
            do {
                recentPRs = try await github.searchRecentAuthoredPullRequests(username: user.login, token: githubToken)
            } catch {
                recentPRs = []
                result.warnings.append("Linked-issue evidence check failed: \(error.localizedDescription).")
            }
            result.claimPullRequestCount = claimPRs.count
            result.activeClaimPullRequestCount = 0
            result.linkedIssueCheckCount = recentPRs.count
            let directClaimURLs = Set(claimPRs.map(\.htmlUrl))
            let candidates = dedupeSearchItems(claimPRs + recentPRs)
            result.scannedPullRequestCount = candidates.count
            for item in candidates.prefix(90) {
                do {
                    let built = try await buildTrackedBounty(from: item, username: user.login, token: githubToken, allowDirectBotClaim: directClaimURLs.contains(item.htmlUrl))
                    result.bounties.append(built.bounty)
                    result.pullRequests.append(built.pullRequest)
                    result.issues.append(built.issue)
                    result.ruleSets.append(built.ruleSet)
                    result.competitors.append(contentsOf: built.competitors)
                    result.riskSnapshots.append(built.riskSnapshot)
                    if built.pullRequest.state == .open || built.pullRequest.state == .draft {
                        result.activeClaimPullRequestCount += 1
                    }
                } catch BountyTrackerServiceError.noBountyEvidence {
                    result.skippedPullRequestCount += 1
                    continue
                } catch {
                    result.failedPullRequestCount += 1
                    result.warnings.append("Skipped \(item.htmlUrl): \(error.localizedDescription)")
                }
            }
        } catch {
            result.warnings.append(error.localizedDescription)
        }

        await mergeAlgoraData(into: &result, githubToken: githubToken, algoraToken: algoraToken, watchedOrgs: watchedOrgs)
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
                guard let snapshot = await openIssueSnapshot(from: item, token: githubToken) else { continue }
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
                for dto in algoraBounties {
                    guard let snapshot = await algoraSnapshot(from: dto, source: .algoraPublic, githubToken: githubToken) else { continue }
                    if filters.matches(snapshot: snapshot, commentCount: 0) {
                        result.bounties.append(snapshot)
                    }
                }
            } catch {
                result.warnings.append("Public Algora discovery failed for \(org): \(error.localizedDescription)")
            }
        }

        result.bounties = dedupe(result.bounties, by: \.stableID).sorted { $0.updatedAt > $1.updatedAt }
        return result
    }

    func manualSnapshot(from text: String) -> TrackedBountySnapshot? {
        nil
    }

    private func buildTrackedBounty(from item: GitHubSearchItem, username: String, token: String, allowDirectBotClaim: Bool) async throws -> BuiltBounty {
        guard let slug = GitHubClient.repositorySlug(from: item.repositoryUrl) else { throw GitHubAPIError.invalidURL }
        async let prTask = github.pullRequest(owner: slug.owner, repo: slug.repo, number: item.number, token: token)
        async let prIssueCommentsTask = github.issueComments(owner: slug.owner, repo: slug.repo, number: item.number, token: token)
        async let prIssueEventsTask = github.issueEvents(owner: slug.owner, repo: slug.repo, number: item.number, token: token)
        let pr = try await prTask
        let prIssueComments = (try? await prIssueCommentsTask) ?? []
        let prIssueEvents = (try? await prIssueEventsTask) ?? []
        let prBody = pr.body ?? item.body ?? ""
        let prEvidenceText = prBody + "\n" + prIssueComments.map(\.body).joined(separator: "\n")
        let claimIssues = BountyParsing.claimIssueNumbers(in: prEvidenceText)
        let linkedIssues = BountyParsing.linkedIssueNumbers(in: prEvidenceText).filter { claimIssues.contains($0) == false }
        let issueNumber = (claimIssues + linkedIssues).first ?? item.number
        async let issueTask = github.issue(owner: slug.owner, repo: slug.repo, number: issueNumber, token: token)
        async let issueCommentsTask = github.issueComments(owner: slug.owner, repo: slug.repo, number: issueNumber, token: token)
        async let issueEventsTask = github.issueEvents(owner: slug.owner, repo: slug.repo, number: issueNumber, token: token)
        let issue = (try? await issueTask) ?? fallbackIssue(from: item, owner: slug.owner, repo: slug.repo, number: issueNumber)
        let issueComments = (try? await issueCommentsTask) ?? []
        let issueEvents = (try? await issueEventsTask) ?? []
        let labels = Array(Set((item.labels + (pr.labels ?? []) + issue.labels).map(\.name))).sorted()
        let officialAlgoraEvidence = BountyParsing.officialAlgoraEventEvidence(issueEvents: issueEvents, pullRequestEvents: prIssueEvents)
        let claimEvidenceText = ([prEvidenceText] + labels + officialAlgoraEvidence).joined(separator: "\n")
        let verification = BountyParsing.classifyAlgoraOnly(
            issue: issue,
            comments: issueComments,
            repo: "\(slug.owner)/\(slug.repo)",
            claimEvidenceText: claimEvidenceText,
            officialEventEvidence: officialAlgoraEvidence,
            claimPrsCount: claimIssues.count
        )
        guard verification.verified else { throw BountyTrackerServiceError.noBountyEvidence }

        let allComments = prIssueComments + issueComments
        let bodyCorpus = [issue.body, pr.body, item.body].compactMap { $0 }.joined(separator: "\n")
        let commentCorpus = allComments.map(\.body)
        let textCorpus = ([bodyCorpus] + commentCorpus).joined(separator: "\n")
        let algoraTextCorpus = verification.evidence.joined(separator: "\n")
        let amount = verification.amountUsd ?? 0
        let claimStatus = BountyParsing.paymentStatus(in: algoraTextCorpus) ?? BountyParsing.claimStatus(in: algoraTextCorpus) ?? .unknown
        let prState = resolvePullRequestState(pr)
        let issueState = verification.issueState
        let latestMaintainer = BountyParsing.latestMaintainerComment(from: allComments, excluding: username)
        let latestBot = BountyParsing.latestAlgoraBotComment(from: issueComments)
        let evidence = ["Verified Algora bounty", "Official Algora evidence found", "Algora claim flow found"] + verification.evidence
        let rewardLinks = BountyParsing.rewardLinks(in: algoraTextCorpus)

        async let repositoryTask = github.repository(owner: slug.owner, repo: slug.repo, token: token)
        async let checksTask = github.checkRuns(owner: slug.owner, repo: slug.repo, ref: pr.head.sha, token: token)
        async let statusTask = github.combinedStatus(owner: slug.owner, repo: slug.repo, ref: pr.head.sha, token: token)
        async let codeOfConductTask = firstRepositoryFile(owner: slug.owner, repo: slug.repo, paths: ["CODE_OF_CONDUCT.md", ".github/CODE_OF_CONDUCT.md"], token: token)
        async let contributingTask = firstRepositoryFile(owner: slug.owner, repo: slug.repo, paths: ["CONTRIBUTING.md", ".github/CONTRIBUTING.md"], token: token)
        async let readmeTask = firstRepositoryFile(owner: slug.owner, repo: slug.repo, paths: ["README.md", "readme.md"], token: token)
        let repository = try? await repositoryTask
        let checkRuns = try? await checksTask
        let statuses = try? await statusTask
        let checkState = resolveCheckState(checkRuns: checkRuns, statuses: statuses)
        let competitors = await competitorSnapshots(owner: slug.owner, repo: slug.repo, issueNumber: issueNumber, username: username, ownPR: pr.number, token: token)
        let activeCompetitorCount = competitors.filter { $0.state == .open || $0.state == .draft }.count
        let competitorMerged = competitors.contains { $0.state == .merged }
        let codeOfConduct = await codeOfConductTask
        let contributing = await contributingTask
        let readme = await readmeTask
        let rulesCorpus = [codeOfConduct, contributing, readme, issue.body].compactMap { $0 }.joined(separator: "\n")
        let requiresVideo = BountyParsing.requiresVideo(in: rulesCorpus + "\n" + textCorpus)
        let hasDemoProof = BountyParsing.hasDemoProof(in: prBody + "\n" + prIssueComments.map(\.body).joined(separator: "\n"))
        let assignmentRequired = BountyParsing.assignmentRequired(in: rulesCorpus + "\n" + textCorpus)
        let maintainerAssignmentRequired = BountyParsing.maintainerAssignmentRequired(in: rulesCorpus + "\n" + textCorpus)
        let userAssigned = issue.assignees?.contains { $0.login.caseInsensitiveCompare(username) == .orderedSame } ?? false
        let priorRejected = BountyParsing.priorRejectedSignal(in: textCorpus, username: username)
        let hasVerification = BountyParsing.hasClearVerification(in: prBody)
        let hasTests = BountyParsing.hasTests(in: prBody)
        let rewarded = verification.alreadyRewarded || claimStatus == .paymentSucceeded
        let riskInput = RiskInput(
            pullRequestState: prState,
            issueState: issueState,
            checkState: checkState,
            claimStatus: claimStatus,
            mergeableState: pr.mergeableState ?? (pr.mergeable == false ? "blocked" : "unknown"),
            hasMaintainerComment: latestMaintainer.isEmpty == false,
            competitionCount: activeCompetitorCount,
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
            competitionCount: activeCompetitorCount,
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
            hasAlgoraEvidence: verification.verified,
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

    private func mergeAlgoraData(into result: inout TrackerRefreshResult, githubToken: String?, algoraToken: String?, watchedOrgs: [String]) async {
        let orgs = watchedOrgs.filter { $0.isEmpty == false }
        for org in orgs {
            do {
                let bounties = try await algoraPublic.bounties(org: org, limit: 100)
                for dto in bounties {
                    if let snapshot = await algoraSnapshot(from: dto, source: .algoraPublic, githubToken: githubToken) {
                        result.bounties.append(snapshot)
                    }
                }
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
            for dto in authedBounties {
                if let snapshot = await algoraSnapshot(from: dto, source: .algoraAuthenticated, githubToken: githubToken) {
                    result.bounties.append(snapshot)
                }
            }
            let authedClaims = try await authenticated.claims(limit: 100)
            result.claims.append(contentsOf: authedClaims.compactMap { claimSnapshot(from: $0, org: "authenticated") })
        } catch {
            result.warnings.append("Authenticated Algora API failed: \(error.localizedDescription). Continuing with GitHub and public data.")
        }
    }

    private func algoraSnapshot(from dto: AlgoraBountyDTO, source: BountySource, githubToken: String?) async -> TrackedBountySnapshot? {
        guard let task = dto.task, let owner = task.repoOwner, let repo = task.repoName, let number = task.number else { return nil }
        let repoSlug = "\(owner)/\(repo)"
        let active = dto.status?.lowercased() == "active"
        let issue = (try? await github.issue(owner: owner, repo: repo, number: number, token: githubToken)) ?? GitHubIssueResponse(
            htmlUrl: task.url ?? "https://github.com/\(owner)/\(repo)/issues/\(number)",
            number: number,
            state: active ? "open" : "closed",
            title: task.title ?? "Algora bounty",
            body: task.body,
            labels: [],
            user: GitHubUserSummary(login: "unknown"),
            assignees: [],
            updatedAt: dto.updatedAt ?? dto.createdAt ?? Date(),
            closedAt: nil
        )
        let issueComments = (try? await github.issueComments(owner: owner, repo: repo, number: number, token: githubToken)) ?? []
        let verification = BountyParsing.classifyAlgoraDiscoveryOnly(
            issue: issue,
            comments: issueComments,
            repo: repoSlug,
            claimPrsCount: dto.claims?.count ?? 0
        )
        guard verification.verified else { return nil }

        let algoraText = verification.evidence.joined(separator: "\n")
        let amount = verification.amountUsd ?? dto.reward?.amount ?? 0
        let claimStatuses = dto.claims?.compactMap { $0.status.map(statusFromAlgora) } ?? []
        let claim = claimStatuses.bestClaimStatus()
        let resolvedClaim = claim == .unknown ? (BountyParsing.paymentStatus(in: algoraText) ?? BountyParsing.claimStatus(in: algoraText) ?? .unknown) : claim
        let updated = maxDate(dto.updatedAt ?? dto.createdAt ?? Date(), issue.updatedAt)
        let issueState = verification.issueState
        let rewarded = verification.alreadyRewarded || resolvedClaim == .paymentSucceeded
        let competitionCount = await bountyWorkPullRequestCount(owner: owner, repo: repo, issueNumber: number, token: githubToken)
        let risk = riskScoring.score(RiskInput(
            pullRequestState: .unknown,
            issueState: issueState,
            checkState: .unknown,
            claimStatus: resolvedClaim,
            mergeableState: "unknown",
            hasMaintainerComment: false,
            competitionCount: competitionCount,
            competitorMerged: false,
            issueAlreadyRewarded: rewarded,
            assignmentRequired: BountyParsing.assignmentRequired(in: algoraText),
            userAppearsAssigned: false,
            demoVideoRequired: BountyParsing.requiresVideo(in: algoraText),
            demoProofPresent: false,
            repoArchived: false,
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            contributingRulesFound: false,
            codeOfConductFound: false
        ))
        return TrackedBountySnapshot(
            stableID: "algora:\(owner)/\(repo)#\(number)",
            source: source,
            repoOwner: owner,
            repoName: repo,
            issueNumber: number,
            linkedPullRequestNumber: nil,
            title: issue.title,
            issueBodySummary: (issue.body ?? task.body ?? "").trimmedSummary(limit: 420),
            pullRequestSummary: "",
            amount: amount,
            labels: issue.labels.map(\.name),
            algoraEvidence: ["Verified Algora bounty", "Official Algora evidence found", "Algora claim flow found"] + verification.evidence,
            rewardLinks: [task.url].compactMap { $0 } + BountyParsing.rewardLinks(in: algoraText),
            workflowStatus: issueState == .open ? .watching : .lost,
            issueState: issueState,
            claimStatus: resolvedClaim,
            checkState: .unknown,
            riskLevel: risk.level,
            payoutChance: risk.score,
            riskFactors: risk.factors,
            nextAction: risk.nextAction,
            latestMaintainerComment: "",
            latestBotComment: BountyParsing.latestAlgoraBotComment(from: issueComments),
            competitionCount: competitionCount,
            hasRewardedSignal: rewarded,
            requiresVideo: BountyParsing.requiresVideo(in: algoraText),
            hasDemoProof: false,
            repoArchived: false,
            assignedOnly: BountyParsing.assignmentRequired(in: algoraText),
            userAppearsAssigned: false,
            maintainerAssignmentRequired: BountyParsing.maintainerAssignmentRequired(in: algoraText),
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            createdAt: dto.createdAt ?? updated,
            updatedAt: updated,
            lastRefreshedAt: Date()
        )
    }

    private func openIssueSnapshot(from item: GitHubSearchItem, token: String?) async -> TrackedBountySnapshot? {
        guard let slug = GitHubClient.repositorySlug(from: item.repositoryUrl) else { return nil }
        async let issueTask = github.issue(owner: slug.owner, repo: slug.repo, number: item.number, token: token)
        async let issueCommentsTask = github.issueComments(owner: slug.owner, repo: slug.repo, number: item.number, token: token)
        let issue = (try? await issueTask) ?? fallbackIssue(from: item, owner: slug.owner, repo: slug.repo, number: item.number)
        let issueComments = (try? await issueCommentsTask) ?? []
        let repoSlug = "\(slug.owner)/\(slug.repo)"
        let verification = BountyParsing.classifyAlgoraDiscoveryOnly(
            issue: issue,
            comments: issueComments,
            repo: repoSlug
        )
        guard verification.verified else { return nil }

        let labels = Array(Set((item.labels + issue.labels).map(\.name))).sorted()
        let algoraText = verification.evidence.joined(separator: "\n")
        let amount = verification.amountUsd ?? 0
        let claim = BountyParsing.paymentStatus(in: algoraText) ?? BountyParsing.claimStatus(in: algoraText) ?? .unknown
        let rewarded = verification.alreadyRewarded || claim == .paymentSucceeded
        let competitionCount = await bountyWorkPullRequestCount(owner: slug.owner, repo: slug.repo, issueNumber: item.number, token: token)
        let risk = riskScoring.score(RiskInput(
            pullRequestState: .unknown,
            issueState: verification.issueState,
            checkState: .unknown,
            claimStatus: claim,
            mergeableState: "unknown",
            hasMaintainerComment: false,
            competitionCount: competitionCount,
            competitorMerged: false,
            issueAlreadyRewarded: rewarded,
            assignmentRequired: BountyParsing.assignmentRequired(in: algoraText),
            userAppearsAssigned: false,
            demoVideoRequired: BountyParsing.requiresVideo(in: algoraText),
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
            title: issue.title,
            issueBodySummary: (issue.body ?? item.body ?? "").trimmedSummary(limit: 420),
            pullRequestSummary: "",
            amount: amount,
            labels: labels,
            algoraEvidence: ["Verified Algora bounty", "Official Algora evidence found", "Algora claim flow found"] + verification.evidence,
            rewardLinks: BountyParsing.rewardLinks(in: algoraText),
            workflowStatus: verification.issueState == .open ? .watching : .lost,
            issueState: verification.issueState,
            claimStatus: claim,
            checkState: .unknown,
            riskLevel: risk.level,
            payoutChance: risk.score,
            riskFactors: risk.factors,
            nextAction: risk.nextAction,
            latestMaintainerComment: "",
            latestBotComment: BountyParsing.latestAlgoraBotComment(from: issueComments),
            competitionCount: competitionCount,
            hasRewardedSignal: rewarded,
            requiresVideo: BountyParsing.requiresVideo(in: algoraText),
            hasDemoProof: false,
            repoArchived: false,
            assignedOnly: BountyParsing.assignmentRequired(in: algoraText),
            userAppearsAssigned: false,
            maintainerAssignmentRequired: BountyParsing.maintainerAssignmentRequired(in: algoraText),
            priorRejectedSignal: false,
            hasClearVerification: false,
            hasTests: false,
            createdAt: item.createdAt,
            updatedAt: maxDate(issue.updatedAt, item.updatedAt),
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

    private func bountyWorkPullRequestCount(owner: String, repo: String, issueNumber: Int, excludingPullRequest: Int? = nil, token: String?) async -> Int {
        let items = (try? await github.searchBountyWorkPullRequests(owner: owner, repo: repo, issueNumber: issueNumber, token: token)) ?? []
        return items.filter { item in
            item.state.lowercased() == "open" && item.number != excludingPullRequest
        }.count
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

    private func dedupeSearchItems(_ values: [GitHubSearchItem]) -> [GitHubSearchItem] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.htmlUrl).inserted }
    }
}

struct TrackerRefreshResult {
    var user: GitHubUser?
    var scannedPullRequestCount = 0
    var claimPullRequestCount = 0
    var activeClaimPullRequestCount = 0
    var linkedIssueCheckCount = 0
    var skippedPullRequestCount = 0
    var failedPullRequestCount = 0
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

enum BountyTrackerServiceError: LocalizedError, Equatable {
    case noBountyEvidence

    var errorDescription: String? {
        switch self {
        case .noBountyEvidence: return "Not Algora: no official Algora amount evidence and claim flow was found for the linked issue."
        }
    }
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
        if recentlyUpdated, let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()), snapshot.updatedAt < cutoff { return false }
        if minimumPayout > 0 && (snapshot.amount == 0 || snapshot.amount < minimumPayout) { return false }
        if maximumPayout > 0 && snapshot.amount > maximumPayout { return false }
        if lowCompetition && snapshot.competitionCount > 5 { return false }
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
