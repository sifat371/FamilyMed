# FAMILYMED V1 — GPT-6 ASTRA AUTONOMOUS PRODUCT COMPLETION MISSION

> **COPY THIS ENTIRE BRIEF INTO CODEX (GPT-6 ASTRA).** This supersedes the earlier audit-only instructions. The goal is working product code, not an audit report.
>
> Product owner: the user. AI role: senior Flutter/FastAPI engineer, UX implementer, tester, and product architect executing within the boundaries below.

## Mission and success condition

Finish the **existing** FamilyMed application as a credible, working **Figma V1.1-aligned family medication-care product**. The repository already contains a substantial Flutter app, FastAPI backend, PostgreSQL schema, local notification service, offline sync and tests. **Do not start over. Do not only prepare a plan. Actually implement the missing screens, workflows, backend corrections and tests, verify them, and push reviewed changes on feature branches.**

**Priority:** complete the manual-first product end to end; closely align visual hierarchy and UX with Figma; remove misleading/inert user experiences; make every user-visible feature actually work; verify real Flutter↔FastAPI↔PostgreSQL flows. Prescription capture/extraction is an optional **stretch milestone** only after that core is complete and verified. Do not ship an invented or fake AI result.

The first complete product is a functioning Android development build connected to the real backend and usable by a caregiver to create and reliably track medication routines. It is not yet necessarily a Play Store production deployment or a medical device.

## Authoritative references

- Local repo: `/home/motion/Desktop/FamilyMed/FamilyMed`
- GitHub: `https://github.com/sifat371/FamilyMed`
- Figma: `https://www.figma.com/design/i4Y7Og4YWvhCCPQLobwxSU/Family-Medication-Care-%E2%80%94-V1-Golden-Path-Wireframe?node-id=11-2`
- Figma file key `i4Y7Og4YWvhCCPQLobwxSU`, page `11:2` — **V1.1 — Revised Golden Path**. Twelve mobile frames, reference 390×844.
- Current checkout branch: `feat/figma-v1-visual-alignment` at `9e1a94890a5ef299aacfc45d907ee4d17eedb819` when last verified; `origin/main` at `9e2116362d8bcb1fdb538785036d03750b98e0c8`. **Recheck at start.**
- PR #9: `https://github.com/sifat371/FamilyMed/pull/9`. It has passed CI but is limited to visual styling and localization changes; it did **not** build the missing features. It must **not** be merged without the owner's approval.
- Original specs: `docs/superpowers/specs/2026-09-22-familymed-v1-design.md`, `2026-09-23-auth-family-medications-design.md`, `2026-09-23-schedules-today-doses-design.md`.

### Verified Figma 12-frame inventory

| Frame ID | Screen | Critical behavior / visual intent |
|---|---|---|
| `11:3` | Welcome | Brand/benefit, Get started, truthful AI promise |
| `11:14` | Who do you care for? | Parent / spouse / child / myself / someone else |
| `11:37` | Add family member | Name, relationship, language, privacy-aware form |
| `11:59` | Family member profile | Medication list, Scan prescription, Add manually, clear safety explanation |
| `11:78` | Scan prescription | Camera/gallery choices, capture guidance — optional stretch |
| `11:91` | Review image | Image preview, retake/continue — optional stretch |
| `11:107` | AI extraction review | Crop/source, candidates, **selection ≠ confirmation**; optional stretch, only with genuine extraction |
| `11:130` | First medicine routine | Confirmation, prescription instruction separate from reminder clock time |
| `13:5` | Second medicine routine | Multi-medicine flow and activate routines |
| `14:2` | Enable reminders | Enable/Not now; routines stay active if notifications declined |
| `11:157` | Today | Family-grouped doses, `2/3 taken`, **Today / Family / History / Me** bottom navigation |
| `11:192` | Dose actions | Taken, Snooze, Skip, explicitly user-confirmed dose status |

