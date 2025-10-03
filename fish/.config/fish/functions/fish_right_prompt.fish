function fish_right_prompt
    set -l branch_output (git branch --show-current 2>/dev/null)
    if test -n "$branch_output"
        set_color brblack
        echo -n "($branch_output)"
        set_color normal
    end
end
