# FamilyMed V1 — Implementation checkpoint

Updated 2026-10-08. Canonical handoff; verify remote before resuming.

## Branch and preservation
- Active: `feat/v1-product-completion`, based on Figma HEAD `9e1a948`.
- Instructions checkpoint `6f9cb64` pushed successfully; product checkpoints follow on this branch.
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

## Verification
- Isolated Postgres container `familymed-product-test-20261008`, loopback port 55438, database/user `familymed_test`; local test credentials supplied explicitly to commands, existing `.env` untouched.
- Isolated test environment `uv run --frozen alembic upgrade head`: passed.
- Same environment `uv run --frozen pytest -q`: 71 passed before account changes; targeted auth tests after changes: 11 passed. `uv run --frozen ruff check .`: passed.
- `flutter analyze --no-pub`: passed. Full `flutter test --no-pub --reporter expanded`: 82 passed.
- `flutter build apk --debug --no-pub`: passed; APK at `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter devices` / `flutter emulators`: no Android device or AVD available.
- Focused Flutter tests: manual medication, routine setup, reminder refresh, registration/manual entry, online/offline care path: 17 passed.
- Widget tests use test repositories; they are not evidence of Flutter-to-live-backend or device verification.

## Milestones and next work
- [ ] A: Finish guided manual-care acceptance and verify real backend integration.
- [ ] B: History/Me/account preferences implemented; responsive English/Bangla verification remains. Account deletion workflow is not implemented (requires scoped plan before release).
- [ ] C: Full mobile checks/debug build, live integration, authorization/reliability regression tests and device QA where available.
- D: Prescription capture/OCR deferred until mandatory V1 acceptance; no fake extraction.
- Next: live Flutter repository → HTTP FastAPI → Postgres acceptance, responsive/Bangla tests, reminder failures and correction refresh regression coverage.
- No merge or deployment authorized. Device notification behavior and visual fidelity remain unverified.
