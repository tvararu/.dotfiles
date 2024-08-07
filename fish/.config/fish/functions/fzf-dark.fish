# From https://raw.githubusercontent.com/base16-project/base16-fzf/main/fish/base16-ayu-dark.fish
function fzf-dark
  # Base16 Ayu Dark
  # Author: Khue Nguyen &lt;Z5483Y@gmail.com&gt;

  set -l color00 '#0f1419'
  set -l color01 '#131721'
  set -l color02 '#272d38'
  set -l color03 '#3e4b59'
  set -l color04 '#bfbdb6'
  set -l color05 '#e6e1cf'
  set -l color06 '#e6e1cf'
  set -l color07 '#f3f4f5'
  set -l color08 '#f07178'
  set -l color09 '#ff8f40'
  set -l color0A '#ffb454'
  set -l color0B '#b8cc52'
  set -l color0C '#95e6cb'
  set -l color0D '#59c2ff'
  set -l color0E '#d2a6ff'
  set -l color0F '#e6b673'

  set -l FZF_NON_COLOR_OPTS

  for arg in (echo $FZF_DEFAULT_OPTS | tr " " "\n")
      if not string match -q -- "--color*" $arg
          set -a FZF_NON_COLOR_OPTS $arg
      end
  end

  set -Ux FZF_DEFAULT_OPTS "$FZF_NON_COLOR_OPTS"\
  " --color=bg+:$color01,bg:$color00,spinner:$color0C,hl:$color0D"\
  " --color=fg:$color04,header:$color0D,info:$color0A,pointer:$color0C"\
  " --color=marker:$color0C,fg+:$color06,prompt:$color0A,hl+:$color0D"
end
