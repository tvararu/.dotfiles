# Defined in /tmp/fish.OgXR9I/eip.fish @ line 2
function eip
    set data (curl -s http://ip-api.com/json/ | jq -r 'if .status == "success" then [.query, (.countryCode // "XX")] | join(" ") else empty end')

    if test -z "$data"
        echo "Error: Failed to fetch data."
        return 1
    end

    set -l parts (string split " " $data)
    set -l ip $parts[1]
    set -l country $parts[2]

    if test "$country" = "XX"
        set flag "🌐"
    else
        set first (string lower (string sub -s 1 -l 1 $country))
        set second (string lower (string sub -s 2 -l 1 $country))
        set u1 (printf "%04X" (math 0x1F1E6 + (printf '%d' "'$first") - 97))
        set u2 (printf "%04X" (math 0x1F1E6 + (printf '%d' "'$second") - 97))
        set flag (printf "\U$u1\U$u2")
    end

    echo "$flag $ip"
end
