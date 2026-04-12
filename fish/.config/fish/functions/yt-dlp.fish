function yt-dlp
  docker run --rm \
    --user (id -u):(id -g) \
    -v "$PWD:/downloads" \
    -v "$HOME/.config/yt-dlp/config:/etc/yt-dlp.conf:ro" \
    ghcr.io/jim60105/yt-dlp \
    $argv
end
