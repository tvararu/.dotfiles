function stop-wivrn --description "Stop the WiVRn server on t1"
    # No idle timer for WiVRn, unlike Sunshine: a headset session is a
    # deliberate act with the headset on your face, so there is no equivalent
    # of a Moonlight client that disconnects and leaves the server holding
    # VRAM unnoticed. Stop it by hand when the session is over.
    set -l script '
        : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
        export XDG_RUNTIME_DIR

        if ! systemctl --user is-active --quiet wivrn; then
            echo "WiVRn is not running"
            exit 0
        fi

        systemctl --user stop wivrn || exit 1
        echo "WiVRn stopped"
    '

    if test (hostname) = t1
        printf '%s\n' $script | sh
    else
        printf '%s\n' $script | ssh t1 sh
    end
end
