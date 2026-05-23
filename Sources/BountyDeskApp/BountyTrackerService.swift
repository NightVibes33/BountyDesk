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
        let scopedSearch = filters.org.nilIfBlank != nil || filters.repo.nilIfBlank != nil || filters.language.nilIfBlank != nil
        let candidateLimit = scopedSearch ? 60 : 35
        let perPage = candidateLimit

        do {
            let items = try await github.searchOpenBountyIssues(token: githubToken, org: filters.org.nilIfBlank, repo: filters.repo.nilIfBlank, language: filters.language.nilIfBlank, perPage: perPage)
            let candidates = Array(items.prefix(candidateLimit))
            result.githubCandidateCount = items.count
            result.scannedCandidateCount += candidates.count
            if items.count > candidateLimit {
                result.limitedCandidateCount += items.count - candidateLimit
                result.warnings.append("Search limited to the newest \(candidateLimit) GitHub candidates. Add an org or repo filter for a deeper search.")
            }
            let snapshots = await openIssueSnapshots(from: candidates, token: githubToken)
            for snapshot in snapshots where filters.matches(snapshot: snapshot, commentCount: 0) {
                result.bounties.append(snapshot)
            }
        } catch {
            result.warnings.append("GitHub discovery failed: \(error.localizedDescription)")
        }

        if let org = filters.org.nilIfBlank {
            do {
                let algoraBounties = try await algoraPublic.bounties(org: org, limit: 100)
                let algoraLimit = 60
                let candidates = Array(algoraBounties.prefix(algoraLimit))
                result.algoraCandidateCount = algoraBounties.count
                result.scannedCandidateCount += candidates.count
                if algoraBounties.count > algoraLimit {
                    result.limitedCandidateCount += algoraBounties.count - algoraLimit
                    result.warnings.append("Algora public discovery limited to the newest \(algoraLimit) bounties for \(org).")
                }
                let snapshots = await algoraSnapshots(from: candidates, source: .algoraPublic, githubToken: githubToken)
                for snapshot in snapshots where filters.matches(snapshot: snapshot, commentCount: 0) {
                    result.bounties.append(snapshot)
                }
            } catch {
                result.warnings.append("Public Algora discovery failed for \(org): \(error.localizedDescription)")
            }
        }

        result.bounties = dedupe(result.bounties, by: \.stableID).sorted { $0.updatedAt > $1.updatedAt }
        return result
    }

    private func openIssueSnapshots(from items: [GitHubSearchItem], token: String?) async -> [TrackedBountySnapshot] {
        var snapshots: [TrackedBountySnapshot] = []
        var index = 0
        while index < items.count {
            let end = Swift.min(index + 6, items.count)
            let batch = Array(items[index..<end])
            await withTaskGroup(of: TrackedBountySnapshot?.self) { group in
                for item in batch {
                    group.addTask {
                        await openIssueSnapshot(from: item, token: token)
                    }
                }
                for await snapshot in group {
                    if let snapshot {
                        snapshots.append(snapshot)
                    }
                }
            }
            index = end
        }
        return snapshots
    }

    private func algoraSnapshots(from dtos: [AlgoraBountyDTO], source: BountySource, githubToken: String?) async -> [TrackedBountySnapshot] {
        var snapshots: [TrackedBountySnapshot] = []
        var index = 0
        while index < dtos.count {
            let end = Swift.min(index + 6, dtos.count)
            let batch = Array(dtos[index..<end])
            await withTaskGroup(of: TrackedBountySnapshot?.self) { group in
                for dto in batch {
                    group.addTask {
                        await algoraSnapshot(from: dto, source: source, githubToken: githubToken)
                    }
                }
                for await snapshot in group {
                    if let snapshot {
                        snapshots.append(snapshot)
                    }
                }
            }
            index = end
        }
        return snapshots
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
        let stableID = "github:\(slug.owner)/\(slug.repo)#\(issueNumber):pr\(pr.number)"
        let competition = await competitionReport(owner: slug.owner, repo: slug.repo, issueNumber: issueNumber, token: token, ourPullRequestNumber: pr.number, cachedIssue: issue, cachedIssueComments: issueComments)
        let competitors = competitorSnapshots(from: competition, bountyStableID: stableID, owner: slug.owner, repo: slug.repo)
        let activeCompetitorCount = competition.seriousOpenCompetitors
        let competitorMerged = competition.mergedClaimPrs > 0
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
        let rewarded = verification.alreadyRewarded || claimStatus == .paymentSucceeded || competition.rewardedClaims > 0
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
            riskFactors: risk.factors + competition.reasons,
            nextAction: nextAction(from: competition.recommendation, fallback: risk.nextAction),
            latestMaintainerComment: latestMaintainer,
            latestBotComment: latestBot,
            competitionCount: competition.openClaimPrs,
            competitionLevel: competition.competitionLevel,
            recommendation: competition.recommendation,
            totalAttemptsFromAlgoraTable: competition.totalAttemptsFromAlgoraTable,
            openClaimPrs: competition.openClaimPrs,
            closedClaimPrs: competition.closedClaimPrs,
            mergedClaimPrs: competition.mergedClaimPrs,
            rewardedClaims: competition.rewardedClaims,
            seriousOpenCompetitors: competition.seriousOpenCompetitors,
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
        let riskSnapshot = RiskSnapshotData(stableID: UUID().uuidString, bountyStableID: stableID, score: risk.score, level: risk.level, factors: risk.factors + competition.reasons, nextAction: nextAction(from: competition.recommendation, fallback: risk.nextAction), createdAt: Date())
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
        let competition = await competitionReport(owner: owner, repo: repo, issueNumber: number, token: githubToken, cachedIssue: issue, cachedIssueComments: issueComments)
        let rewarded = verification.alreadyRewarded || resolvedClaim == .paymentSucceeded || competition.rewardedClaims > 0
        let risk = riskScoring.score(RiskInput(
            pullRequestState: .unknown,
            issueState: issueState,
            checkState: .unknown,
            claimStatus: resolvedClaim,
            mergeableState: "unknown",
            hasMaintainerComment: false,
            competitionCount: competition.seriousOpenCompetitors,
            competitorMerged: competition.mergedClaimPrs > 0,
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
            riskFactors: risk.factors + competition.reasons,
            nextAction: nextAction(from: competition.recommendation, fallback: risk.nextAction),
            latestMaintainerComment: "",
            latestBotComment: BountyParsing.latestAlgoraBotComment(from: issueComments),
            competitionCount: competition.openClaimPrs,
            competitionLevel: competition.competitionLevel,
            recommendation: competition.recommendation,
            totalAttemptsFromAlgoraTable: competition.totalAttemptsFromAlgoraTable,
            openClaimPrs: competition.openClaimPrs,
            closedClaimPrs: competition.closedClaimPrs,
            mergedClaimPrs: competition.mergedClaimPrs,
            rewardedClaims: competition.rewardedClaims,
            seriousOpenCompetitors: competition.seriousOpenCompetitors,
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
        let competition = await competitionReport(owner: slug.owner, repo: slug.repo, issueNumber: item.number, token: token, cachedIssue: issue, cachedIssueComments: issueComments)
        let rewarded = verification.alreadyRewarded || claim == .paymentSucceeded || competition.rewardedClaims > 0
        let risk = riskScoring.score(RiskInput(
            pullRequestState: .unknown,
            issueState: verification.issueState,
            checkState: .unknown,
            claimStatus: claim,
            mergeableState: "unknown",
            hasMaintainerComment: false,
            competitionCount: competition.seriousOpenCompetitors,
            competitorMerged: competition.mergedClaimPrs > 0,
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
            riskFactors: risk.factors + competition.reasons,
            nextAction: nextAction(from: competition.recommendation, fallback: risk.nextAction),
            latestMaintainerComment: "",
            latestBotComment: BountyParsing.latestAlgoraBotComment(from: issueComments),
            competitionCount: competition.openClaimPrs,
            competitionLevel: competition.competitionLevel,
            recommendation: competition.recommendation,
            totalAttemptsFromAlgoraTable: competition.totalAttemptsFromAlgoraTable,
            openClaimPrs: competition.openClaimPrs,
            closedClaimPrs: competition.closedClaimPrs,
            mergedClaimPrs: competition.mergedClaimPrs,
            rewardedClaims: competition.rewardedClaims,
            seriousOpenCompetitors: competition.seriousOpenCompetitors,
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

    private func competitionReport(
        owner: String,
        repo: String,
        issueNumber: Int,
        token: String?,
        ourPullRequestNumber: Int? = nil,
        cachedIssue: GitHubIssueResponse? = nil,
        cachedIssueComments: [GitHubComment]? = nil
    ) async -> BountyCompetitionReport {
        let repoSlug = "\(owner)/\(repo)"
        let now = Date()
        let issue = cachedIssue ?? ((try? await github.issue(owner: owner, repo: repo, number: issueNumber, token: token)) ?? GitHubIssueResponse(
            htmlUrl: "https://github.com/\(owner)/\(repo)/issues/\(issueNumber)",
            number: issueNumber,
            state: "open",
            title: "Bounty candidate",
            body: nil,
            labels: [],
            user: GitHubUserSummary(login: "unknown"),
            assignees: [],
            updatedAt: now,
            closedAt: nil
        ))
        let issueComments = cachedIssueComments ?? ((try? await github.issueComments(owner: owner, repo: repo, number: issueNumber, token: token)) ?? [])
        let verification = BountyParsing.classifyAlgoraDiscoveryOnly(issue: issue, comments: issueComments, repo: repoSlug, lastCheckedAt: now)
        guard verification.verified else {
            return .notAlgora(issue: issue, repo: repoSlug, reason: verification.excludedReason ?? "No algora-pbc[bot] comment found", verification: verification, lastCheckedAt: now)
        }

        let attemptRows = BountyParsing.parseAlgoraAttemptTables(from: issueComments, issueNumber: issueNumber)
        let searchItems = (try? await github.searchBountyWorkPullRequests(owner: owner, repo: repo, issueNumber: issueNumber, token: token, perPage: 100)) ?? []
        let attemptNumbers = attemptRows.compactMap(\.prNumber)
        let searchedNumbers = searchItems.map(\.number)
        let prNumbers = orderedUniqueNumbers(searchedNumbers + attemptNumbers + [ourPullRequestNumber].compactMap { $0 })
        var searchItemsByNumber: [Int: GitHubSearchItem] = [:]
        for item in searchItems {
            searchItemsByNumber[item.number] = item
        }
        let prSummaries = await competitorDetails(
            owner: owner,
            repo: repo,
            issueNumber: issueNumber,
            prNumbers: Array(prNumbers.prefix(60)),
            searchItemsByNumber: searchItemsByNumber,
            attemptRows: attemptRows,
            token: token
        )

        let prNumberSet = Set(prSummaries.compactMap(\.prNumber))
        let attemptOnlyRows = attemptRows.filter { row in
            guard let prNumber = row.prNumber else { return true }
            return prNumberSet.contains(prNumber) == false
        }.map { row in
            var enriched = row
            if let prNumber = row.prNumber {
                enriched.prUrl = "https://github.com/\(owner)/\(repo)/pull/\(prNumber)"
            }
            return enriched
        }
        let competitors = (prSummaries + attemptOnlyRows).sorted { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        let ourSummary = ourPullRequestNumber.flatMap { number in competitors.first { $0.prNumber == number } }
        let competitorOnly = competitors.filter { summary in
            guard let ourPullRequestNumber else { return true }
            return summary.prNumber != ourPullRequestNumber
        }
        let claimPrs = competitors.filter { $0.prNumber != nil && $0.claimSeen }
        let openClaimPrs = claimPrs.filter { $0.state == .openPr }.count
        let closedClaimPrs = claimPrs.filter { $0.state == .closedPr }.count
        let mergedClaimPrs = claimPrs.filter { $0.state == .mergedPr }.count
        let rewardedClaims = competitors.filter { $0.rewardSeen }.count
        let seriousOpenCompetitors = competitorOnly.filter { $0.serious }.count
        let level = competitionLevel(openClaimPrs: openClaimPrs, rewardedClaims: rewardedClaims)
        let decision = recommendationAndReasons(
            verified: verification.verified,
            issueState: verification.issueState,
            amount: verification.amountUsd ?? 0,
            openClaimPrs: openClaimPrs,
            rewardedClaims: rewardedClaims,
            seriousOpenCompetitors: seriousOpenCompetitors,
            requiresVideo: BountyParsing.requiresVideo(in: verification.evidence.joined(separator: "\n") + "\n" + (issue.body ?? "")),
            hasRunnableTests: false,
            hasMaintainerRejection: competitorOnly.contains { BountyParsing.maintainerRejectionSeen(in: $0.evidence.joined(separator: "\n")) },
            ourSummary: ourSummary
        )

        return BountyCompetitionReport(
            repo: repoSlug,
            issueNumber: issueNumber,
            issueUrl: issue.htmlUrl,
            issueTitle: issue.title,
            issueState: verification.issueState,
            source: .algora,
            algoraVerified: true,
            algoraBotSeen: verification.algoraBotSeen,
            bountyAmountUsd: verification.amountUsd,
            claimFlowSeen: verification.claimFlowSeen,
            rewardActionSeen: verification.rewardActionSeen,
            ourPrNumber: ourSummary?.prNumber ?? ourPullRequestNumber,
            ourPrUrl: ourSummary?.prUrl,
            ourPrState: ourSummary?.state.pullRequestState,
            ourPrMerged: ourSummary?.merged ?? false,
            ourPrMergeable: ourSummary?.mergeable,
            ourPrMergeableState: ourSummary?.mergeableState,
            ourCheckSummary: ourSummary?.checksSummary ?? "none",
            ourPaidSignal: ourSummary?.rewardSeen ?? false,
            totalAttemptsFromAlgoraTable: attemptRows.count,
            openClaimPrs: openClaimPrs,
            closedClaimPrs: closedClaimPrs,
            mergedClaimPrs: mergedClaimPrs,
            rewardedClaims: rewardedClaims,
            seriousOpenCompetitors: seriousOpenCompetitors,
            competitionLevel: level,
            competitors: competitorOnly,
            recommendation: decision.recommendation,
            reasons: decision.reasons,
            lastCheckedAt: now
        )
    }

    private func competitorDetail(owner: String, repo: String, issueNumber: Int, prNumber: Int, searchItem: GitHubSearchItem?, attemptRows: [CompetitorSummary], token: String?) async -> CompetitorSummary? {
        guard let pr = try? await github.pullRequest(owner: owner, repo: repo, number: prNumber, token: token) else { return nil }
        async let prIssueTask = try? github.issue(owner: owner, repo: repo, number: prNumber, token: token)
        async let commentsTask = try? github.pullRequestComments(owner: owner, repo: repo, number: prNumber, token: token)
        async let reviewCommentsTask = try? github.pullRequestReviewComments(owner: owner, repo: repo, number: prNumber, token: token)
        async let checkRunsTask = try? github.checkRuns(owner: owner, repo: repo, ref: pr.head.sha, token: token)
        async let statusTask = try? github.combinedStatus(owner: owner, repo: repo, ref: pr.head.sha, token: token)
        let prIssue = await prIssueTask
        let comments = (await commentsTask) ?? []
        let reviewComments = (await reviewCommentsTask) ?? []
        let checkRuns = await checkRunsTask
        let statuses = await statusTask
        let checkState = resolveCheckState(checkRuns: checkRuns, statuses: statuses)
        let checksSummary = summarizeChecks(checkRuns: checkRuns, statuses: statuses)
        let labels = (pr.labels ?? []) + (prIssue?.labels ?? []) + (searchItem?.labels ?? [])
        let body = pr.body ?? searchItem?.body ?? ""
        let commentsText = (comments + reviewComments).map(\.body).joined(separator: "\n")
        let labelsText = labels.map(\.name).joined(separator: "\n")
        let evidenceText = [body, commentsText, labelsText].joined(separator: "\n")
        let tableRows = attemptRows.filter { $0.prNumber == prNumber }
        let tableRewardSeen = tableRows.contains { $0.rewardSeen }
        let rewardSeen = tableRewardSeen || BountyParsing.rewardSignalSeen(in: commentsText + "\n" + labelsText)
        let claimSeen = BountyParsing.claimSeen(in: evidenceText, issueNumber: issueNumber) || tableRows.contains { $0.claimSeen }
        let prState = resolvePullRequestState(pr)
        let competitorState: CompetitorState
        if prState == .merged {
            competitorState = .mergedPr
        } else if prState == .closed {
            competitorState = .closedPr
        } else if prState == .open || prState == .draft {
            competitorState = .openPr
        } else {
            competitorState = .unknown
        }
        let rejectionSeen = BountyParsing.maintainerRejectionSeen(in: commentsText)
        let looksRelevant = claimSeen || BountyParsing.linkedIssueNumbers(in: body).contains(issueNumber) || (pr.changedFiles ?? 0) > 0
        let serious = claimSeen
            && competitorState == .openPr
            && pr.draft != true
            && (checkState == .passing || checkState == .noneConfigured)
            && looksRelevant
            && rejectionSeen == false
        let evidence = ([body.trimmedSummary(limit: 220)] + tableRows.flatMap(\.evidence) + comments.map { $0.body.trimmedSummary(limit: 160) } + reviewComments.map { $0.body.trimmedSummary(limit: 160) })
            .filter { $0.isEmpty == false }
        return CompetitorSummary(
            prNumber: prNumber,
            prUrl: pr.htmlUrl,
            author: pr.user.login,
            title: pr.title,
            state: competitorState,
            merged: prState == .merged,
            rewardSeen: rewardSeen,
            checksSummary: checksSummary,
            claimSeen: claimSeen,
            updatedAt: pr.updatedAt,
            evidence: evidence,
            isDraft: pr.draft ?? false,
            serious: serious,
            mergeable: pr.mergeable,
            mergeableState: pr.mergeableState
        )
    }

    private func competitorDetails(
        owner: String,
        repo: String,
        issueNumber: Int,
        prNumbers: [Int],
        searchItemsByNumber: [Int: GitHubSearchItem],
        attemptRows: [CompetitorSummary],
        token: String?
    ) async -> [CompetitorSummary] {
        var details: [CompetitorSummary] = []
        var index = 0
        while index < prNumbers.count {
            let end = Swift.min(index + 8, prNumbers.count)
            let batch = Array(prNumbers[index..<end])
            await withTaskGroup(of: CompetitorSummary?.self) { group in
                for number in batch {
                    group.addTask {
                        await competitorDetail(
                            owner: owner,
                            repo: repo,
                            issueNumber: issueNumber,
                            prNumber: number,
                            searchItem: searchItemsByNumber[number],
                            attemptRows: attemptRows,
                            token: token
                        )
                    }
                }
                for await detail in group {
                    if let detail {
                        details.append(detail)
                    }
                }
            }
            index = end
        }
        return details.sorted { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
    }

    private func competitorSnapshots(from report: BountyCompetitionReport, bountyStableID: String, owner: String, repo: String) -> [CompetitorPRSnapshot] {
        report.competitors.compactMap { competitor in
            guard let number = competitor.prNumber, let url = competitor.prUrl else { return nil }
            let pullState = competitor.state.pullRequestState
            return CompetitorPRSnapshot(
                stableID: "github:\(owner)/\(repo):competitor-pr\(number)",
                bountyStableID: bountyStableID,
                number: number,
                authorLogin: competitor.author,
                title: competitor.title ?? "Competing solution",
                htmlURLString: url,
                state: pullState,
                competitorState: competitor.state,
                checkState: checkState(from: competitor.checksSummary),
                checksSummary: competitor.checksSummary ?? "none",
                claimSeen: competitor.claimSeen,
                rewardSeen: competitor.rewardSeen,
                serious: competitor.serious,
                changedFiles: 0,
                additions: 0,
                deletions: 0,
                labels: competitor.rewardSeen ? ["Reward seen"] : [],
                latestComment: competitor.evidence.first ?? "",
                evidence: competitor.evidence,
                hasDemoProof: BountyParsing.hasDemoProof(in: competitor.evidence.joined(separator: "\n")),
                hasMaintainerApproval: competitor.rewardSeen,
                updatedAt: competitor.updatedAt ?? Date()
            )
        }
    }

    private func competitionLevel(openClaimPrs: Int, rewardedClaims: Int) -> CompetitionLevel {
        if openClaimPrs >= 20 || rewardedClaims >= 5 { return .extreme }
        if openClaimPrs >= 10 { return .high }
        if openClaimPrs >= 4 { return .medium }
        if openClaimPrs >= 1 { return .low }
        return rewardedClaims == 0 ? .none : .low
    }

    private func recommendationAndReasons(
        verified: Bool,
        issueState: IssueState,
        amount: Int,
        openClaimPrs: Int,
        rewardedClaims: Int,
        seriousOpenCompetitors: Int,
        requiresVideo: Bool,
        hasRunnableTests: Bool,
        hasMaintainerRejection: Bool,
        ourSummary: CompetitorSummary?
    ) -> (recommendation: BountyRecommendation, reasons: [String]) {
        guard verified else { return (.notAlgora, ["No algora-pbc[bot] proof found"]) }
        var score = 0
        var reasons: [String] = ["Verified Algora bounty"]
        score += 40
        if issueState == .open { score += 20; reasons.append("Issue is open") }
        if openClaimPrs == 0 { score += 20; reasons.append("No open claim PRs") }
        else if openClaimPrs <= 3 { score += 10; reasons.append("Low open claim PR count") }
        if amount >= 50 { score += 10; reasons.append("Payout is at least $50") }
        if hasRunnableTests { score += 10; reasons.append("Runnable tests or validation commands found") }
        if openClaimPrs >= 10 { score -= 20; reasons.append("High open claim PR count") }
        if openClaimPrs >= 20 { score -= 40; reasons.append("Extreme open claim PR count") }
        if rewardedClaims > 0 { score -= 40; reasons.append("Reward or paid signals were seen") }
        if amount > 0 && amount < 10 { score -= 20; reasons.append("Low payout") }
        if requiresVideo { score -= 30; reasons.append("Demo or video proof may be required") }
        if hasMaintainerRejection { score -= 50; reasons.append("Similar PR rejection signal found") }
        if seriousOpenCompetitors > 0 { reasons.append("\(seriousOpenCompetitors) serious open competing solution(s)") }
        if let ourSummary {
            if ourSummary.state == .closedPr { score -= 40; reasons.append("Our PR is closed") }
            if ourSummary.isDraft { score -= 20; reasons.append("Our PR is still draft") }
            if ourSummary.mergeable == false || ourSummary.mergeableState == "dirty" || ourSummary.mergeableState == "blocked" { score -= 25; reasons.append("Our PR is not mergeable") }
            if ourSummary.checksSummary?.contains("failure") == true { score -= 30; reasons.append("Our checks are failing") }
            if ourSummary.serious { score += 10; reasons.append("Our PR has a serious claim shape") }
        }
        let recommendation: BountyRecommendation
        if rewardedClaims >= 5 || openClaimPrs >= 20 {
            recommendation = .alreadyRewardedOrSaturated
        } else if score >= 80 {
            recommendation = .goodTarget
        } else if score >= 50 {
            recommendation = .possibleButContested
        } else if score >= 20 {
            recommendation = .lowPriority
        } else {
            recommendation = .notWorthIt
        }
        return (recommendation, reasons)
    }

    private func summarizeChecks(checkRuns: GitHubCheckRunsResponse?, statuses: GitHubCombinedStatusResponse?) -> String {
        var counts: [String: Int] = [:]
        for run in checkRuns?.checkRuns ?? [] {
            let key = normalizeCheckState(run.conclusion ?? run.status)
            counts[key, default: 0] += 1
        }
        for status in statuses?.statuses ?? [] {
            let key = normalizeCheckState(status.state)
            counts[key, default: 0] += 1
        }
        guard counts.isEmpty == false else { return "none" }
        let order = ["failure", "error", "cancelled", "timed_out", "action_required", "pending", "in_progress", "success", "neutral", "skipped"]
        return counts.keys.sorted { lhs, rhs in
            (order.firstIndex(of: lhs) ?? order.count) < (order.firstIndex(of: rhs) ?? order.count)
        }.map { key in "\(key):\(counts[key] ?? 0)" }.joined(separator: " ")
    }

    private func normalizeCheckState(_ raw: String) -> String {
        let lower = raw.lowercased()
        if ["success", "neutral", "skipped", "failure", "error", "cancelled", "timed_out", "action_required", "pending", "in_progress"].contains(lower) {
            return lower
        }
        return lower.isEmpty ? "unknown" : lower
    }

    private func checkState(from summary: String?) -> CheckState {
        guard let summary, summary != "none" else { return .noneConfigured }
        if summary.contains("failure") || summary.contains("error") || summary.contains("cancelled") || summary.contains("timed_out") || summary.contains("action_required") { return .failing }
        if summary.contains("pending") || summary.contains("in_progress") { return .pending }
        if summary.contains("success") { return .passing }
        return .unknown
    }

    private func nextAction(from recommendation: BountyRecommendation, fallback: String) -> String {
        switch recommendation {
        case .goodTarget: return fallback
        case .possibleButContested: return "Proceed only if our PR is clearly stronger than competing claim PRs."
        case .lowPriority: return "Treat as low priority until competition or payout improves."
        case .notWorthIt: return "Do not pursue unless the bounty changes materially."
        case .alreadyRewardedOrSaturated: return "Do not pursue: reward signals or saturation are already visible."
        case .notAlgora: return "Do not track: no verified Algora payout flow."
        }
    }

    private func orderedUniqueNumbers(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
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
    var scannedCandidateCount = 0
    var githubCandidateCount = 0
    var algoraCandidateCount = 0
    var limitedCandidateCount = 0
    var warnings: [String] = []
}

enum BountyTrackerServiceError: LocalizedError, Equatable {
    case noBountyEvidence

    var errorDescription: String? {
        switch self {
        case .noBountyEvidence: return "Not Algora: no Algora issue comment with amount and claim flow was found for the linked issue."
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
