set fish_greeting ""
set -x EDITOR nvim

# SSH agent
if test (uname) = Darwin
    # Secretive (macOS)
    set -x SSH_AUTH_SOCK ~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh
else
    # ssh-tpm-agent (Linux)
    set -x SSH_AUTH_SOCK $XDG_RUNTIME_DIR/ssh-tpm-agent.sock
end

# z
zoxide init fish | source

# Orbstack (macOS only)
test (uname) = Darwin; and source ~/.orbstack/shell/init2.fish 2>/dev/null

# Abbreviations for day to day commands
abbr --add -- l 'ls'
abbr --add -- led 'ledger -f current.ledger --price-db prices.db --exchange £ --pedantic'
abbr --add -- ll 'ls -lah'
abbr --add -- lt 'lsd --tree'
abbr --add -- p 'ping 1.1'
abbr --add -- r 'rails'
abbr --add -- t 'tmux'
abbr --add -- v 'nvim'
abbr --add -- os 'overmind start --daemonize --procfile Procfile.dev'
abbr --add -- oc 'overmind connect'
abbr --add -- oq 'overmind quit'
abbr --add -- mc 'mise ci'
abbr --add -- ms 'mise setup'
abbr --add -- md 'mise deploy'
abbr --add -- mds 'mise deploy:setup'
abbr --add -- bbb 'brew doctor && brew update && brew upgrade'
abbr --add -- cc 'claude --dangerously-skip-permissions --continue'
abbr --add -- zcc 'claude --settings ~/.claude/settings.json.zai --dangerously-skip-permissions --continue'

# git abbreviations, stolen from oh-my-zsh some time ago
abbr --add -- ga 'git add --all .'
abbr --add -- gap 'git add --patch'
abbr --add -- gb 'git branch'
abbr --add -- gbd 'git branch -D'
abbr --add -- gbis 'git bisect'
abbr --add -- gcach 'git commit --amend -C HEAD'
abbr --add -- gcam 'git commit --amend'
abbr --add -- gcm 'git commit'
abbr --add -- gcmsg 'git commit -m'
abbr --add -- gco 'git checkout'
abbr --add -- gcob 'git checkout -b'
abbr --add -- gd 'git diff'
abbr --add -- gda 'git diff --cached'
abbr --add -- gdhh 'git diff HEAD^ HEAD'
abbr --add -- gdm 'git diff main'
abbr --add -- gl 'git pull --rebase'
abbr --add -- glo 'git log --oneline --decorate --color --graph'
abbr --add -- gp 'git push'
abbr --add -- gpf 'git push --force-with-lease origin (git rev-parse --abbrev-ref HEAD)'
abbr --add -- gpu 'git push -u origin (git rev-parse --abbrev-ref HEAD)'
abbr --add -- grb 'git rebase'
abbr --add -- grbc 'git rebase --continue'
abbr --add -- grbima 'git rebase -i main --autosquash'
abbr --add -- grhh 'git reset --hard HEAD'
abbr --add -- grs 'git restore --staged .'
abbr --add -- gsp 'git stash pop'
abbr --add -- gst 'git status'
abbr --add -- gs 'git switch'

# LM Studio CLI (lms)
test -d ~/.cache/lm-studio/bin; and set -gx PATH $PATH ~/.cache/lm-studio/bin
