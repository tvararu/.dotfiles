#!/bin/sh
# Give each YouTube channel directory a poster.jpg, so Jellyfin has series
# artwork for it.
#
# This exists because the Jellyfin YoutubeMetadata plugin's *remote* provider —
# the only thing that fetched channel art — shells out to a binary named
# youtube-dl, which is dead upstream and absent from the container. Rather than
# install a second downloader in there with no PO token provider, the channel
# avatar is fetched with the same yt-dlp the sync already uses and written as
# poster.jpg, which Jellyfin reads natively without any plugin involved.
#
# Cheap to re-run: a directory that already has a poster is skipped, so the
# steady state is one playlist metadata fetch per new channel and nothing else.
set -eu

LIB=/mnt/aux/media/youtube
YTDLP=/home/deity/.local/bin/yt-dlp
CACHE=/mnt/aux/yt-queue/cache

for dir in "$LIB"/*/; do
    [ -d "$dir" ] || continue
    [ -e "$dir/poster.jpg" ] && continue

    # Every video yt-dlp downloads records its channel_url, so the channel is
    # derivable from what is already on disk — no separate lookup or list of
    # channels to keep in sync with the library.
    info=$(find "$dir" -maxdepth 1 -name '*.info.json' -print -quit)
    [ -n "$info" ] || continue
    url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("channel_url") or "")' "$info")
    [ -n "$url" ] || continue

    # --playlist-items 0 fetches the channel's own thumbnail without touching a
    # single video. --convert-thumbnails pins the extension, since the avatar
    # arrives as webp for some channels and Jellyfin looks for poster.jpg.
    # Failure is non-fatal: one unreachable channel must not stop the rest.
    "$YTDLP" --skip-download --write-thumbnail --playlist-items 0 \
        --convert-thumbnails jpg \
        --no-write-info-json --no-write-subs \
        --cache-dir "$CACHE" \
        -o "${dir}poster.%(ext)s" "$url" || echo "poster fetch failed: $dir" >&2
done
