# Contributing to Protocol Emulator

Welcome to the Protocol Emulator project!

This document defines the contribution guidelines and collaboration practices for the project. All contributors are expected to follow these guidelines to maintain a consistent and organized development workflow.

## 1. Branching Strategy

The `main` branch is the primary integration branch and should contain reviewed and stable changes.

Create a separate branch for each task or change.

Use the following naming conventions:

| Branch prefix | Purpose |
|---|---|
| `feature/` | New functionality |
| `bugfix/` | Bug fixes |
| `enhancement/` | Improvements to existing functionality |
| `docs/` | Documentation changes |

Examples:
- `feature/i2c-controller`
- `bugfix/spi-clock-generation`
- `enhancement/uart-fifo`
- `docs/add-contributing-guide`

Always create new branches from the latest `main`.

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

1. Make the required code or documentation changes.
2. Run relevant tests and checks.
3. Review your own changes.
4. Stage and commit your changes with a descriptive commit message.
5. Push your branch to GitHub.

Example Git commands:

```bash
git switch main
git pull origin main
git switch -c feature/i2c-controller

# Make your changes

git add .
git commit -m "feat: add initial I2C controller"
git push -u origin feature/i2c-controller
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
8. Click **Create pull request**.

### 3.4 Review and Merge

1. At least one approval is required before merging.
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

- At least one approval is required before merging.
- Resolve all review conversations before merging.
- Reviewers should check correctness, readability, maintainability, and relevant verification evidence.
- Contributors should address review feedback before merging.
- Significant design or interface changes should be discussed with the relevant technical owners.

## 5. Issue Tracking

Jira is the primary project-management and task-tracking system.

- Use Jira for tasks, assignments, priorities, Epics, and workflow status.
- GitHub Issues may be used for technical bugs, questions, enhancements, and development discussions.
- Reference relevant Jira issue IDs in branch names, commits, and PR descriptions where applicable.

## 6. Directory Ownership

The repository is organized into high-level functional areas.

| Directory | Purpose |
|---|---|
| `rtl/` | Hardware design |
| `verification/` | Verification infrastructure and testbenches |
| `software/` | ISA, assembler, toolchain, and programs |
| `flows/` | ASIC implementation and tool-flow configuration |
| `scripts/` | Automation and utility scripts |
| `docs/` | Project documentation |

Each functional area's designated owner is responsible for defining and maintaining its internal directory structure, coding conventions, and documentation.

Changes affecting multiple areas should be coordinated with the respective owners.

## 7. General Guidelines

- Keep changes focused and avoid unrelated modifications.
- Do not commit generated files, temporary files, or build artifacts unless explicitly required.
- Document important design decisions and interfaces.
- Keep code and documentation consistent.
- Communicate significant architectural or interface changes with the relevant owners.
- Never commit credentials, private keys, or other sensitive information.
