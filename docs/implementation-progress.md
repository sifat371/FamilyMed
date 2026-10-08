# FamilyMed V1 — Implementation checkpoint

Updated 2026-10-08. Canonical handoff; verify remote before resuming.

## Branch and preservation
- Active: `feat/v1-product-completion`, based on Figma HEAD `9e1a948`.
- Instructions checkpoint `6f9cb64` pushed successfully; product checkpoints follow on this branch.
- Product draft [PR #10](https://github.com/sifat371/FamilyMed/pull/10) is stacked on PR #9; latest prior pushed slice `556d6ee`.
- [PR #9](https://github.com/sifat371/FamilyMed/pull/9) remains open and unchanged. Product PR must target its branch while it is unmerged.
- Preserve original local changes: `backend/uv.lock`, `mobile/pubspec.lock`, `docker-compose.yml`, generated `mobile/android/build/`, and ignored `.env`. These are excluded from commits.

## Implemented slices
- Manual medicine save opens routine setup with the persisted medication ID; back from a profile-launched flow returns to profile without resubmitting medication.
- New routines use member timezone and medication start/end dates; existing routines preserve their own timezone/date boundaries.
- Schedule lookup failure blocks saving and offers retry instead of treating a network error as no existing schedule.
- Routine displays saved medicine summary using existing Figma theme. Retrieved Figma `11:130` design context and screenshot; no rendered-device visual comparison yet.
- Reminder preference failures display an error; failed reads no longer falsely report disabled. Reminder screen scrolls for smaller viewports.

- Four working tabs: Today, Family, History, Me. History aggregates authorized member records and refreshes after corrections, with empty/error/retry states.
- Me edits name/language through authenticated `PATCH /auth/me`; preferences persist and apply to app locale. Logout and member care settings navigation work.
- Family/medication providers refresh on account changes to prevent reuse of previous account data.
- Navigation uses locally stored Figma icon assets at 20×20; direct render comparison remains pending.

- Family create/edit now provides an explicit IANA timezone selector. New routine timezone follows the member; existing routines retain their saved zone, explained in the UI.
- Fixed routine dropdown/header overflow under large text.

## Verification
- Isolated Postgres container `familymed-product-test-20261008`, loopback port 55438, database/user `familymed_test`; local test credentials supplied explicitly to commands, existing `.env` untouched.
- Isolated test environment `uv run --frozen alembic upgrade head`: passed.
- Same environment `uv run --frozen pytest -q`: 73 passed. `uv run --frozen ruff check .`: passed.
- `flutter analyze --no-pub`: passed. Full `flutter test --no-pub`: PASSED locally during checkpoint recovery.
- `flutter build apk --debug --no-pub`: passed; APK at `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter devices` / `flutter emulators`: no Android device or AVD available.
- Focused Flutter tests: manual medication, routine setup, reminder refresh, registration/manual entry, online/offline care path: 17 passed.
- Opt-in live test (`FAMILYMED_LIVE_TEST_URL=http://127.0.0.1:58008/api/v1`): PASSED with real Flutter repositories, HTTP API and Postgres. Two medicines/three doses, reminders declined, snooze/taken/skip/correction history, fresh-cache relogin, lifecycle, account preferences and cross-account isolation. Platform scheduler substituted; not a device UI walkthrough.
- Responsive routine/reminder tests pass for English/Bangla at 360×800, 390×844, 480×960 with 1.5× text; permission denial and failed preference write covered.
- Timezone form-state regression and full Flutter suite: PASSED locally during checkpoint recovery; automated menu-scroll interaction not covered.

## Milestones and next work
- [ ] A: Manual-care repository integration verified; ambiguous create retry protection remains.
- [ ] B: History/Me/account preferences and responsive routine/reminder layouts implemented. Full device render comparison and account deletion workflow remain (scoped deletion plan required before release).
- [ ] C: Full mobile checks/debug build, live integration, authorization/reliability regression tests and device QA where available.
- D: Prescription capture/OCR deferred until mandatory V1 acceptance; no fake extraction.
- Next: harden medication creation against ambiguous network retries; finalize regression coverage and checkpoint.
- No merge or deployment authorized. Device notification behavior and visual fidelity remain unverified.

## Pending slice: retry-safe manual medication creation
- Implementation branch: `feat/idempotent-medication-creation`, stacked on PR #10.
- Flutter manual entry reuses a generated creation UUID across form retries.
- FastAPI accepts optional `creation_id`, atomically upserts with `ON CONFLICT DO NOTHING` on the existing medication ID, and rejects mismatched key reuse with 409.
- Older clients without a creation UUID remain compatible; no database migration required.
- Tests added for repeated POST, account/member isolation, legacy compatibility, and UI retry key.
- GitHub CI verification pending; no Flutter/Dart or PostgreSQL test runner is available here.
- Next: inspect CI, fix any failures, then resume V1 device UI/notification checks.
