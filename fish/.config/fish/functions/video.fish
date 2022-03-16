function video
ffmpeg \
-f x11grab \
-s (xdpyinfo | grep dimensions | awk '{print $2;}') \
-i "$DISPLAY" \
-c:v libx264 -qp 0 -r 30 \
$HOME/downloads/video-(date '+%y%m%d-%H%M-%S').mp4
end
