function backup-music
  rsync -rv --size-only --delete ~/Music/ 10.0.0.5:/mnt/SEAGATE/NAS/Music/
end
