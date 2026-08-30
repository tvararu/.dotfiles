function yt-dlp
    set -l conf "$HOME/.config/yt-dlp/config"
    set -l opts -v "$PWD:/download"
    test -f $conf; and set -a opts -v "$conf:/etc/yt-dlp.conf:ro"
    docker run --rm --user (id -u):(id -g) $opts ghcr.io/jim60105/yt-dlp $argv
end
