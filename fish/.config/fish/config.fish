# Remove the newcomer fish greeting.
set fish_greeting ""
set -x EDITOR vim

abbr -a s sgpt --no-animation

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
