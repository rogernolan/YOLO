# Codex Alert

Small Swift-based attention system with:

- `codex-alert`: a macOS command line tool that creates an alert payload
- `CodexAlert`: an iOS SwiftUI app that shows alerts and can refresh them from CloudKit

## What works now

- Shared alert model and persistence live in `AttentionKit`
- The CLI saves alerts locally and can upload them to CloudKit when `CODEX_ALERT_CONTAINER` is set
- The iOS app loads cached alerts, refreshes from CloudKit, and schedules a local notification for newly synced alerts

## Quick start

Build and run tests:

```bash
swift test
```

Send a local alert:

```bash
swift run codex-alert send \
  --title "Need input" \
  --body "Please review the current blocker." \
  --sender Codex \
  --urgency high
```

Build the iOS app for Simulator:

```bash
xcodebuild -project CodexAlert.xcodeproj \
  -scheme CodexAlert \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Build the signed macOS helper app:

```bash
xcodebuild -project CodexAlert.xcodeproj \
  -scheme CodexAlertCLI \
  -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates build
```

Run the helper's bundled executable:

```bash
~/Library/Developer/Xcode/DerivedData/CodexAlert-*/Build/Products/Debug/CodexAlertCLI.app/Contents/MacOS/CodexAlertCLI \
  send \
  --title "Need input" \
  --body "Please review the current blocker." \
  --sender Codex \
  --urgency high
```

## CloudKit setup for a real iPhone

1. Open [`CodexAlert.xcodeproj`](/Users/rog/Development/Codex%20alert/CodexAlert.xcodeproj) in Xcode.
2. Change the bundle identifier and select your Apple Developer team.
3. The target is configured for bundle ID `net.hatbat.CodexAlert` and CloudKit container `iCloud.net.hatbat.CodexAlert`.
4. Export the same container value if you want to override the built-in helper default:

```bash
export CODEX_ALERT_CONTAINER="iCloud.net.hatbat.CodexAlert"
```

Once both ends use the same CloudKit container, alerts sent from the CLI can be pulled into the app.
