# Testing

## Setup

Open `Peel.xcodeproj`, select the shared Peel scheme and an installed simulator, then use Product → Test (⌘U). Both `PeelTests` and `PeelUITests` are included; the scheme disables parallelization for both targets. Run iPad and iPhone destinations sequentially.

Recorded toolchain: Xcode 27.2 (27B52), Swift 5 language mode, iOS 27.2 simulators. The deployment target of iOS/iPadOS 17 does not itself establish execution on that OS or compatibility with an older Xcode toolchain.

```sh
# Optional focused launch/navigation check before a complete run.
xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' \
  -only-testing:PeelUITests/PeelUITests/testNavigationAndCaptureBaseline test

# Finish each destination before starting another.
xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M4)' test

xcodebuild -project Peel.xcodeproj -scheme Peel -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Recorded results

On **23 November 2026**, focused iPad navigation passed **1/1**. Complete iPad Air 11-inch (M4) and iPhone 17 suites then ran sequentially and passed **144/144 each**: **138 expanded unit cases and six UI tests**, with zero failures, skips, expected failures or tests not run. Swift Testing's method count differs from the expanded parameterized-case total.

Result identifiers:

- Focused iPad: `Test-Peel-2026.11.23_04-25-50-+0200.xcresult`; summary `5C6410B1-D2E3-42ED-92AC-B5C34C740F56.txt`.
- Complete iPad: `Test-Peel-2026.11.23_04-28-06-+0200.xcresult`; summary `CF7194BD-7CA6-43D6-B61F-B7EE739E2E13.txt`.
- Complete iPhone: `Test-Peel-2026.11.23_04-30-40-+0200.xcresult`; summary `22E621D7-4283-48E8-9303-D2182154BC71.txt`.

These are recorded outcomes, not new runs following documentation changes. Raw results are not shipped in the repository; historical temporary bundles may no longer be available. The application, test and required resource bytes remain covered by `Verification/implementation-sha256.txt`.

## Coverage

`PeelTests` uses Swift Testing with fictional ZIP/HTML/JSON/text examples and injected importer, persistence and HTTP mocks. Automated tests make no live Instagram requests. Fixtures use `peel_fixture_*` usernames; model tests use disposable defaults domains and clean up their files.

Coverage includes comparison, ordering and deduplication; exclusion semantics across all three modes; review progress and counts; stale import completion/cancellation; malformed ZIP/JSON and resource bounds; failed writes and saved-data recovery; backup compatibility; temporary-export ownership; website/metadata policies and avatar request contracts; HTTP/redirect failures and rate limits; browser state; logout record selection; Demo isolation; localization and the privacy manifest.

Cancellation tests synchronize with an actual worker start. Avatar rate-limit tests hold responses until the initial batch starts. Other operation-race tests use controlled continuations and bounded polling; the suite is not completely free of timing assumptions.

The six XCTest/XCUIAutomation tests are:

- `testNavigationAndCaptureBaseline()`
- `testCorruptStorageShowsRecoveryAndRetry()`
- `testDashboardLargeTextAndRotation()`
- `testDemoGestureAndPopulatedLists()`
- `testPrivacyInformationNavigation()`
- `testBackupShareCancellationAndRepeat()`

UI tests use `XCUIApplication()` with Target Application set to Peel and unique defaults domains through the Debug-only harness. This isolates their stored lists from normal app state.

## Known intermittent failures

- **Ten-second Demo gesture:** an earlier iPad run missed activation after a 10.2-second press. Three isolated repeats on each simulator and later complete passes did not establish its cause. The original gesture and VoiceOver alternative remain; no timeout/assertion was weakened.
- **Launch/accessibility failures:** earlier complete runs had different UI failures on iPhone and iPad. Isolated passes did not prove an environment-only cause or shared-state interference.
- **Daemon setup:** a later iPad attempt timed out after 120 seconds initiating a control session, before executing tests. It was canceled; a subsequent focused run selected the correct app but failed during relaunch.
- **Termination-state mismatch:** Xcode recorded a signal-9 death notice for the app PID while XCTest continued reporting it foreground and timed out waiting for termination. This supports a process-state observation problem but does not establish its ultimate cause.

After a non-erasing restart of Xcode and the affected simulator, the focused check and both complete suites passed as recorded above. That demonstrates recovery, not a resolved root cause. Inspect result logs and runner state before retries; do not infer concurrency from interleaved console output or change production behavior solely to satisfy a failing runner.

## Coverage limits

Physical iPhone/iPad, iOS 17, full VoiceOver/Dynamic Type/contrast coverage, live Split View/Stage Manager resizing, real share-extension consumers, low-storage/process interruption and memory/performance stress remain incompletely verified. Genuine Instagram login/2FA/challenges/logout, current exports, avatars, offline recovery and observed throttling need authorized manual testing. Fixture success cannot establish live-service compatibility or authorization.

See [release requirements](Release-Readiness.md) for the manual verification matrix. No additional tests are implied by the current documentation or release status.
