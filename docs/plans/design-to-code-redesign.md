# Design-to-code: Expense Tracker redesign

Status: planning only; the target design is not yet implemented. See `DESIGN.md` for design rules.

## UI and navigation

- Implement the approved English-language screens for Home, Statistics and Settings as three persistent bottom-navigation tabs. Keep the app an expense/income tracker, not an e-wallet.
- Move theme selection and Drive account/backup controls to Settings. Move PDF/CSV reports to Statistics; their date-range selector is independent of backup.
- Provide Week, Month and Year filters for both Expenses and Income. Reuse the same period layout, updating dates, categories, totals and chart data for the selected type and period. Income Week and Year do not need separate frames.
- Implement scrolling and persistent navigation in Flutter. A fully interactive prototype is not required. Design mock data and state illustrations are not evidence of working behavior.

## Drive backup and sync: requested behavior

- Back up all data across all months in a single complete snapshot. Each successful backup creates one new version. Keep at most the latest three versions in Google Drive; each version is one complete file, not a file per month. No month picker.
- Sync is a user-initiated download/import of the latest complete backup from Google Drive, selected automatically. It is not implicitly a two-way sync. No file or month picker for this action.
- Design UI labels: `Back up all data` and `Sync latest backup`. Home has only the Add transaction action; Drive actions are in Settings. Trigger Google sign-in only when explicitly requested or required for a Drive action, not merely when entering Settings.
- Retain the existing non-destructive import behavior as the starting point: avoid overwriting or deleting local transactions silently. The exact behavior for edits, deletions and conflicts across devices needs a product decision before calling this two-way sync or replacing local data.
- Preserve previous good versions until the new upload is complete and verified. Prune only app-owned snapshots after success; never delete old backups on failed uploads. Establish a deterministic version ordering and handle interrupted uploads, retries, concurrent devices, duplicate versions, missing backups, corrupt newest files, Drive permissions and cleanup failures without silent data loss. Verify the selected snapshot before importing.
- Existing installations have monthly JSON files. Define and test an explicit legacy migration/restore path before removing access to those backups; never delete legacy files as part of automatic retention. The schema, naming/versioning, concurrency control and any fallback to an older complete snapshot are implementation decisions, not existing behavior.
- Specify which entities belong in a complete snapshot (transactions and required category/subcategory data at minimum), schema validation, size limits and atomic restore. Test incomplete, invalid, unsupported and partially failed operations; preserve local data and report actionable results.

## Account behavior

- Read last-used account/status from local state for display; opening Settings must not launch an interactive Google sign-in. Cached status is historical, not proof that credentials still work.
- Sign-in may be initiated by the explicit sign-in control, backup or sync. Handle revoked/expired authorization and cancelled sign-in clearly.
- Sign out/disconnect must clear cached account identity and connection status; distinguish local sign-out from Google permission revocation, and verify behavior on SDK failure. Do not store tokens in preferences.

## Background work and update

- Backup/sync progress and result should remain visible when navigating away and back while the app process remains alive. Define cancellation and partial-failure reporting; avoid duplicate operations. Do not claim survival after app termination without an Android-backed implementation and tests.
- The update controller is app-scoped in `lib/presentation/providers/update_providers.dart`; verify real behavior rather than assuming background durability. Download/install failure, progress and platform background execution are coding-stage work. No extra update states or full prototype required now.

## Current code and implementation checks

- `lib/presentation/pages/backup_page.dart` currently exports monthly Drive backups and offers local JSON import and Drive restore with month selection. Drive restore downloads/imports one file at a time; existing rows are skipped and failures reported. This does not yet meet the requested snapshot/sync behavior.
- `lib/domain/usecases/import_month_usecase.dart` validates the monthly JSON format; compatibility and full-snapshot limits must be designed before changing it. Review the repository and Drive service before implementing.
- `lib/data/services/google_drive_service.dart`, `lib/data/services/google_sign_in_memory.dart`, and `lib/presentation/providers/backup_providers.dart` contain existing Drive/auth flows. `accountChanges()` currently initializes authentication; verify and decouple passive display from interactive authentication.
- Test full-data round-trip, three-version retention and failed-upload safety, legacy files, repeated sync and duplicates, empty/corrupt backups, conflict handling, account revocation, navigation during work, and update behavior. Test Android background survival separately if it becomes a requirement.

