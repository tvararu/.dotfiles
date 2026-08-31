function start-wivrn --description "Start the WiVRn server on t1 for a headset session"
    # The dashboard is only a frontend: it spawns wivrn-server and kills it on
    # exit, which is why closing the window drops the headset. The packaged
    # user unit runs the same binary without a GUI, so this starts that instead
    # and leaves nothing on screen.
    #
    # Not enabled at boot — VR is occasional and an idle server holds an
    # encoder context. Same reasoning as start-sunshine.
    set -l script '
        : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
        export XDG_RUNTIME_DIR

        if systemctl --user is-active --quiet wivrn; then
            echo "WiVRn is already running"
            exit 0
        fi

        # A dashboard-spawned server is not the unit, so is-active misses it.
        # Starting a second one is worse than doing nothing: each server
        # unlinks /run/user/1000/wivrn/comp_ipc as "stale" on startup and again
        # on exit, so the survivor listens on a socket with no path left. The
        # headset still connects over the network, but every local OpenXR app
        # dies with XR_ERROR_RUNTIME_UNAVAILABLE.
        if pgrep -x wivrn-server >/dev/null; then
            echo "wivrn-server is already running outside the unit (dashboard?)" >&2
            exit 1
        fi

        systemctl --user start wivrn || exit 1

        # systemctl returns before the listener is up; wait for 9757 so the
        # headset finds the server on its first poll.
        i=0
        while [ $i -lt 30 ]; do
            if ss -lnt | grep -q ":9757 "; then
                echo "WiVRn is ready"
                exit 0
            fi
            sleep 0.5
            i=$((i + 1))
        done

        echo "WiVRn started but port 9757 never opened" >&2
        exit 1
    '

    if test (hostname) = t1
        printf '%s\n' $script | sh
    else
        printf '%s\n' $script | ssh t1 sh
    end
end
