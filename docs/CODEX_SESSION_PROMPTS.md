# FamilyMed — short Codex prompts

These short prompts assume the repository files `AGENTS.md`, `codex.md`, the V1 mission and `docs/implementation-progress.md` exist. They replace repeated multi-page prompts and are meant to minimize Astra context use.

## First development session — paste into Codex

```text
You are FamilyMed's principal engineer. Work in this existing Git repository, not a new audit worktree. Read the root AGENTS.md (automatically loaded if available), codex.md, docs/implementation-progress.md, and the relevant sections of FamilyMed_Astra_Full_Product_Implementation_Mission_2026-10-08.md. This is an implementation assignment: FINISH the working Figma V1.1-aligned Flutter/FastAPI manual-first V1, not an audit.

First check git status/remote/current branch and the uncommitted lock/config files. Preserve all owner work and .env. PR #9 is Figma styling only and remains unmerged. If safe, start a dedicated feat/v1-product-completion branch from the Figma branch, keeping a visible stacked-PR dependency. Never merge into main.

Start immediately on the highest-impact incomplete core flow. Inspect only relevant files, implement with real backend persistence, run targeted tests, review the diff, update docs/implementation-progress.md, commit and PUSH each meaningful checkpoint to GitHub, then continue automatically through approved milestones A–C. Keep replies brief. Prescription capture/OCR is optional only after the core works; no fake AI.

Do not stop after a report or plan. Stop only for a real blocker or reserved owner approval. End each checkpoint with pushed branch/commit, tests actually run, next task.
```

## New session / another Codex account — paste into Codex

```text
Resume FamilyMed from GitHub, not from assumptions about this chat. Verify authentication, fetch origin, locate the active pushed feature branch/PR, and read AGENTS.md, codex.md and docs/implementation-progress.md from that branch. Reuse the existing mission and architecture; read only relevant feature code. Verify current commit and previous test results, finish the next incomplete approved slice, run relevant tests, update progress, commit and push. Do not merge into main. If checkpoint disagrees with GitHub, report the mismatch and choose the newest verified pushed work without destroying local changes. Keep output brief.
```

## Approaching context/usage limit — paste into Codex

```text
Before stopping, checkpoint FamilyMed safely: inspect git diff/status, run relevant available checks, stage only intended code/tests/docs, update docs/implementation-progress.md with completed work, in-progress work, exact next step, tests and blockers. Make a clearly labeled WIP commit if unfinished and safe, push the current feature branch, verify remote SHA, and briefly report the branch, commit and whether remote backup succeeded. Never include secrets or merge unfinished code into main.
```

## Review milestone — paste into Codex

```text
Without changing main, prepare an honest milestone review: what works end-to-end with real FastAPI/Postgres, what is unit-test-only, what has not been device-tested, screenshots/comparison to Figma if available, pending bugs, precise GitHub branch/PR and next task. Run the necessary full milestone checks and fix regressions before claiming completion. Keep the summary under 20 lines.
```
