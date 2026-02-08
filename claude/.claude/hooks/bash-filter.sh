#!/bin/bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

block() {
  echo "$1" >&2
  exit 2
}

[[ "$CMD" =~ ^mise\ run\  ]] && block 'Use "mise TASK" not "mise run TASK"'
[[ "$CMD" =~ git\ .*-[cC]\  ]] && block 'Use "git" directly, cd if you must'
[[ "$CMD" =~ ^grep ]] && block 'Use the Grep tool instead of the grep command'
[[ "$CMD" =~ ^find ]] && block 'Use the Glob tool instead of the find command'
[[ "$CMD" =~ ^cat ]] && block 'Use the Read/Write/Edit tools instead of cat'
[[ "$CMD" =~ ^bun\ run\  ]] && block 'Use mise to run package.json scripts instead of bun run'
[[ "$CMD" =~ ^bunx\  ]] && block 'Use mise to run package.json scripts instead of bunx'
[[ "$CMD" =~ ^python3\ -c ]] && block 'Write scripts to tmp and run via uv instead'
[[ "$CMD" =~ ^node\ -e ]] && block 'Write scripts to tmp and run via node'
[[ "$CMD" =~ ^bun\ -e ]] && block 'Write scripts to tmp and run via bun'

exit 0
