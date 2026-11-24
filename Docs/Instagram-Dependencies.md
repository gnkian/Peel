# Instagram dependency ownership

This document describes source ownership, not service authorization or a promise of future compatibility. Keep live website behavior separate from offline export schemas. Use fictional fixtures and injected/intercepted transport in automated tests; do not fetch Instagram fixtures in tests.

## Live website and URL policy

`Peel/Core/Instagram/InstagramWebsitePolicy.swift` owns login/export endpoint values, profile construction and matching, login/challenge path classification, HTTP image-host validation, website-data record matching, and the existing avatar URLSession configuration. `InstagramEndpoints` retains its current interface for browser, review and avatar callers. A URL/path change belongs in the policy and its tests, not in SwiftUI screens or PeelModel.

These rules have intentionally different scopes:

- Transport checks lowercase the URL scheme and accept Instagram, cdninstagram and fbcdn hosts/subdomains.
- Profile success checks require the current HTTPS scheme/host/path rules and the intended username.
- Login classification preserves existing path-prefix behavior; it is not an authentication verifier or navigation allowlist.
- Logout matches the original Instagram/Facebook/CDN record-name list. It is not inferred from transport hosts and does not establish server-side logout.
- Metadata URL acceptance remains independent, including its exact scheme check. Never replace it with the transport predicate without a separately approved behavior change.

`Core/Networking/HTTPClient.swift` owns streaming bounds, cancellation, HTTP status handling and enforcement of its injected URL predicate on initial requests, redirects and final response URLs. Its production Instagram configuration is supplied by the integration layer. No default permissive predicate is introduced.

`Core/Services/InstagramSession.swift` owns the existing WebKit data-removal operation. `InstagramNavigationCoordinator.swift` owns web-view lifecycle and callbacks. `BrowserLoadState.swift` owns request generations, errors and success gating through the endpoint interface. Their persistent-store, manual-confirmation, review-marking and retry semantics must not be changed as a side effect of a URL update.

## Export, metadata and username boundaries

`Core/Instagram/InstagramProfileMetadataParser.swift` owns AvatarMetadata's exact two regexes, pattern precedence, entity decoding and metadata-only URL acceptance. A changed og:image layout belongs here and in its fictional fixtures. It does not own HTTP transport validation or export HTML.

`Core/Instagram/InstagramAvatarLoader.swift` owns the two-request sequence, headers/timeouts/body bounds, UTF-8 conversion and ImageIO thumbnail options, plus the existing request gate. `Core/Services/InstagramAvatarStore.swift` owns cache, shared in-flight tasks, cancellation, retry/cooldown and avatar presentation. A metadata change must not require altering that cache or SwiftUI body. The existing HTTPClient protocol supplies deterministic payloads; no additional parser protocol is required for a pure String-to-URL function.

`Core/Instagram/Exports/InstagramExportParser.swift` now owns the existing archive filename regex, standalone type detection and JSON/HTML/text export parsing. `Core/Services/InstagramZIPReader.swift` remains a compatibility composition point: it passes that filename predicate to `ZIPArchiveReader`, which owns ZIP validation, decompression, CRC, resource bounds and entry order. Generic ZIP validation has no live website or export schema dependency. The selection predicate is required, with no permissive default.

`Core/Models/UsernameRules.swift` owns the original validation, normalization and ordered deduplication. `UsernameParser` retains all previous signatures as compatibility forwarding functions. Persistence validation calls the shared identity rule directly, without parsing export files. `ImportService.restore` remains separate: it decodes ProgressFile and invokes SavedStateValidator, never InstagramExportParser.

Export parsing must retain the distinction between archive-entry filename selection and standalone-list type detection. The latter is intentionally broader. JSON field recognition, export HTML links (including `_u/`), text handling, supported empty structures and reserved headers belong to the offline parser, not the live website policy.

Username validation is also used by persisted-state validation. Changing accepted characters, length, normalization or reserved-name handling requires explicit compatibility analysis; a website change is not permission to invalidate saved data. Ordered deduplication must retain the first occurrence, without new sorting.

## Presentation and saved application state

Dashboard, account lists and browser wrappers consume services and endpoint values. Service-specific help/error wording remains in its existing localized presentation files and `PeelError`; changing service instructions may require an intentional copy update. Do not move all product wording into a URL configuration registry.

PeelModel owns imported/reviewed state and composes existing ImportServicing and InstagramSessionServicing dependencies. It must not acquire HTML regexes, export keys or website URLs. ProgressStore, QueueState, PeelPreferences and ProgressFile retain their existing keys/fields and backup marker.

## Handling a future Meta change

1. Reproduce the issue manually with authorization; record the redirect/status/format without credentials or personal usernames. Do not intentionally trigger rate limits.
2. Identify the owner above. Preserve a sanitized fictional example that reproduces the observed structure, including a negative case.
3. Run characterization tests before changing a rule. Keep metadata and transport acceptance tests separate, and do not guess alternate endpoints or scrape around restrictions.
4. Change only the responsible integration component. Preserve unsupported-format errors, failed-operation data protection, cancellation, limits and demo isolation.
5. Run the full iPhone and iPad suites, including the original baseline, and compare requests, parsing order and saved-data compatibility. Document any intentional behavior change separately.
6. Manually verify genuine login/2FA/challenges, current avatars/export compatibility and review flows as relevant. Fixture success does not establish live-service support, authorization, complete logout or App Store compliance.

See [testing](Testing.md) for coverage and known failures, and [release requirements](Release-Readiness.md) for physical-device and live-service verification.
