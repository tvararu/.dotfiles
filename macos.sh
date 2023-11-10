#!/bin/sh

### Defaults
echo "\n Setting up macOS.\n"

echo " Setting up system and application defaults."

echo " Asking for the administrator password upfront."
sudo -v

# Keep-alive: update existing `sudo` time stamp until `.osx` has finished.
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

echo "\n Global changes."

echo "- Expand save panel by default."
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

echo "- Expand print panel by default."
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

echo "- Enable subpixel font rendering on non-Apple LCDs."
# Reference: https://github.com/kevinSuttle/macOS-Defaults/issues/17#issuecomment-266633501
defaults write NSGlobalDomain AppleFontSmoothing -int 1

echo "\n Menu bar."

echo "- Customize the clock look."
defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM  HH:mm:ss"

echo "- Change the battery to show the percentage."
defaults write com.apple.menuextra.battery ShowPercent -string "YES"

echo "\n Keyboard."

echo "- Set Keyboard > Key Repeat to be the fastest possible from System Preferences."
defaults write NSGlobalDomain KeyRepeat -integer 2

echo "- Set Keyboard > Delay Until Repeat to be the fastest possible from System Preferences."
defaults write NSGlobalDomain InitialKeyRepeat -integer 15

echo "\n Dock."

echo "- Don't show recent applications in Dock."
defaults write com.apple.dock show-recents -bool false

echo "- Restarting the Dock."
killall Dock

echo "\n Finder."

echo "- Set default path to HOME directory."
defaults write com.apple.finder NewWindowTarget -string "PfLo"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/"

echo "- When performing a search, search the current folder by default."
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

echo "- Avoid creating .DS_Store files on network volumes."
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true

echo "- Enable snap-to-grid for icons on the desktop and in other icon views."
/usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist
/usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" ~/Library/Preferences/com.apple.finder.plist

echo "- Use list view in all Finder windows by default."
# Four-letter codes for all views: `icnv`, `Nlsv`, `clmv`, `Flwv`.
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"

echo "- Expand the following File Info panes: General, Open with, and Sharing & Permissions."
defaults write com.apple.finder FXInfoPanesExpanded -dict \
	General -bool true \
	OpenWith -bool true \
	Privileges -bool true

echo "- Hide icons for hard drives, servers, and removable media on the desktop."
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowMountedServersOnDesktop -bool false
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false

echo "\n Defaults done."

### Homebrew
# Install Homebrew if it's not already present.
if command -v brew >/dev/null 2>&1; then
  echo " Homebrew already exists. Skipping install.\n"
else
  echo " Installing Homebrew. (http://brew.sh)"
  echo " Please install the command line tools when prompted, and press 'enter' after it's done.\n"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
  brew doctor
  echo " Homebrew successfully installed.\n"
fi

echo " brew update to make sure we’re using the latest Homebrew."
brew update

echo "\n brew upgrade any already-installed formulae."
brew upgrade

echo "\n brew tap homebrew/cask-fonts to add fonts to brew."
brew tap homebrew/cask-fonts

brew install stow --quiet

mkdir ~/.ssh ~/.vim ~/.gnupg

stow -R fish git gpg homebrew ssh tmux vim

echo "\n brew bundling."
brew bundle --global

echo "\n Removing outdated versions from the cellar."
brew cleanup

if ! grep --quiet $(which fish) /etc/shells; then
  echo "\n hanging default shell to fish."
  sudo sh -c "echo $(which fish) >> /etc/shells"
  chsh -s $(which fish)
fi

echo " Successfully installed all brew apps.\n"

echo " Homebrew install done.\n"

echo " All done! Enjoy.\n"
