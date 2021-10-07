" Auto-install vim-plug if it doesn't exist
if empty(glob('~/.vim/autoload/plug.vim'))
  silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin('~/.vim/plugged')
  " Shortcuts for commenting lines
  Plug 'tpope/vim-commentary'

  " Use * to search for what's selected in visual mode
  Plug 'nelstrom/vim-visual-star-search'

  " Fuzzy finder
  Plug '/usr/local/opt/fzf'

  " Nunjucks and jinja templates
  Plug 'lepture/vim-jinja'
call plug#end()

" Use syntax highlighting
syntax on

" Allow backspace to delete existing text
set backspace=2

" Use utf-8 encoding for everything
set encoding=utf-8

" Load filetype plugins
filetype plugin on

" Show line numbers in gutter
set number

" Use 2 space indentation
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab

" Show position of cursor in bottom right
set ruler

" Use previous line indentation when starting new line
set autoindent

" Remove netrw banner
let g:netrw_banner = 0

" Hide files instead of closing when navigating away with unsaved changes
set hidden

function! <SID>TrimWhitespaces()
  let _cursor_position = getpos(".")

  " Trim trailing whitespace on every line
  :silent! %s/\s\+$//e
  " Trim blank lines at end of file
  :silent! %s#\($\n\s*\)\+\%$##

  call setpos(".", _cursor_position)
endfunction

" Automatically remove trailing whitespace on write for any file type (*)
autocmd BufWritePre * :call <SID>TrimWhitespaces()

" Use search highlighting
set hlsearch

" Mute search highlighting with <C-l>
nnoremap <silent> <C-l> :<C-u>nohlsearch<CR><C-l>
