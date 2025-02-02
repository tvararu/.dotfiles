function yt-dlp
  docker run --rm -v "$PWD:/downloads" ghcr.io/jim60105/yt-dlp \
    -o "/downloads/%(title)s.%(ext)s" \
    $argv
end
