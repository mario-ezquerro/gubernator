# Gubernator Testing Workflow

This document outlines the standard procedure AI agents and developers should follow to ensure code quality in Gubernator.

## 1. Local Testing

Before submitting or suggesting any changes, run the full test suite locally:

```bash
go test -v ./...
```

## 2. Writing Tests

When introducing new functionality, ensure adequate coverage:
- **API Endpoints (`internal/api`)**: Use `httptest` and Gin's `TestMode`. Always inject an in-memory SQLite database (`file::memory:?cache=shared`) to avoid polluting disk state.
- **Database Logic (`internal/db`)**: Validate GORM queries against the in-memory database.
- **Core Engine (`internal/docker`)**: Mock or wrap OS execution commands if necessary to prevent test-suite dependency on a live Docker daemon (unless running integration tests).

## 3. Continuous Integration

Every push or pull request to the `main` branch automatically triggers the `.github/workflows/test.yml` GitHub Action, running tests on an isolated Ubuntu runner.

**MANDATORY RULE:** Never merge code that breaks the CI pipeline. Ensure you run `go mod tidy` and fix imports before committing.
