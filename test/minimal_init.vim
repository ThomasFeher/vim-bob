" bob plugin (the device under test)
set rtp+=..
runtime! plugin/vim-bob.vim

" test framework
set rtp+=plenary.nvim/
runtime! plugin/plenary.vim

" Ubuntu uses dash instead of sh, which seems to not like the workaround with
" the shellpipe option in s:DevImpl
set shell=/usr/bin/bash

" let g:bob_verbose = 1