## Ordered implementation plan

1. Establish a baseline: check the current branch and existing changes, run Flutter analyze/tests on a machine with the Flutter SDK, and document any existing failures. Use the CI workflow when local Flutter is unavailable. Do not claim tests passed without a run.
2. Prepare the visual foundation: import the approved piggy-bank and receipt artwork into the Flutter asset bundle after verifying dimensions, alpha and usage rights; register them in `pubspec.yaml`. Define shared light/dark semantic color, text, spacing and radius tokens; reuse the existing persisted theme mode. Replace mockup emoji navigation symbols with consistent accessible Flutter icons. Verify text scaling, small screens, contrast and touch targets.
3. Refactor `lib/main.dart` routing into a persistent Home/Statistics/Settings shell; keep Add/Edit outside the shell and preserve back/deep-link behavior and tab state. Move theme controls into Settings, then implement Home and Add/Edit with both themes and validation states. Keep local transactions and existing features intact.
4. Implement Statistics period filtering for both transaction types, keeping date boundaries in the established date-range helpers. Move existing PDF/CSV report controls from Backup to Statistics while retaining their independent range selector. Exercise empty periods, locale, year boundaries, chart totals and export errors.
5. Separate cached account presentation from authentication. Opening Settings must not invoke restore or a sign-in sheet; label cached identity as last used, not verified connected. Gate sign-in behind explicit account/Drive actions, and clear local account history on disconnect; handle SDK errors and revoked credentials.
6. Design and test the complete snapshot format and transactional, non-destructive import before changing Drive operations. Specify entities, schema version, validation, size limits, conflicts and legacy access. Keep the legacy monthly importer until its migration path is proven. Test round-trip, duplicates, failed validation and rollback with multi-month data.
7. Add Drive versioning and sync latest: upload a new complete version and verify success before pruning only app-owned snapshots, retaining three; never prune legacy files. Address concurrent devices, ordering, interrupted uploads and cleanup failure explicitly. Test these with mocked Drive responses before live testing. Preserve usable backups when uncertain.
8. Move backup/sync progress into app-scoped state, prevent duplicate operations, and test navigation while work runs. Audit update download and install behavior independently: in-process persistence is not process-death survival. Choose and test an Android-backed mechanism only if process-death survival is required; no unsupported durability claim.
9. Run unit, widget and integration tests for both themes, navigation, account cancellation, backup, restore and reports; test Android sign-in and update behavior on a device/emulator. Inspect representative rendered screens and accessibility at enlarged text sizes. Record actual commands, results and unresolved decisions in the change report.

## Design handoff

- Implementation assets are `assets/images/piggy_bank.png` and `assets/images/receipt_mascot.png`, registered in `pubspec.yaml`. See `DESIGN.md` for the visual handoff.
- Current dark reference colors: background `#101916`, surface `#1B2924`, secondary surface `#244239`, primary text `#EDF7F1`, secondary text `#A8BDB3`, accent `#83DFB7`; light reference background `#F4F6F8`, primary emerald `#0E5A44`. Confirm text/background contrast numerically when defining tokens, not from screenshots alone.
- Treat repeated elements and states as variants of shared light/dark tokens; implement reusable Flutter components, not one widget per state.
- Mockup symbols and example amounts are illustrative. Use actual accessible icons, real app data and responsive layout; do not treat frame dimensions as fixed device sizes. Design screens are static, not proof of functionality.

## Open decisions before implementation

1. Define sync conflict/deletion semantics for edits on different devices and whether any destructive replacement needs confirmation.
2. Define legacy monthly backup migration and whether local JSON import/export remains available separately from Drive sync.
3. Define exactly which data is included beyond transactions and categories, and whether background work must survive process death.
