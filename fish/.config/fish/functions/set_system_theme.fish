function set_system_theme
    type -q defaults; or return

    set -l macos_mode (defaults read -g AppleInterfaceStyle 2>/dev/null)
    set -l detected_mode (test -n "$macos_mode" && echo "dark" || echo "light")

    if not set -q current_theme; or test "$detected_mode" != "$current_theme"
        if test "$detected_mode" = "dark"
            set_dark_theme
        else
            set_light_theme
        end
        set -g current_theme $detected_mode
    end
end
