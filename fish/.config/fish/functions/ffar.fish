function ffar --description 'Show video dimensions and aspect ratio'
    ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $argv[1] | awk -F, 'function gcd(a,b){return b?gcd(b,a%b):a} {g=gcd($1,$2); printf "%dx%d (%d:%d)\n", $1, $2, $1/g, $2/g}'
end
