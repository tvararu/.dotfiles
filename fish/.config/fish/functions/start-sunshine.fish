function start-sunshine --description "Start Sunshine on t1 for a Moonlight session"
    # Idempotent twice over: the is-active check short-circuits, and `systemctl
    # start` is itself a no-op on a running unit, so a race cannot double-start.
    #
    # Sunshine stops itself after an hour with no session to free ~513 MiB of
    # VRAM (see sys/t1/maintenance.md, "Idle VRAM reclaim"), which is why this
    # exists. One `sh` snippet piped over ssh rather than several ssh calls, so
    # the readiness wait costs one round trip instead of thirty.
    set -l script '
        unit=app-dev.lizardbyte.app.Sunshine.service

        # pam_systemd sets this on an ssh login and linger keeps user@1000 alive
        # with no session open, so this is belt-and-braces — but without it
        # `systemctl --user` cannot find the session bus and every call fails.
        : "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
        export XDG_RUNTIME_DIR

        if systemctl --user is-active --quiet "$unit"; then
            echo "Sunshine is already running"
            exit 0
        fi

        systemctl --user start "$unit" || exit 1

        # systemctl returns once the unit is active, but Sunshine binds its
        # listeners a moment after that. Wait for 47989 so Moonlight finds the
        # host on its first poll instead of showing it offline.
        i=0
        while [ $i -lt 30 ]; do
            if ss -lnt | grep -q ":47989 "; then
                echo "Sunshine is ready"
                exit 0
            fi
            sleep 0.5
            i=$((i + 1))
        done

        echo "Sunshine started but port 47989 never opened" >&2
        exit 1
    '

    # The dotfiles are stowed on t1 as well, so skip the hop when already there.
    if test (hostname) = t1
        printf '%s\n' $script | sh
    else
        # Piped rather than passed as an argument: ssh re-parses its command
        # through the remote shell, which would mangle the quoting above.
        printf '%s\n' $script | ssh t1 sh
    end
end
