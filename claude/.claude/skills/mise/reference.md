# Mise Task Reference

Condensed from https://mise.jdx.dev/tasks/

## TOML Task Fields

```toml
[tasks.build]
run = "cargo build"                    # string, array of strings, or mixed array
run = ["cargo build", "cargo test"]    # array runs serially
run = [
  { task = "setup" },                  # run a task
  { tasks = ["lint", "test"] },        # run tasks in parallel
  "echo done",                         # then a shell command
]
description = "Build the project"
alias = "b"                            # or ["b", "compile"]
depends = ["setup", "codegen"]         # run before this task
depends = ["build --release"]          # with inline args
depends = [{ task = "setup", env = { NODE_ENV = "test" } }]  # object syntax
depends_post = ["cleanup"]             # run after this task
wait_for = ["setup"]                   # wait if running, don't trigger
env = { RUST_BACKTRACE = "1" }         # task-specific env (not passed to depends)
dir = "{{cwd}}"                        # working directory (default: config root)
sources = ["src/**/*.ts", "package.json"]
outputs = ["dist/app"]                 # or { auto = true } for hash-based tracking
usage = 'arg "<name>"'                 # argument spec (see Usage Spec below)
confirm = "Delete everything?"         # prompt before running
shell = "bash -c"                      # override default shell
raw = true                             # direct stdin/stdout passthrough, single-threaded
hide = true                            # hide from task list
quiet = true                           # suppress mise's command display
silent = true                          # suppress all output ("stdout" or "stderr" for partial)
vars = { key = "value" }               # task-local vars, access via {{vars.key}}
file = "scripts/build.sh"              # external script (local or remote URL)
```

## File Task Directives

File tasks are executable scripts in `.mise/tasks/`. Subdirectories create
namespaces: `.mise/tasks/ops/build` → `mise ops:build`.

```bash
#!/usr/bin/env bash
#MISE description="Build the project"
#MISE alias="b"
#MISE depends=["setup", "codegen"]
#MISE depends_post=["cleanup"]
#MISE wait_for=["setup"]
#MISE sources=["src/**/*.ts"]
#MISE outputs=["dist/app"]
#MISE env={RUST_BACKTRACE="1"}
#MISE dir="{{cwd}}"
#MISE raw=true
#MISE hide=true
#MISE quiet=true
#MISE silent=true
#MISE shell="bash -c"
#MISE tools={rust="1.85"}
set -euo pipefail
```

If a formatter inserts a space after `#`, use `# [MISE]` instead of `#MISE`.

## Usage Spec Syntax

Defined via `usage` field (TOML) or `#USAGE` directive (file tasks). Values
become `$usage_<name>` env vars (hyphens → underscores).

### Positional Arguments

```
arg "<name>"                           # required
arg "[name]"                           # optional
arg "[name]" default="value"           # with default
arg "<name>" help="Description"        # help text
arg "<name>" env="ENV_VAR"             # backed by env var
arg "<name>" { choices "a" "b" "c" }   # restricted values
arg "[files]" var=#true                # variadic (0+)
arg "<files>" var=#true                # variadic (1+)
arg "<files>" var=#true var_min=2 var_max=5
```

Special names: `<file>` completes filenames, `<dir>` completes directories.

### Flags

```
flag "-f --force"                      # boolean (short + long)
flag "--output <file>"                 # with value
flag "--color <when>" { choices "auto" "always" "never" }
flag "--format" default="json"
flag "-v --verbose" count=#true        # counting (-vvv = 3)
flag "--color" negate="--no-color" default=#true
flag "--region" env="AWS_REGION"       # env var backing
flag "--debug" hide=#true
```

### Completions

```
complete "plugin" run="mise plugins ls"
```

### Priority

CLI argument > environment variable > default value.

### Accessing in Scripts

Shell: `$usage_name`, `$usage_force`
Templates: `{{usage.name}}`, `{{usage.force}}`
Variadic in bash: `eval "files=($usage_files)"`

## Sources/Outputs (Change Detection)

Task skipped when oldest output is newer than newest source. The task file
itself is auto-included as a source.

When `sources` is set but `outputs` is not, defaults to `{ auto = true }` which
uses an internal hash file at `~/.local/state/mise/task-outputs/<hash>`.

Force run: `mise run --force <task>`.

## Running Tasks

```bash
mise run <task>              # standard
mise <task>                  # shorthand (avoid in scripts — shadowing risk)
mise run build ::: test      # parallel tasks (separate args with :::)
mise run --force <task>      # skip freshness check
mise run --jobs 8 <task>     # max parallel tasks (default 4)
mise run --timings <task>    # show elapsed time per task
mise run --dry-run <task>    # preview without executing
mise watch <task>            # re-run on source changes (requires watchexec)
```

## Auto-Injected Environment Variables

| Variable            | Value                                  |
| ------------------- | -------------------------------------- |
| `MISE_ORIGINAL_CWD` | Directory where `mise run` was invoked |
| `MISE_CONFIG_ROOT`  | Directory containing `mise.toml`       |
| `MISE_PROJECT_ROOT` | Project root directory                 |
| `MISE_TASK_NAME`    | Name of the executing task             |
| `MISE_TASK_DIR`     | Directory containing the task script   |
| `MISE_TASK_FILE`    | Full path to the task script           |

## Task Config

```toml
[task_config]
dir = "{{cwd}}"                        # default dir for all tasks
includes = ["tasks.toml", "mise-tasks"] # additional task sources
```
