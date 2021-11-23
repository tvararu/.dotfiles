let data_dir = has('nvim') ? stdpath('data') . '/site' : '~/.vim'
if empty(glob(data_dir . '/autoload/plug.vim'))
  silent execute '!curl -fLo '.data_dir.'/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin('~/.vim/plugged')
  Plug 'tpope/vim-sensible'         " Sensible defaults
  Plug 'nekonako/xresources-nvim'   " Load Xresources colours
  Plug 'tpope/vim-commentary'       " Shortcuts for commenting lines
  Plug 'itchyny/lightline.vim'      " Light and configurable statusline
  Plug 'lepture/vim-jinja'          " .njk support
  Plug 'jxnblk/vim-mdx-js'          " .mdx support
call plug#end()

colorscheme xresources              " Use a color scheme based on Xresources
set number                          " Show line numbers in gutter
set cc=80                           " Set an 80 width column border
set hidden                          " Allow navigating away with unsaved changes

set tabstop=2                       " Set tab to 2 spaces
set shiftwidth=2                    " Shift by 2 spaces when using << >>
set softtabstop=2                   " Move forward 2 spaces with pressing tab
set expandtab                       " Use space instead of tabs

let g:netrw_banner = 0              " Remove netrw banner
let mapleader ="\<Space>"           " Map space bar as the leader key

set noshowmode                      " Don't show mode below statusline
let g:lightline = { 'colorscheme': 'ayu_dark', }

function! <SID>TrimWhitespaces()
  let _cursor_position = getpos(".")

  :silent! %s/\s\+$//e              " Trim trailing whitespace on every line
  :silent! %s#\($\n\s*\)\+\%$##     " Trim blank lines at end of file

  call setpos(".", _cursor_position)
endfunction

" Automatically remove trailing whitespace on write for any file type (*)
autocmd BufWritePre * :call <SID>TrimWhitespaces()
