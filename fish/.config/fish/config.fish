set fish_greeting ""
set -x EDITOR vim

fish_add_path ~/.bin

# Arch asdf config
if test -e /opt/asdf-vm/asdf.fish
  source /opt/asdf-vm/asdf.fish
end

# macOS asdf config
if test -e /opt/homebrew/opt/asdf/libexec/asdf.fish
  source /opt/homebrew/opt/asdf/libexec/asdf.fish
end

fish_ssh_agent

zoxide init fish | source

abbr -a -- be 'bin/bundle exec'
abbr -a -- l 'ls'
abbr -a -- led 'ledger -f current.ledger --price-db prices.db --exchange £ --pedantic'
abbr -a -- ll 'ls -lah'
abbr -a -- lt 'lsd --tree'
abbr -a -- p 'ping 1.1'
abbr -a -- r 'rails'
abbr -a -- t 'tmux'
abbr -a -- v 'nvim'

abbr -a -- ga 'git add --all .'
abbr -a -- gap 'git add --patch'
abbr -a -- gb 'git branch'
abbr -a -- gbd 'git branch -D'
abbr -a -- gbis 'git bisect'
abbr -a -- gcach 'git commit --amend -C HEAD'
abbr -a -- gcam 'git commit --amend'
abbr -a -- gcm 'git commit'
abbr -a -- gcmsg 'git commit -m'
abbr -a -- gco 'git checkout'
abbr -a -- gcob 'git checkout -b'
abbr -a -- gd 'git diff'
abbr -a -- gda 'git diff --cached'
abbr -a -- gdhh 'git diff HEAD^ HEAD'
abbr -a -- gdm 'git diff main'
abbr -a -- gl 'git pull --rebase'
abbr -a -- glo 'git log --oneline --decorate --color --graph'
abbr -a -- gp 'git push'
abbr -a -- gpf 'git push --force-with-lease origin (git rev-parse --abbrev-ref HEAD)'
abbr -a -- gphm 'git push heroku main'
abbr -a -- gphom 'git push && git push heroku'
abbr -a -- gpu 'git push -u origin (git rev-parse --abbrev-ref HEAD)'
abbr -a -- grb 'git rebase'
abbr -a -- grbc 'git rebase --continue'
abbr -a -- grbima 'git rebase -i main --autosquash'
abbr -a -- grhh 'git reset --hard HEAD'
abbr -a -- grs 'git restore --staged .'
abbr -a -- gsp 'git stash pop'
abbr -a -- gst 'git status'
