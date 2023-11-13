function toggle_prompt
  if set -q __prompt_state
    exec fish
    set -e __prompt_state
  else
    function fish_prompt
      echo "\$ "
    end
    set -g __prompt_state 1
  end
end
