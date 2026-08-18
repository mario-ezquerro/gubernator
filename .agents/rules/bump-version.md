---
trigger: always_on
---

# Rule: Automatic Version Bumping & Descriptive Changelogs

Whenever an AI agent completes a task, implements a new feature, or makes a commit to the codebase, the agent MUST automatically increment the version number in the `VERSION` file at the root of the repository and generate descriptive changelogs.

## 📌 Rules for Version Bumping
1. Read the `VERSION` file (e.g., `v2.21.2`).
2. If the change is a minor bug fix, documentation update, or patch, increment the PATCH version (`v2.21.3`).
3. If the change is a major new feature or sprint phase, increment the MINOR version (`v2.22.0`).
4. Update the `VERSION` file before notifying the user.

## 📝 Descriptive Commit Messages & Release Changelogs
1. **Meaningful Commit Subjects & Bullets**:
   - Always follow Conventional Commits format (`feat(scope): ...`, `fix(scope): ...`, `perf(scope): ...`, `docs(...)`, `chore(...)`).
   - The commit message body MUST contain clear, detailed bullet points explaining exact user-facing improvements, new endpoints, and architecture changes. Avoid generic messages like `bump version`, `fix bug`, or `update`.
2. **Annotated Git Tags**:
   - When creating a Git tag, ALWAYS create an **annotated tag** with a descriptive summary of the release:
     ```bash
     git tag -a vX.Y.Z -m "Release vX.Y.Z: <Detailed summary of features and fixes>"
     ```
3. **GitHub Release & Auto-Updater Sync**:
   - Push both the commit and tag to GitHub:
     ```bash
     git push origin main && git push origin vX.Y.Z
     ```
   - This triggers the automated GitHub Release CI (`.github/workflows/release.yml`) which extracts the annotated tag message and commit log, generating rich release notes with categorized improvements for the Web Dashboard's "Update Improvements" modal.