**Design fidelity expectations:** use the Figma frames as the visual/hierarchy reference: typography, palette, cards, pills, field treatments, button ranking, spacing and content grouping. Adapt responsibly for Android safe areas, small screens, larger text sizes and English/Bangla overflow. Match intent rather than blindly positioning widgets at fixed pixel coordinates. Where the design lacks a screen (login, registration, manual medicine editor, global History, Me, offline/error states, settings), extrapolate using existing tokens/components without removing functionality. Preserve existing DOB, medication edit/lifecycle, history correction, offline data and QA improvements introduced after the wireframe.

**Figma access:** attempt Figma MCP/integration and use its screenshots/design context. If unavailable, consult the linked Figma file and the verified frame descriptions above. Never claim a pixel-perfect match without render-based inspection; state any evidence gap and still build what can be verified. Do not block the core implementation because a Figma API is unavailable.

## Existing implementation; do not recreate it

The repo contains: Flutter/Riverpod/GoRouter/Dio/Drift, auth, family onboarding, manual medication CRUD, schedules, dose generation and actions, member history/corrections, local notifications, offline sync, English/Bangla, and FastAPI/Postgres/Alembic/pytest. AI directory is a mock-only boundary; there is no validated prescription OCR. Existing PR #9 changes 16 mobile presentation/theme/localization/test files, not backend or feature routes. **Inspect before changing.** Keep the working backend domain and tests unless a demonstrated bug or missing operation requires change.

Known gaps to check in the current branch:
- Add-manual-medication flow currently returns to member profile instead of offering guided routine creation.
- `mobile/lib/app/app_shell.dart` uses only Today and Family navigation, while Figma shows four sections; implement functional History and Me or, if blocked, clearly document the remaining deliberate deviation instead of adding fake tabs.
- Prescription scan is disabled in member profile. The welcome copy should not imply usable AI scanning while it is absent.
- `backend/app/auth/router.py` has register/login/refresh/me but no confirmed self-service account deletion; account settings and deletion should be planned/implemented carefully where feasible, without exposing destructive unauthenticated operations. These are required before Play submission.
- Reminder scheduling currently uses local notifications and Android exact-alarm permissions; validate alarm scheduling and fallback honestly.
- `mobile/lib/features/schedules/presentation/set_routine_screen.dart` uses hardcoded `Asia/Dhaka` for a new routine. Decide timezone behavior explicitly; do not silently mishandle devices in other zones.
- Backend production deployment and Play release packaging are **not** this mission; keep clean interfaces and note blockers only.

## Initial Git protection — mandatory, brief, then BUILD

Prior verification found the checkout clean relative to its upstream commit, **but with three modified files and one untracked generated report**:
- modified `backend/uv.lock`
- modified `docker-compose.yml`
- modified `mobile/pubspec.lock`
- untracked `mobile/android/build/reports/problems/problems-report.html`

Recheck `git status`, remote, HEAD, diff, and branch; inspect these modifications for intent. **Preserve them**, do not `reset --hard`, `clean`, delete, stash, silently commit, overwrite, or discard. Stage only explicitly intended files (`git add <specific-paths>`), and don't commit the generated HTML report. If existing lockfile changes are essential for reproducible builds, understand and include only explicitly justified changes.

**No extra audit worktree is required.** Use the existing checked-out repository, respecting dirty files. Prefer creating a new product-completion feature branch from the current Figma feature HEAD after ensuring the branch switch will preserve changes safely. Suggested `feat/v1-figma-product-completion`. If you create a PR before PR #9 merges, make the dependency explicit (stacked PR targeting `feat/figma-v1-visual-alignment` or otherwise preserve the ancestry); don't hide or duplicate the existing PR #9 changes. Do not merge PR #9 or commit directly to main. If a clean branch switch would be unsafe, continue working on an appropriate branch without risking existing changes and explain the choice. GitHub authentication as `sifat371`, fetch and push access were already verified; recheck minimally.

## Implementation priorities — EXECUTE, DO NOT STOP AFTER PLANNING

