#!/bin/sh

sudo sed -i "s@#EnableAUR@EnableAUR@" /etc/pamac.conf
sudo sed -i "s@#CheckAURUpdates@CheckAURUpdates@" /etc/pamac.conf
sudo sed -i "s@#CheckAURVCSUpdates@CheckAURVCSUpdates@" /etc/pamac.conf
sudo sed -i "s@#NoUpdateHideIcon@RemoveUnrequiredDeps@" /etc/pamac.conf
sudo sed -i "s@#DownloadUpdates@DownloadUpdates@" /etc/pamac.conf
sudo sed -i "s@#RemoveUnrequiredDeps@RemoveUnrequiredDeps@" /etc/pamac.conf
sudo sed -i "s@#EnableSnap@EnableSnap@" /etc/pamac.conf
sudo sed -i "s@#EnableFlatpak@EnableFlatpak@" /etc/pamac.conf

pamac install \
  asdf \
  fish \
  vim
