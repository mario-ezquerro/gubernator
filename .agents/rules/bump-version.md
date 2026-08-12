---
trigger: always_on
---

# Rule: Automatic Version Bumping

Whenever an AI agent completes a task, implements a new feature, or makes a commit to the codebase, the agent MUST automatically increment the version number in the `VERSION` file at the root of the repository.

**Rules for bumping:**
1. Read the `VERSION` file (e.g., `v1.1.1`).
2. If the change is a minor bug fix or small documentation update, increment the PATCH version (`v1.1.2`).
3. If the change is a new feature (like completing a Sprint Phase), increment the MINOR version (`v1.1.3`).
4. Update the `VERSION` file accordingly before notifying the user.
5. **Git Tag & Release Sync & Descriptive Commit Messages**:
   - Commit messages MUST be detailed and descriptive (e.g., following Conventional Commits format like `feat(scope): detailed explanation` or `fix(component): detailed root cause fix explanation`). Avoid simple/generic commit messages like `bump version` or `fix bug`.
   - Whenever a version bump is committed, ALWAYS create and push a corresponding Git tag (`git tag vX.Y.Z && git push origin vX.Y.Z`) to GitHub so that the GitHub Releases API (`api.github.com/repos/mario-ezquerro/gubernator/releases/latest`) detects the update and the Web Dashboard's auto-updater badge remains fully operational.

