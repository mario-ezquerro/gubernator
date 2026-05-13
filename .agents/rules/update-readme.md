# Rule: Continuous README.md Maintenance

## Objective
The `README.md` file MUST be continuously created, updated, and expanded to reflect the real-time state of the Gubernator project. It serves as the primary entry point and documentation for any user or developer interacting with the project.

## Requirements

1. **Keep it Updated at Every Step:** Whenever a new feature, endpoint, or CLI command is implemented, you must immediately update the `README.md` to reflect this change. Never leave the documentation out of sync with the code.
2. **Provide Practical Examples:** For every new functionality added to Gubernator, include a concrete, runnable example in the README. 
   - *Example:* If a new `gbnt stack deploy` command is added, provide the exact bash command and a sample `docker-compose.yml` that a user could copy and paste to test it.
3. **Expand with Best Practices:** 
   - Structure the README logically (e.g., Overview, Installation, Usage, Architecture, API Docs).
   - Use Markdown features effectively (code blocks with syntax highlighting, tables, alert blockquotes).
   - Ensure the tone is clear, professional, and aligns with the Roman Empire theme of the project where appropriate.
4. **API & CLI Documentation:** Keep a section for CLI commands and another for API endpoints. As the project grows, summarize them in the README and point to the Swagger UI (`http://localhost:4000/swagger/index.html`) for full API details.

## Actionable Trigger
If you modify code that changes how a user interacts with `gbnt` (CLI or API), your next immediate action must be to update the `README.md`.
