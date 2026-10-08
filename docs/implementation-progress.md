# FamilyMed V1 — GitHub Handoff / Implementation Progress

> **Canonical checkpoint.** Updated and pushed with every meaningful development slice. A new Codex session/account should start here and verify GitHub before assuming this file is current. Keep this file under ~100 lines. Never put secrets or personal/health data here.

## Current handoff (2026-10-08)

- **Status:** Implementation started; GitHub authenticated and Figma branch verified.
- **Repo:** `https://github.com/sifat371/FamilyMed`.
- **Last verified `origin/main`:** `9e2116362d8bcb1fdb538785036d03750b98e0c8` (2026-10-08 verification; re-fetch).
- **Last verified Figma branch:** `feat/figma-v1-visual-alignment` / `9e1a94890a5ef299aacfc45d907ee4d17eedb819`; [PR #9](https://github.com/sifat371/FamilyMed/pull/9) open/unmerged.
- **Active product development branch:** `feat/v1-product-completion`, created from verified Figma HEAD `9e1a948`.
- **GitHub backup of this checkpoint:** Initial instructions checkpoint being committed and pushed on the product branch.
- **Local dirty files at last check:** `backend/uv.lock`, `docker-compose.yml`, `mobile/pubspec.lock`; untracked generated Android report; mission Markdown newly copied by owner. Preserve/review; do not accidentally stage them.
- **PR dependency:** New product-completion PR should be stacked on PR #9 while PR #9 is unmerged.

## Existing code baseline (NOT equivalent to device-verified done)

- Source already contains auth, family CRUD, manual medication CRUD, medication lifecycle, schedules, Today/dose actions, member history/correction, local notifications, offline sync, English/Bangla, FastAPI/Postgres and tests.
- PR #9 has Figma-themed presentation/localization changes; does not add the missing features.
- Figma requires functional 4-tab navigation; current app only has Today/Family. Manual medicine flow currently returns to profile rather than guiding to routine. Scan prescription is disabled; backend production deployment not in scope of this build mission.

## Mandatory V1 milestones — update only with verified evidence

- [ ] **A:** Guided manual-care path: registration → family → medication → routine → reminders → Today → dose actions → history; real backend persistence.
- [ ] **B:** Figma-aligned **working** Today / Family / History / Me navigation, complete accessible Flutter UI, account management, English/Bangla, error/offline states.
- [ ] **C:** Backend/mobile integration, auth isolation, dose lifecycle/idempotency, timezone and notification reliability; passing applicable checks and Android build.
- [ ] **D optional:** User-controlled prescription photo capture/preview; real extraction only if safe and tested, otherwise explicitly deferred.

## Next executable actions

1. Verify current Git status, PR #9 and worktree; preserve all pre-existing changes.
2. Read root `AGENTS.md`, `codex.md`, and **relevant** V1 mission sections. Create a product feature branch from Figma branch if safe; don't merge PR #9.
3. Implement highest-impact working-flow gap, likely **manual add → guided routine → reminders → Today**, with backend persistence and targeted tests; then commit/push checkpoint.
4. Continue with four-tab functional navigation/settings and other mandatory gaps; test/commit/push each coherent slice.

## Latest completed slice / proof

- **Feature/changes:** None by Astra yet.
- **Last pushed implementation commit:** None on product-completion branch yet.
- **Tests run by new development session:** None yet. Prior PR #9 CI passed, but does not constitute device/E2E verification.
- **Known blockers:** Physical Android device and direct Figma access in Codex not yet confirmed. Continue independent core work.

## Handoff discipline

On each checkpoint replace the current fields above with actual branch/commit/PR, test commands + results, verified features, incomplete work, one precise next step. Push this file alongside code. If push fails, say **LOCAL ONLY**. Keep prior major decisions in commit history rather than accumulating verbose session logs here.
