# FamilyMed V1 — Implementation checkpoint

Updated 2026-10-09. Canonical handoff; fetch and verify remote before resuming.

## Branch and preservation
- Active: `feat/v1-care-reminder-reliability`, based on PR #11 HEAD `bd41801a4877b3241b88a589965daea8a8bd926e`.
- Verified open/unmerged stack: [#9](https://github.com/sifat371/FamilyMed/pull/9) → [#10](https://github.com/sifat371/FamilyMed/pull/10) (`504bfd0`) → [#11](https://github.com/sifat371/FamilyMed/pull/11) (`bd41801a`). PR #11 backend/mobile CI both SUCCESS.
- Current draft [PR #12](https://github.com/sifat371/FamilyMed/pull/12) targets `feat/idempotent-medication-creation`; no merge or deployment authorized.
- Verified implementation pushes: `e199e19` (session-safe reminders/retries), `c0deebf` (fresh-cache history correction).
- Preserve original local changes: `backend/uv.lock`, `mobile/pubspec.lock`, `docker-compose.yml`, generated `mobile/android/build/`, and ignored `.env`. Excluded from commits.

## Completed inherited work (do not repeat)
- Manual medicine save opens routine setup using persisted ID; back returns to profile without creating another medication.
- PR #11 adds retry-safe creation UUID, atomic backend insert, mismatch/account/member isolation and legacy compatibility; no migration required.
- New routines use member timezone and medication dates; existing routines preserve their timezone/date boundaries. Failed schedule lookup blocks saving and offers retry.
- Four functioning Today/Family/History/Me tabs; global history, correction refresh, persisted account name/language, logout and family care settings.
- Family create/edit supports explicit IANA timezone selection, with explanation that existing routines retain their saved timezone.
- Figma theme and local navigation assets; routine/reminder layouts tested in English/Bangla at 360×800, 390×844, 480×960 with 1.5× text.

## Current development slices
- `e199e19`: coordinator persists across account changes and reads current repository on refresh. Clear invalidates stale responses and serializes cancellation after platform scheduling. App rechecks account after sync; account changes clear reminders.
- Preference read and scheduling errors offer Retry. Scheduling retry does not rewrite the enabled preference; disable reconciliation failures remain visible.
- History correction now carries the server history dose into the form and seeds an absent cache row before queuing correction. Historical doses need not have appeared in Today.
- History seeding never overwrites an existing queued action and does not make historical doses eligible for reminders.
- Added regression tests for late feed responses, scheduling/clear overlap, new-session refresh, retry behavior, empty-cache history correction and preservation of queued snapshots.

## Latest slice: History routes and compact navigation
- Verified PR #12 CI at `d7c1c0d`: backend and mobile both SUCCESS (run `37843238587`).
- Added production-router regression coverage for global/member History → correction → save/cancel → originating History, refreshed status and selected History tab.
- Fixed an uncaught refresh exception after successful correction when global History reload fails. Provider error/Retry UI remains responsible for recovery; retry does not resubmit the correction.
- Compact 360×640 English/Bangla tests at 1.5× text cover all four tabs, correction scrolling, reachable save button and return navigation. No additional compact layout changes were needed.
- Current validation: `flutter analyze --no-pub` PASS; targeted History/navigation/account suites: 12 passed (7 new route/compact regressions).
- Tests use the production router and correction/sync repositories with in-memory storage and a controlled server fixture; they do not replace live API/device verification.

## Prior milestone verification
- `flutter analyze --no-pub`: PASS.
- Full `flutter test --no-pub --reporter expanded`: 98 passed, 1 opt-in live test skipped by default.
- Opt-in live test against loopback HTTP API + isolated Postgres: PASS, including newly added correction after relogin with an empty Drift cache and server history verification.
- Live scenario also covers two medicines/three doses, declined reminders, snooze/taken/skip/correction, preferences, lifecycle and cross-account isolation. Notification scheduler is substituted; this is not device UI QA.
- Backend `uv run --frozen pytest -q`: 75 passed. `uv run --frozen ruff check .`: PASS.
- Isolated test database: existing container `familymed-product-test-20261008`, loopback 55438; no changes to `.env` or actual user data. Live API started on loopback 58008 for tests.
- `flutter build apk --debug --no-pub`: PASS; `mobile/build/app/outputs/flutter-apk/app-debug.apk`.
- `flutter devices` / `flutter emulators`: Linux/Chrome only; no Android device or AVD. Device notification delivery, boot restoration and full UI walkthrough unverified.

## Remaining V1 acceptance
- [ ] A: Manual-care and retry protection implemented; complete device UI walkthrough remains.
- [ ] B: Working Figma-derived navigation/screens; full rendered comparison remains. Account deletion needs a scoped implementation/retention plan before release.
- [ ] C: Automated checks and live repository integration pass; Android notification permission/background/boot tests remain device-dependent.
- D optional: Prescription capture/OCR deferred; no fake extraction.
- Next: device/Figma render QA when available; remaining device-dependent acceptance is listed above. History return/refresh and compact navigation task is complete.
- Use the live runner instructions in `docs/DEVELOPMENT_RUNBOOK.md`; do not point it at a database containing actual family records.
