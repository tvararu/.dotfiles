# Remove the newcomer fish greeting.
set fish_greeting ""
set -x EDITOR vim

# Arch asdf config
if test -e /opt/asdf-vm/asdf.fish
  source /opt/asdf-vm/asdf.fish
end

# macOS asdf config
if test -e /usr/local/opt/asdf/asdf.fish
  source /usr/local/opt/asdf/asdf.fish
end

fish_ssh_agent
