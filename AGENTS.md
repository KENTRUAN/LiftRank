# Repository workflow

- Create a new `codex/` feature branch before making changes for a new task.
- Never commit or push directly to `main`. Do not merge into `main` without an explicit user request.
- Keep `project.yml` and the generated Xcode project in sync (`xcodegen generate`).
- Run `python3 scripts/lint.py --swift`, appropriate XCTest coverage, and backend checks for changed behavior.
- Cloud secrets and local service configuration must stay out of Git. Use the examples in `backend/README.md`.