### Milestone A — complete the integrated manual-first golden path (P0)

Deliver a first-time caregiver experience that genuinely works:

1. Welcome → register/login → choose person → create family profile → member profile.
2. Add medicine **manually**, validate name, strength, form, start/end dates, and present a natural **Set routine** next step (reuse existing server models and editor; don't create conflicting medication records on back navigation/retry).
3. Configure clock times and quantities, save a persisted schedule, then choose **Enable reminders** or **Not now**. A declined permission cannot deactivate the medication routine.
4. Today shows scheduled doses correctly grouped by family member; actions Taken / Snooze / Skip persist through backend, reflect in Today, survive refresh/re-login, and appear in History. Confirm status corrections are auditable.
5. Show appropriate empty, loading, validation, network and offline states; make back/navigation flows robust and predictable. Ensure lifecycle actions pause/resume/end update schedule, Today and reminders correctly.
6. Use **real** FastAPI + PostgreSQL calls in production-facing screens; no hardcoded successful demo data. Local cache is allowed only when identified as cache/offline. Ensure refresh, authentication expiry and queued sync do not create duplicate or inaccurate dose events.

### Milestone B — complete Figma-aligned navigation and production-quality frontend (P0)

1. Treat current PR #9 as the visual foundation, not as proof alignment is finished. Compare **real Flutter renders** against the 12 Figma frames accessible to you; fix significant spacing, hierarchy, typography, copy, card, button and navigation discrepancies.
2. Honor Figma's Today/Family/History/Me information architecture with functioning destinations, not placeholders. Global History may aggregate from existing member history repositories/backend via an appropriately scoped endpoint if needed; add backend routes only if genuinely necessary, with auth and tests. `Me` should provide usable account details, logout, preferences, support/privacy links if available, and a safe route toward account deletion. Don't add dead buttons.
3. Preserve all existing features not shown in Figma, including member and medication editing, history correction, reminder preferences and offline state.
4. Ensure readable English/Bangla strings, touch targets, scrolling/keyboard behavior, safe areas, empty/loading/error states and responsive layout on 360×800, 390×844, and larger Android devices.
5. Make the brand and welcome copy truthful for the actual feature set. If scanning is not implemented, communicate “coming soon” without implying medicine was read by AI.
6. Audit navigation paths for inaccessible routes, infinite redirects, broken back stacks and state restoration. Fix what you find.

### Milestone C — backend integration, correctness and reliability (P0)

- Run migrations and tests against isolated local/test Postgres; diagnose reproducible backend/UI integration failures. Add narrowly scoped endpoints only when necessary.
- Verify authorization isolation across family/member/medication/schedule/dose/history; reject cross-account access. Never log prescription content or credentials. Treat medication records as sensitive health-related information.
- Verify dose status lifecycle, idempotency, timezone/date boundaries, missed-dose calculation, recurrence/schedule mutation, pause/resume/end, reminder opt-in and offline replay/collision behavior.
- Reconcile Android notification permission, exact/inexact timing, boot/restoration, cancellation on routine changes, taps routing to the right dose, and lack of a false guarantee of precise delivery. Prefer testable abstractions; be candid about scenarios requiring physical-device QA.
- Ensure API failures are communicated without suggesting that a medicine action succeeded when it did not.
- Ensure local dev Android backend configuration is configurable without committing local IPs or secrets; emulator-only `10.0.2.2` must not be mistaken for a real-phone/prod backend URL.

### Milestone D — optional prescription capture / assisted entry (P1, only after P0 passes)

**This milestone is optional, not a reason to leave the manual-care app unfinished.**

- If practical, implement real permission-aware camera/gallery selection, image preview/retake and a safe user-controlled flow for transcribing/entering medicine details. Provide appropriate storage/access protection and retention design if persisting images. No public URLs or uncontrolled logging.
- Keep OCR/handwriting extraction **optional**. Only implement if an available, trustworthy model/service and real evaluation permit it, without unapproved paid APIs or privacy compromises. Do not fabricate Metformin/Amlodipine from a demo image or label deterministic samples as AI output.
- Candidate selection must remain separate from **explicit human confirmation**; users check the source image and manually verify medicine name, strength, form, quantity, and schedule. No diagnosis, prescription changes, dose suggestions or autonomous schedule activation.
- If no safe functional OCR is possible, leave an explicitly deferred scanning/AI flow or ship a clearly labelled manual entry from captured image, based on actual safe implementation feasibility. Do not leave half-functional clickable routes or misleading claims.

## Acceptance tests (must be proven with evidence)

**Core scenario:** New user registers; adds Amma; enters Metformin 500 mg and Amlodipine 5 mg **manually**; creates two times for Metformin and one for Amlodipine as user-entered schedules; enables or declines reminders; Today displays three scheduled occurrences, the user marks two taken, Today shows **2/3 taken**, member/global history reflects actions; the state persists after app restart/re-login; skip and snooze and correction paths work. These are UI acceptance examples, **not dosing advice**. Never infer dose frequency from a medicine name.

Other essential tests: wrong-password/login validation, empty family and empty Today, creation and editing, duplicate submissions, malformed schedule, multi-account authorization, offline cache/replay, time zone/day transitions, alarm permission denied, notification tap route, pause/end effects, correction event history, Bangla overflow and Android back navigation. Tests must reflect actual app behavior and not mock away the backend integration in E2E evidence.

**Evidence:** `flutter analyze`, `flutter test`, debug Android build, backend Ruff/pytest, Alembic migration upgrade; exercise Flutter↔FastAPI↔Postgres integration, ideally on Android emulator or physical device. Report exact commands, results and any device-dependent unverified cases. Do not claim visual or notification device QA when no device is available. Compare rendered app screenshots to Figma if tooling permits.

## Execution cadence and autonomy

- Spend only enough time inspecting the codebase to choose safe, minimal edits. **Implement immediately**; do not produce four audit documents or stop after a roadmap.
- Work through Milestones A–C autonomously, running tests after coherent increments. Avoid a giant rewrite. Use local subplans as needed, but keep momentum toward working screens and API functionality.
- Keep a **short progress checklist** in `docs/implementation-progress.md` so work can resume across context limits: completed functions, changed paths/commits, tests, blockers, next actions. This is a build log, **not a substitute for implementation**.
- Review diffs, fix test failures, commit small coherent checkpoints to the approved feature branch, and push that feature branch to GitHub. Create/update a PR with a clear dependency on PR #9; never merge automatically. Commit only intended files and never secrets/build artifacts.
- Do not pause for routine engineering decisions, ordinary dependency installs, non-destructive local database setup, code changes or tests. Make reasonable choices and document them.
- **Ask product-owner approval before:** merging into `main`, production deployment, destructive or irreversible data operations, adding paid external services, exposing patient data to third parties, changing substantive medical/privacy policy, or discarding any pre-existing work. Do not assume full CLI permissions imply authorization for these decisions.
- If a step is blocked (e.g. no emulator, Figma MCP unavailable, camera hardware unavailable, paid OCR required), finish the independent core milestones, accurately report remaining unverified cases, and keep the project buildable.
- Continue through the agreed P0 milestones without stopping after the first completed file or first report. If the environment prevents a long uninterrupted run, record exactly what is done and next steps for immediate continuation.

## Final deliverable

A functioning Flutter Android app + FastAPI backend with the V1 manual-care experience, Figma-aligned presentation, working navigation and end-to-end medication state; passing applicable automated tests/build; feature branch commits pushed to the correct repository; an unmerged PR for owner review; an honest short completion matrix (working, tested, needs device QA, deferred); straightforward local run instructions. Optional prescription functionality separately reported as completed or clearly deferred, never fake.

**Begin by inspecting the current repo and the real Figma reference, then start implementing. Do not ask for a standalone audit and do not create an `audit` directory.**
