# Peel release readiness

This checklist distinguishes recorded simulator results from outstanding device, service and distribution requirements.

## Current verification status

Recorded on 23 November 2026 with Xcode 27.2 (27B52), iOS 27.2 simulators: focused iPad navigation **1/1**, then complete iPad Air 11-inch (M4) and iPhone 17 suites **144/144 each**, run sequentially. Each suite contains 138 expanded unit cases and six UI tests, zero failures/skips. See [Testing.md](Testing.md) for result identifiers and unresolved intermittent failures.

Debug uses **-Onone / testability YES**; Release uses **-O / testability NO**. The deployment target is **17.0**, Swift language mode **5.0**. A Release archive and development IPA export succeeded on 24 November 2026; the exported app passed strict/deep signature verification and retains the source privacy manifest.

The attached IPA is **Apple Development-signed**, not an App Store/TestFlight distribution package. Its profile covers **two registered devices** and expires **27 November 2026 at 16:43:41 UTC**. It retains `get-task-allow=true`. A standard GitHub release does not change those signing or installation restrictions.

## Local data, exports and privacy

- Imported lists, exclusions and review progress use app-owned UserDefaults and a coherent checkpoint. Legacy keys and `follow-manager-backup-v1` remain compatible. UserDefaults provides no durable-write acknowledgement; physical storage/power-loss testing remains outstanding.
- Login confirmation is a manual Boolean, not proof of authentication. Instagram sign-in occurs inside persistent WebKit website storage. Passwords and cookies are not included in Peel progress backups.
- Backups contain usernames and review information. A user-selected sharing destination receives a copy outside Peel's cleanup scope. Local-first does not mean data cannot leave the device through sharing or device backups.
- TemporaryExportStore registers only Peel-created current-process files. Cleanup follows confirmed consumer completion; active consumers, imported files, user-selected files, saved progress and unconfirmed prior-process exports are protected. No directory sweep or deletion-on-disappearance is used. Real extension consumers and VoiceOver cancellation still require verification.
- The privacy manifest declares verified UserDefaults required-reason usage, **CA92.1**, only. No direct production file-timestamp, available-disk-space, boot-time or active-keyboard API use was established in the documented inventory. Reaudit when API usage or dependencies change.
- WebKit pages and avatar requests contact Instagram/Meta infrastructure. Avatar transport has separate cookie-disabled configuration and bounded requests. These implementation details do not establish external service authorization or a security guarantee.
- Logout requests removal of selected Instagram/related website data records; actual login/2FA/logout behavior and the precise disclosure wording need live verification. Already exported copies cannot be erased by Reset Lists.

Required-reason references: [Apple policy](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## Outstanding release requirements

- Preserve the unresolved Demo long-press and historical runner/launch failures; later passes do not determine their original causes.
- Complete the physical-device and live-service matrix below, including iOS 17. Simulator checks do not establish accessibility-label claims or oldest-OS compatibility.
- Assess Xcode recommendations individually. The App Intents metadata-extraction warning is distinct from compiler errors; adding an unused framework only to silence it is not justified.
- Provide a hosted privacy policy, support/metadata/disclosures and confirm service authorization and licensing/branding rights.
- Configure and validate the intended distribution channel, signing and package separately. The existing development IPA is not evidence of App Store, TestFlight or AltStore PAL eligibility.
- Recheck applicable Apple, distribution-channel and Instagram requirements before submission; these documents do not certify compliance.

## Physical-device and live-service verification matrix

Run on physical iPhone and iPad, including the oldest supported OS and a current OS. Record device, OS, text size, window size, expected result, actual result and evidence without credentials or personal usernames.

- iPad: portrait, both landscapes, 1/3–2/3 and half Split View, entering/leaving multitasking, live resizing and Stage Manager where supported. Verify dashboard, populated relationship lists, exclusions, sidebar/tabs selection, sheets and file/share pickers. Screenshots alone do not establish live resizing.
- iPhone: original default-size design, small display, landscape, content above the floating tab bar, keyboard and scrolling.
- Accessibility: all Dynamic Type sizes through AX5, VoiceOver reading order and default/named demo actions, headings and repeated account actions, 44-point hit regions, Increase Contrast, Reduce Motion and external keyboard navigation. Do not claim an accessibility nutrition label from source inspection alone.
- Login: genuine sign-in, 2FA/challenge, redirects, cancellation, keyboard/focus, relaunch, expired session and logout/relaunch. Use the owner's authorized account manually; never automate account actions.
- Export/import: current sanitized JSON and HTML exports, Files/iCloud/security-scoped selection, malformed or truncated data, supported maximum input and low storage. Check saved progress before and after failed operations.
- Avatars/network: real supported and missing avatars, offline startup and retry, connection loss, cancellation/dismissal and observed throttling. Do not intentionally hammer Instagram to generate rate limits.
- Manual review: correct profile, Next/Previous, excluded accounts, saved/reloaded review counts, no review mark after a failed load, and a clear distinction between reviewed and actually unfollowed.
- Backup/share: Save Progress at large text and short window height; share sheet on iPad; cancel sharing, re-open, restore a valid backup and reject an invalid one without replacing saved data. Shared files contain usernames.
- Lifecycle: background/foreground during import and browsing, process termination, interrupted saves, device restore/upgrade, memory pressure and worst-case import/list latency. Test legacy upgrade compatibility and separately assess downgrade/edit/upgrade round trips.

Recorded automated results are in [Testing.md](Testing.md). Pending items above are not claimed to pass.

