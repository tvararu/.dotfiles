function fish_prompt
    set_system_theme

    set -l last_status $status
    set -l color
    if test $last_status -eq 0
        set color (set_color green)
    else
        set color (set_color red)
    end
    echo $color'$ '(set_color normal)
end
