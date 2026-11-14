# Contributing to Protocol Emulator

Welcome to the Protocol Emulator project!

This document defines the contribution guidelines and collaboration practices for the project. All contributors are expected to follow these guidelines to maintain a consistent and organized development workflow.

## 1. Branching Strategy

The `main` branch is the primary integration branch and should contain reviewed and stable changes.

Create a separate branch for each task or change.

Use the following naming conventions:

| Branch prefix | Purpose |
|---|---|
| `feature/` | New functionality and improvements to existing functionality |
| `fix/` | Bug fixes |
| `build/` | Build, tool-flow, CI and Docker changes |
| `verif/` | Testbenches, formal, regressions |
| `docs/` | Documentation changes |

Examples:
- `feature/i2c-controller`
- `fix/spi-clock-generation`
- `build/adopt-tt-layout`
- `verif/spi-formal`
- `docs/add-contributing-guide`

Always create new branches from the latest `main`. Pull Requests go into `main` only.

## 2. Commit Guidelines

Write clear and descriptive commit messages.

Use the following format:

`<type>: <short-description>`

Common types:

| Type | Purpose |
|---|---|
| `feat` | New functionality |
| `fix` | Bug fixes |
| `enhancement` | Improvements |
| `docs` | Documentation changes |
| `refactor` | Code restructuring without functional changes |
| `test` | Test-related changes |
| `build` | Build or implementation-flow changes |

Example:

`feat: add I2C start condition detection`

Keep commits focused on logically related changes.

## 3. Pull Request Process

All changes must be submitted through Pull Requests (PRs) targeting `main`.

### 3.1 Create a Branch

1. Open the repository on GitHub.
2. Switch to the `main` branch.
3. Make sure you have the latest changes from `main`.
4. Create a new branch using the naming conventions in Section 1.

### 3.2 Make and Commit Changes

1. Make the required code or documentation changes, following the
   [RTL coding rule](README.md#rtl-coding-rule).
2. Run relevant tests and checks. Before every push, at least (inside the
   `pe-verif` image, see [verification/docker/README.md](verification/docker/README.md)):
   ```bash
   scripts/check_rtl_frontend.sh
   scripts/lint_rtl.sh
   ```
   For changes in `src/` or `test/`, also run the top-level test (`cd test && make -B`);
   see [README.md](README.md#running-the-flows-locally) for the other flows.
3. Review your own changes.
4. Run `git status` and stage explicit paths (`git add <paths>`), not `git add .`,
   so that no stray or generated file gets committed. Then commit with a
   descriptive commit message.
5. Rebase on the latest `main` (no merge commits from `main` into your branch).
6. Push your branch to GitHub.

Example Git commands:

```bash
git switch main
git pull origin main
git switch -c feature/i2c-controller

# Make your changes

git status
git add src/i2c_controller/
git commit -m "feat: add initial I2C controller"

# Before pushing: checks, then rebase on the latest main
scripts/check_rtl_frontend.sh && scripts/lint_rtl.sh
git fetch origin
git rebase origin/main
git push -u origin feature/i2c-controller        # after a rebase of a pushed branch: --force-with-lease
```

### 3.3 Create a Pull Request

1. Open the repository on GitHub.
2. Navigate to the **Pull requests** tab.
3. Click **New pull request**.
4. Select:
   - **Base:** `main`
   - **Compare:** Your working branch.
5. Click **Create pull request**.
6. Provide a clear title and description explaining what changed and why.
7. Reference the related Jira issue, where applicable.
8. Add labels (see Section 5.1).
9. Click **Create pull request**.

### 3.4 Review and Merge

1. All required GitHub checks must be green (`rtl-checks`, `test`, `docs`, `gds`
   incl. precheck and gate-level test; see [README.md](README.md#github-checks)),
   and at least one approval is required before merging. Details:
   [docs/WORKFLOWS.md](docs/WORKFLOWS.md#github-checks).
   - `test` and `gds` skip their heavy jobs when a push changes no design or flow
     files (always run on `main`); **"Skipped" counts as passing**.
   - A newer push to your branch cancels the still-running `test` / `gds` run of
     the older one; only the latest push counts.
   - `scripts/check_rtl_frontend.sh` fails on any `*.v` / `*.sv` under `src/` that
     is in no `<block>.f` and not in `info.yaml`: list every RTL file you add.
2. Reviewers should check correctness, readability, maintainability, and relevant verification evidence.
3. Address review feedback and resolve all review conversations.
4. Once approved, merge using **Squash and merge**.
5. Delete the working branch after merging.

**Note:** Contributors cannot approve their own pull requests. An independent collaborator must provide the required approval.

### 3.5 Working on Multiple Changes

- A separate branch should be created for each logical task, feature, or independent piece of work.
- Multiple related changes and commits can be made on the same branch.
- A Pull Request does not need to be created for every commit. Create one when the logical piece of work is ready for review.
- If changes are requested during review, make the updates on the same branch and push them. The existing PR will automatically reflect the updates.
- Avoid creating unnecessary branches for individual files or small, related changes.

### 3.6 Starting the Next Task

Once the current PR has been merged:

1. Switch back to `main`.
2. Pull the latest changes.
3. Create a new branch for the next task.

This ensures that new work starts from the latest integrated code.

## 4. Code Review Guidelines

- All required checks green and at least one approval are required before merging.
- Resolve all review conversations before merging.
- Reviewers should check correctness, readability, maintainability, and relevant verification evidence.
- Contributors should address review feedback before merging.
- Significant design or interface changes should be discussed with the relevant technical owners.

## 5. Issue Tracking

Jira is the primary project-management and task-tracking system.

- Use Jira for tasks, assignments, priorities, Epics, and workflow status.
- GitHub Issues may be used for technical bugs, questions, enhancements, and development discussions.
- Reference relevant Jira issue IDs in branch names, commits, and PR descriptions where applicable.

### 5.1 Labels

Label every GitHub issue and PR with one type and the area(s) it touches:

| Kind | Labels |
|---|---|
| Type | `bug`, `enhancement`, `task`, `question`, `documentation` |
| Area | `area: rtl`, `area: verification`, `area: flows`, `area: software`, `area: documentation` |
| Triage | `help wanted`, `good first issue`, `duplicate`, `invalid`, `wontfix` |

The issue templates set the type label automatically.

## 6. Directory Ownership

The repository is organized into high-level functional areas.

| Directory | Purpose |
|---|---|
| `src/` | Hardware design (RTL that gets hardened) |
| `test/` | Top-level cocotb test of the Tiny Tapeout top |
| `verification/` | Verification infrastructure, testbenches and the `pe-verif` Docker image |
| `software/` | ISA, assembler, toolchain, and programs |
| `flows/` | ASIC implementation and tool-flow configuration |
| `scripts/` | Automation and utility scripts |
| `docs/` | Project documentation |

Each functional area's designated owner is responsible for defining and maintaining its internal directory structure, coding conventions, and documentation.

Changes affecting multiple areas should be coordinated with the respective owners.

## 7. General Guidelines

- Keep changes focused and avoid unrelated modifications.
- Do not commit generated files, temporary files, or build artifacts unless explicitly required
  (`.gitignore` covers the flow outputs: `runs/`, `tt/`, `tt_submission/`, venvs, waveforms).
- Document important design decisions and interfaces.
- Keep code and documentation consistent.
- Communicate significant architectural or interface changes with the relevant owners.
- Never commit credentials, private keys, or other sensitive information.
