# FamilyMed — Local development and GitHub recovery runbook

This document is for the human owner and replacement Codex sessions. `AGENTS.md` contains always-on instructions, `codex.md` the policy, and `docs/implementation-progress.md` the live checkpoint. **Only use commands that fit the actual current branch and state; never blindly reset.**

## 1. Verify the correct repository (any new session/account)

```bash
git rev-parse --show-toplevel
git remote -v
git status --short
git branch -vv
git fetch origin
gh auth status
gh pr list --repo sifat371/FamilyMed --state open
```

Expected GitHub remote: `https://github.com/sifat371/FamilyMed.git`; existing Figma PR #9. GitHub authentication is **per machine/account**; ChatGPT GitHub permissions do not automatically authorize another Codex environment.

If a different Codex account is used, install/authenticate GitHub CLI if necessary with `gh auth login`, and verify the new GitHub identity has access. Do not paste tokens into chat or commit credential files. Another account can recover **only pushed** commits and documentation.

## 2. Initial development-branch strategy (review changes first)

Astra may create a new product branch **from the checked-out Figma branch**, keeping PR #9 intact. Do not execute automatically if a name already exists or any operation might overwrite a dirty checkout.

```bash
# Example only, after inspection:
git branch --show-current          # expected feat/figma-v1-visual-alignment
git status --short                  # preserve dirty changes
git switch -c feat/v1-product-completion
```

A branch switch without checkout conflicts generally carries dirty working changes into the new branch. **Those changes remain uncommitted and must not be swept into unrelated commits.** Use explicit file staging only; never `git add -A` with a dirty worktree. If unsure, stop and propose a preservation plan.

Push product work to its own branch. While PR #9 is open, a new PR can target `feat/figma-v1-visual-alignment` as a **stacked PR**. When PR #9 merges with owner approval, inspect and retarget the stacked PR without losing changes. Never merge automatically.

## 3. Local runtime — existing repository commands

From repository root, create your local `.env` only if absent; **do not overwrite a pre-existing `.env`**:

```bash
# Only when .env does not already exist:
cp .env.example .env
docker compose up -d postgres
```

Backend (Python >=3.13,<3.14; `uv` required):

```bash
cd backend
uv sync --all-groups
uv run alembic upgrade head  # only on the intended local/dev database
uv run uvicorn app.main:app --reload
```

Flutter mobile (run in a separate terminal):

```bash
cd mobile
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter run
```

Emulator backend URL defaults to `http://10.0.2.2:8000/api/v1`. For a **real phone**, use a reachable LAN server address and the supported runtime parameter rather than rewriting source:

```bash
flutter run --dart-define=FAMILYMED_API_BASE_URL=http://YOUR_LAN_IP:8000/api/v1
```

Use HTTPS with production data; the example HTTP URL is **local development only**. Do not expose the development API publicly.

## 4. Efficient verification

```bash
cd backend && uv run ruff check . && uv run pytest
cd mobile && flutter analyze && flutter test
cd mobile && flutter build apk --debug
```

Run targeted tests while changing a single feature; run full commands and inspect integration/real Android behavior at a coherent milestone. Flutter unit tests and CI cannot substitute for permission, background-alarm, camera and physical device checks.

## 5. GitHub checkpoint (after a coherent feature)

```bash
git status --short
git diff --stat
# git add EXACT intended source, test and checkpoint paths (never all files blindly)
git diff --cached --check
git diff --cached --stat
git commit -m "feat: <verified slice>"
git push -u origin <current-feature-branch>
git ls-remote --heads origin <current-feature-branch>
```

Verify the remote SHA matches the local HEAD; `git status` alone does not prove a successful remote backup. Make sure `docs/implementation-progress.md` is included in a pushed checkpoint. Use draft PRs for ongoing work; a PR must state dependencies and remaining tests.

## 6. If the session ends or the account changes

1. Save/commit/push safe incomplete work to the **feature branch**; record WIP and known failures. No secrets.
2. Verify the remote contains the latest commit; write the exact branch/commit/PR and next step in `docs/implementation-progress.md`.
3. On a new machine/account: clone or open repo, authenticate GitHub, fetch all relevant refs, check out the **checkpoint's active feature branch**, read relevant rules/mission, install toolchains, and resume.
4. Restore local `.env` using secure provisioning (never from GitHub) and initialize a **local/test** DB. Do not claim production or medical data is backed up by source-code pushes.
5. If a push fails, keep local commits and say **NOT BACKED UP TO GITHUB** until resolved.
