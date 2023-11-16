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
