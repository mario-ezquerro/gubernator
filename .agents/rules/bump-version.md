# Rule: Automatic Version Bumping

Whenever an AI agent completes a task, implements a new feature, or makes a commit to the codebase, the agent MUST automatically increment the version number in the `VERSION` file at the root of the repository.

**Rules for bumping:**
1. Read the `VERSION` file (e.g., `v1.1.1`).
2. If the change is a minor bug fix or small documentation update, increment the PATCH version (`v1.1.2`).
3. If the change is a new feature (like completing a Sprint Phase), increment the MINOR version (`v1.2.0`).
4. Update the `VERSION` file accordingly before notifying the user.
