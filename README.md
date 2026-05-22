# BountyDesk

BountyDesk is an iOS 26 SwiftUI app for tracking Algora-backed GitHub bounties from a sideloaded iPhone or iPad.

## What It Does

- Tracks Algora/GitHub bounty candidates, claims, submitted PRs, review state, merged work, paid work, blocked work, and skipped work.
- Stores bounty records locally with no login or backend required.
- Creates records from GitHub issue or pull request URLs.
- Generates matching Algora issue links from GitHub issue metadata.
- Tracks payout, priority, competition count, CI/check notes, PR URL, labels, and maintainer/status notes.
- Ships with sample bounty records based on active bounty tracking notes.
- Uses an iOS 26 SwiftUI interface with Liquid Glass panels where it helps scanning.

## SideStore Notes

The GitHub Actions workflow builds an unsigned IPA for SideStore/AltStore-style signing. The app bundle includes explicit `CFBundleExecutable` metadata, a compiled app icon catalog, and a workflow guard that verifies the executable exists before upload.

## Build Locally On macOS

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project BountyDesk.xcodeproj -scheme BountyDesk -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO archive -archivePath build/BountyDesk.xcarchive
mkdir -p build/Payload
cp -R build/BountyDesk.xcarchive/Products/Applications/BountyDesk.app build/Payload/
(cd build && zip -qry BountyDesk-unsigned.ipa Payload)
```

## GitHub Actions

Push this repo to GitHub and run `Build unsigned iOS IPA`. The artifact is named `BountyDesk-unsigned-ipa`.
