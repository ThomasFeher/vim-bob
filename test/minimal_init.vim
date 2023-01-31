" bob plugin (the device under test)
set rtp+=..
runtime! plugin/vim-bob.vim

" test framework
set rtp+=plenary.nvim/
runtime! plugin/plenary.vim

" let g:bob_verbose = 1
