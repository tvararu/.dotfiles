---
name: mise
description: Use when adding, modifying, or documenting mise tasks in any project — covers inline TOML tasks, file-based shell tasks, argument handling, and CLAUDE.md documentation conventions
---

# Mise Task Conventions

See `reference.md` for available mise features and syntax.

## Inline vs File Tasks

- **Inline TOML** `[tasks.X]` — ≤3 lines of shell, no conditionals, no helper functions
- **File task** in `.mise/tasks/` — anything more complex

## File Task Shell

- Shebang: `#!/usr/bin/env bash`
- Always `set -euo pipefail` (or `set -e` for trivial scripts)
- Never fish scripts — bash only

## Naming

- Kebab-case file names: `bundle-models`, `setup-modules`
- Colon namespaces via subdirectories: `.mise/tasks/ops/build` → `mise ops:build`
- In TOML: `[tasks."ops:build"]`, `[tasks."db:restore"]`
- Standard verb forms: `build`, `test`, `format` — not `run-tests` or `formatting`
- Prefer `db:` over `pg:` for database tasks

## Arguments

- Inline TOML: `usage` field with usage spec, access via `$usage_name`
- File tasks: positional `$1`/`$2` with defaults via `${1:-default}`

## Standard Task Names

| Task                    | Purpose                                        |
| ----------------------- | ---------------------------------------------- |
| `bundle`                | Install dependencies                           |
| `ci`                    | All checks (format + typecheck + test)         |
| `build`                 | Compile/package                                |
| `test`                  | Run tests                                      |
| `test:coverage`         | Tests with coverage                            |
| `typecheck`             | Static type checking                           |
| `format` / `format:fix` | Check / fix formatting                         |
| `lint` / `lint:fix`     | Check / fix linting                            |
| `dev`                   | Development server                             |
| `start`                 | Start the app                                  |
| `release`               | Cut a version (tag, changelog, GitHub Release) |
| `deploy`                | Deploy to production                           |
| `worktree`              | Create git worktree for feature work           |
| `health`                | Check runtime dependencies                     |

Domain-specific tasks get prefixed: `ops:*`, `db:*`, etc.

## CLAUDE.md Documentation

When adding tasks, update the project's CLAUDE.md Commands section:

````markdown
## Commands

Always use mise tasks instead of direct <tool> commands:

```bash
mise build                   # Compile to binary
mise test                    # Run tests
mise ci                      # Run all checks (typecheck + test + format)
mise db:restore              # Restore latest database backup
```
````

```

- One `mise <task>` per line with inline `#` comment
- Align comments with spaces
- Group related tasks (build/test, then ops, then domain-specific)
- Include "Always use mise tasks instead of direct X commands" preamble (X = project's package manager)
- If `mise ci` exists, add: "Always run `mise ci` after completing a piece of work."
```
