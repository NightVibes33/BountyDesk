# BountyDesk

BountyDesk is an iOS 26 SwiftUI developer dashboard for tracking Algora-backed GitHub bounties from a sideloaded iPhone or iPad.

This build is no longer a seeded/sample tracker. It starts from real user data: a GitHub token, GitHub public search, optional public Algora org endpoints, optional Algora Bearer-token endpoints, and manual URL imports that are refreshed from GitHub when possible.

## Features

- GitHub passkey-capable Device Flow sign-in plus GitHub token sign-in with `/user` validation.
- Keychain token storage; tokens are never stored in SwiftData, exported, or logged.
- Optional Algora API token mode that never blocks GitHub-only tracking.
- SwiftData persistence for accounts, watched orgs, bounties, claims, PRs, issues, repo rules, competitor PRs, alerts, and risk snapshots.
- GitHub API client for user profile, claim PR search, PRs, linked issues, comments, labels, checks, commit statuses, repository metadata, and repo docs.
- Public Algora client for `https://console.algora.io/api/orgs/{org}/bounties?limit=100` and claims where available.
- Authenticated Algora client for `/api/bounties`, `/api/claims`, `/api/orgs/{org}/bounties`, and `/api/orgs/{org}/claims` when a token exists.
- Current bounty tracker with payout, evidence, PR status, issue status, claim status, checks, competition, maintainer/bot comments, risk score, and next action.
- Competition view with ethical improvement suggestions only.
- Discover tab with org, repo, language, payout, competition, active/paid/video/assignment filters.
- Alerts tab for refresh-detected status, check, maintainer, bot, claim, and payout changes.
- Settings for token management, watched orgs, refresh interval, notification preferences, exports, and cache clearing.
- Debug/test mock fixtures are kept out of production startup data.

## Token Setup

Use **Continue with GitHub Passkey** to start GitHub OAuth Device Flow. BountyDesk opens `https://github.com/login/device`, where iOS can offer the GitHub passkey saved in Passwords. After authorization, BountyDesk stores the returned GitHub OAuth token in Keychain.

The app embeds only the public GitHub OAuth client ID. It does not embed or use a GitHub OAuth client secret. Device Flow must be enabled on the OAuth app in GitHub settings.

You can still paste a GitHub personal access token. Use public repo read access for public bounty tracking. Add private repo read access only if you want BountyDesk to track private repositories.

Most users do not need an Algora API token. If an Algora token is missing or an Algora endpoint fails, BountyDesk continues with GitHub and public data.

## Build Locally On macOS

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project BountyDesk.xcodeproj -scheme BountyDesk -destination 'platform=iOS Simulator,name=iPhone 17' test
xcodebuild -project BountyDesk.xcodeproj -scheme BountyDesk -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" archive -archivePath build/BountyDesk.xcarchive
mkdir -p build/Payload
cp -R build/BountyDesk.xcarchive/Products/Applications/BountyDesk.app build/Payload/
(cd build && zip -qry BountyDesk-unsigned.ipa Payload)
```

## GitHub Actions

The workflow generates the Xcode project with XcodeGen, runs unit tests, archives an unsigned device build with signing disabled, validates the bundle, packages `Payload/BountyDesk.app`, and uploads `BountyDesk-unsigned-ipa`.

## Tests

The test target covers:

- GitHub token validation request behavior.
- GitHub OAuth Device Flow requests and token polling without a client secret.
- PR search parsing and deduping.
- `/claim` and `@algora-pbc /claim` detection.
- Linked issue extraction.
- Algora evidence and bot/status parsing.
- Bounty amount parsing, including `$4k` and USD strings.
- Claim/payment status parsing.
- Risk scoring.
- Missing Algora token fallback.
- Public Algora endpoint failure fallback during discovery.
