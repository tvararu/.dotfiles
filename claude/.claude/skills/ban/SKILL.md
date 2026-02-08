---
name: ban
description: Use when user wants to block a bash command via /ban "command" "explanation"
---

# Ban Command

Add a blocking rule to `~/.claude/hooks/bash-filter.sh` that intercepts a command and shows a message.

## Usage

```
/ban "bun test" "Use mise ts:test for TypeScript tests"
```

## Implementation

1. Parse the two quoted arguments from the invocation
2. Read `~/.claude/hooks/bash-filter.sh`
3. Check if a rule for this pattern already exists - if so, inform user and stop
4. Escape the banned command for bash regex (spaces become `\ `)
5. Add this line before the final `exit 0`:

```bash
[[ "$CMD" =~ ^<escaped-pattern> ]] && block '<message>'
```

6. Write the updated file

## Example

Input: `/ban "bun test" "Use mise ts:test for TypeScript tests"`

Adds:

```bash
[[ "$CMD" =~ ^bun\ test ]] && block 'Use mise ts:test for TypeScript tests'
```

## Errors

- If `~/.claude/hooks/bash-filter.sh` doesn't exist, set up hooks first
- If rule already exists for that pattern, inform user (don't duplicate)
