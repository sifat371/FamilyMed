# FamilyMed — Codex Engineering Operating Policy

**Owner:** FamilyMed's creator is the sole product/development/Play Console decision-maker. A cousin may fund marketing only; do not assume a co-developer or account administrator.

**Goal:** Finish a *working*, Figma-aligned V1 using the existing Flutter + FastAPI/PostgreSQL code. This is a development assignment, **not** an audit assignment. A published release is a later phase.

**Reference order for this initiative:** Current owner request → `AGENTS.md` guardrails → this operating policy → `docs/implementation-progress.md` for state → `FamilyMed_Astra_Full_Product_Implementation_Mission_2026-10-08.md` for product scope → relevant original specs/code. If instructions conflict, obey the safety boundaries and surface the specific conflict instead of silently reverting owner-approved functionality. `AGENTS.md` is loaded automatically; this file is read when starting or resuming substantial work.

## 1. Repository and verified starting point

- Root on this Ubuntu PC: `/home/motion/Desktop/FamilyMed/FamilyMed` (reconfirm; do not assume other machines use this path).
- Remote: `https://github.com/sifat371/FamilyMed.git`; default branch `main`.
- On 2026-10-08: `origin/main` = `9e2116362d8bcb1fdb538785036d03750b98e0c8`.
- Figma feature branch `feat/figma-v1-visual-alignment` = `9e1a94890a5ef299aacfc45d907ee4d17eedb819` (open [PR #9](https://github.com/sifat371/FamilyMed/pull/9)). It contains styling/localization work, not the complete feature set. **Treat these as historical reference points, not immutable targets. Re-fetch before acting.**
- Most recent local verification reported modified `backend/uv.lock`, `docker-compose.yml`, `mobile/pubspec.lock`, and generated/untracked `mobile/android/build/reports/problems/problems-report.html`. The owner also added the mission Markdown to the root. Inspect, protect, and never indiscriminately stage these files.
- `.env` exists locally and is ignored. Do not print, copy, commit, or share its secret values.

## 2. Immediate development objective

Build a coherent manual-first family medication experience:

1. Welcome → register/login → choose family member → create/edit profile.
2. Add/edit medicine **manually** → natural transition to saved schedule/routine. Avoid duplicate records on retries/back navigation.
3. Configure quantity, schedule and reminder times; choose enable notifications or Not now (must not deactivate the routine).
4. Family-specific Today dashboard → mark taken/snooze/skip → backend persistence → history and correction → state survives refresh and relogin.
5. Working bottom navigation **Today / Family / History / Me** (Figma), with real destinations and usable account settings. Preserve established flows not pictured in Figma (edits, lifecycle, offline, correction).
6. Proper loading, offline, permission-denied, expired-session, empty, validation, error and retry behavior. English and Bangla must remain usable.
7. Back-end authorization isolation, safe history/sync, timezone correctness, and notification correctness.

Do **not** make false claims: a Flutter widget is not an end-to-end feature; a passing unit test is not real-device verification; mock AI is not prescription reading.

## 3. Figma visual source

Figma file: https://www.figma.com/design/i4Y7Og4YWvhCCPQLobwxSU/Family-Medication-Care-%E2%80%94-V1-Golden-Path-Wireframe?node-id=11-2

Page: `11:2` **V1.1 — Revised Golden Path**, 12 mobile frames (390×844):

- `11:3` Welcome; `11:14` Who do you care for?; `11:37` Add family member; `11:59` Family profile.
- `11:78` Capture prescription; `11:91` Review prescription image; `11:107` AI extraction review (**optional/deferred**, no fake recognition).
- `11:130` First medicine routine; `13:5` Second routine; `14:2` Enable reminders.
- `11:157` Today (Today/Family/History/Me navigation); `11:192` Dose actions.

Where Figma lacks production screens, extend its palette, visual hierarchy, cards/buttons, typography and spacing to working auth, manual entry, settings, corrections and offline/error states. Prefer responsive Flutter layout over fixed 390×844 coordinates. If no Figma connection exists in Codex, request/reference exports or use frame inventory and design specification; never claim direct visual verification if unavailable.

## 4. Autonomous execution and cost discipline

- **Work, don't audit.** Before each feature, inspect only relevant files and tests. Make the smallest coherent change that meets actual acceptance criteria. Only inspect broader architecture when necessary to avoid an integration bug.
- Use targeted searches (`rg`, `git grep`) instead of dumping entire trees. Limit log output (`tail`, failure-only), avoid looping/repeating failed commands, and reuse existing UI primitives and API contracts.
- Prefer Astra Low/Medium for implementation as available; switch to a cheaper model for mechanical tasks if the owner chooses. Do not assume a prompt can override the selected model or guarantee a usage limit.
- Keep the model's replies compact: completed slice, tests/result, pushed commit/branch, next action. Use `docs/implementation-progress.md` for persistent state; update meaningfully, not per small edit.
- Continue across the approved P0 product milestones without waiting for authorization for every normal code change. Break major work into coherent, testable, recoverable increments. No large rewrite or speculative infrastructure.
- When a tool, device, or Figma connection is unavailable, complete independent work and record precisely what was not tested. Never manufacture evidence.

## 5. GitHub checkpoint contract (mandatory)

Every meaningful implementation slice must be pushed to a GitHub feature branch **before beginning the next slice** when GitHub is available:

1. Confirm branch/upstream and review `git status`/`git diff`. Avoid disturbing pre-existing dirty files.
2. Implement and run tests proportionate to the change.
3. Update `docs/implementation-progress.md`: done/current/next, branch, test evidence, blockers, PR chain; do not mark functionality verified unless verified.
4. `git add` only explicit intended paths. Check `git diff --cached`; ensure no secrets, unrelated files, user data or generated artifacts.
5. Commit coherently; push to `origin` with the correct upstream. Verify push succeeded and the remote has the commit. If unable to push, report **LOCAL ONLY / NOT BACKED UP**, retain work, and do not claim GitHub continuity.
6. Maintain an open PR when useful; keep the dependency on PR #9 visible. **Do not merge PRs or force-push**.

If interrupted mid-slice, save a WIP commit on a development branch if it won't accidentally include private or unrelated changes. Mark WIP/known failing tests in progress. A WIP is a backup, **not an approved merge**.

**Branch strategy:** Preserve the existing Figma branch and PR #9. Prefer creating a new product branch from its commit (e.g. `feat/v1-product-completion`) rather than mixing substantive backend work into PR #9. If PR #9 is still open, use a stacked PR targeting `feat/figma-v1-visual-alignment` and document the dependency. Rebase/retarget only with appropriate review and without losing work. Never commit directly to `main` without explicit owner authorization.

## 6. Verification and safety

- Backend: `cd backend && uv sync --all-groups && uv run ruff check . && uv run alembic upgrade head && uv run pytest` (only on an appropriately isolated local/test database; never run unreviewed migrations against production).
- Mobile: `cd mobile && flutter pub get && flutter gen-l10n && dart run build_runner build && flutter analyze && flutter test && flutter build apk --debug` (choose targeted tests during each slice; full pass at milestones).
- Inspect API authorization, real persistence, offline replay, dose-state idempotency, timezone/day boundaries and notifications when touched. Real-device notification/camera checks must be reported separately from simulated tests.
- The sample Metformin/Amlodipine names in the Figma scenario are *test fixtures only*, not medication or scheduling advice. Never infer prescribed dose times, modify prescribed doses, or activate AI suggestions without explicit confirmation.
- Prescription image capture or OCR may be attempted **only after core V1 acceptance passes**. A genuine, user-controlled capture/preview and manual transcription can be a later increment; no unapproved paid OCR or uploads of patient images to external providers. If infeasible, mark deferred and ensure user-facing copy is truthful.
- Account deletion needs an authorized, testable, scoped data-deletion plan; do not prematurely delete data to satisfy a UI button. Do not deploy or publish automatically.

## 7. Approval and checkpoints

**Independently authorized:** project file edits, code refactors required for the task, local non-destructive test DB setup, tests, builds, dependency installation, feature branches, commits/pushes, PR creation/updates, documentation needed for continuity.

**Explicit owner approval required:** merge to `main`, publish/deploy production, change or delete actual user data, irreversible production migrations, commit private secrets, send health data to third parties, buy services, materially change privacy/medical claims or remove previously approved functionality.

If a choice is genuinely ambiguous but not reserved, make a reasonable conservative engineering decision, document it in the checkpoint, and continue. If reserved, prepare the reviewable work and ask for a decision without stopping unrelated implementation.

## 8. Session/account portability

GitHub carries **pushed** code, tests, migrations, specs, PRs and checkpoint files; it does not carry Codex conversations, local `.env`, physical test-device state or uncommitted files. A new account needs access to the GitHub repository plus its own Codex access and local toolchain. The next agent must:

1. Authenticate Git/GitHub without printing tokens; `git fetch origin`.
2. Find the *actual active development branch* from `docs/implementation-progress.md` and GitHub PRs. Do not blindly check out stale local `main`.
3. Read this policy, the checkpoint, and only relevant parts of the product mission/code.
4. Run essential local setup/targeted verification, then resume the next incomplete slice.
5. Push a checkpoint when the next slice is stable; keep the PR chain and handoff current.

**Owner-facing reporting:** A few sentences with `(branch + commit + GitHub push confirmed)`, working feature, test evidence, current blocker/next task. Do not narrate every tool call.
