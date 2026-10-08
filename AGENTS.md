# FamilyMed — Codex Repository Rules

This file is intentionally small because Codex loads `AGENTS.md` automatically. The product owner directs scope; execute approved implementation rather than producing an audit. For detailed operating policy use `codex.md`, for the V1 scope use `FamilyMed_Astra_Full_Product_Implementation_Mission_2026-10-08.md`, and for handoff use `docs/implementation-progress.md`. Read only the relevant portions needed for a task; do not reread every document before every edit.

## Product and architecture
- Finish **the existing** Figma V1.1-aligned FamilyMed Android app: Flutter/Riverpod/GoRouter/Dio/Drift and FastAPI/PostgreSQL/Alembic. Do not rebuild from scratch.
- Make the manual medication-care path actually work end to end with real backend persistence. Prioritize usable UI, navigation, onboarding, schedule/reminder setup, Today, dose actions, history, account settings and reliability.
- Figma is the visual reference; preserve working capabilities added after the wireframes. No inert buttons or pretend success states.
- Prescription image capture/OCR is optional **after** the manual-first V1 works. Never represent mock AI as functional or activate extracted medicines without human confirmation. Do not make medical recommendations or infer dosing.

## Working safely and autonomously
- At session start: check working branch, `git status --short`, upstream and current PR. Preserve existing uncommitted files and `.env`; do not reset, clean, overwrite, force-push or silently stash.
- Work in coherent feature increments: inspect relevant code → implement → targeted test → update `docs/implementation-progress.md` → review diff → **commit and push code + checkpoint to GitHub** → continue. Never claim backup until push succeeds.
- Push at **meaningful checkpoints**, not after every tiny edit. If a session may end with unfinished work, create a clearly labeled WIP commit on a feature branch, if safe, and push; document failing tests and next action. Never merge incomplete code into `main`.
- Stage explicit paths only. Do not commit secrets, `.env`, private health information, generated build artifacts, or unrelated lock/config changes.
- Write focused tests for changed behavior. Do not claim device QA, Figma pixel matching, or backend integration without running the corresponding checks.
- Prefer concise terminal outputs and status reports. Avoid repeated broad audits, unnecessary rewrites, overplanning and redundant tool calls; do not skip necessary safety testing to save tokens.
- Routine file edits, dependency installs, test runs, feature branches, commits, feature-branch pushes and PR creation are authorized. **Approval required:** merge to `main`, production deployment/Play publishing, destructive data operations, spending money, third-party sharing of medical data, and fundamental privacy/medical-policy changes.

## Resuming across accounts
- GitHub is the source of truth for pushed code and handoff documents. At the start of a new session, read `docs/implementation-progress.md`, verify the **correct remote feature branch**, and resume the next task. Keep that file accurate and pushed.
- The user's explicit current request overrides historical planning preferences when they conflict. Stop only for a true blocker or a reserved decision; otherwise keep building.
