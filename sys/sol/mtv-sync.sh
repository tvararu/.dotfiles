#!/bin/bash
# Pull the MTV YouTube playlist into the Jellyfin MTV library. Same layout as
# the manual get.sh that built the folder: flat "<title>.mkv" with a
# .info.json, a .jpg and an .nfo. get.sh asked for mp4+m4a only, which caps
# many videos at 1080p H.264; the mkv takes any codec, so yt-dlp's default
# format choice is used instead, as on t1.
set -uo pipefail

# Without ffmpeg, yt-dlp still downloads but cannot merge or convert, and
# leaves unmerged .f137.mp4/.m4a pairs in the library.
command -v ffmpeg >/dev/null || { echo "ffmpeg not installed" >&2; exit 1; }

state="$HOME/srv/mtv-sync"
mkdir -p "$state"
cd /mnt/pool/MTV

# The archive is the only state. It lives outside the library so Jellyfin
# never sees it; it was seeded from the ids in the existing .info.json files.
# Writing playlist metafiles is yt-dlp's default and would put a phantom
# entry named after the playlist in the library.
/usr/bin/yt-dlp \
    --download-archive "$state/archive.txt" \
    --add-metadata --ignore-errors --force-ipv4 \
    --write-thumbnail --write-info-json --no-write-playlist-metafiles \
    --output '%(title)s.%(ext)s' --merge-output-format mkv \
    --embed-thumbnail --convert-thumbnails jpg \
    "$MTV_PLAYLIST_URL"
status=$?

# Jellyfin reads the .nfo, not the .info.json. Without -w, existing .nfo files
# are kept. ytdl-nfo 0.3.0 imports pkg_resources, which setuptools 81 removed,
# and the old venv in the folder broke when sol moved past Python 3.12.
"$HOME/.local/share/mise/installs/uv/latest/.mise-bins/uvx" --python 3.12 \
    --with 'setuptools<81' --from ytdl-nfo==0.3.0 ytdl-nfo . || status=1

exit $status
