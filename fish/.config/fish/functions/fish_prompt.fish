function fish_prompt
  set -l last_status $status
  set -l cyan (set_color -o cyan)
  set -l yellow (set_color -o yellow)
  set -l red (set_color -o red)
  set -l blue (set_color -o blue)
  set -l green (set_color -o green)
  set -l normal (set_color normal)

  if test $last_status = 0
    set arrow "$green➜ "
  else
    set arrow "$red➜ "
  end
  set -l cwd $cyan(basename (prompt_pwd))

  echo -n -s $cwd ' ' $arrow $normal ' '
end
