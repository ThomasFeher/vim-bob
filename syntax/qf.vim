syn match qfBobPackageName "|| >> .*$"
syn match qfBobAttic "||    ATTIC.*$"
syn match qfBobBuild "||    BUILD.*$"
syn match qfBobCheckout "||    CHECKOUT.*$"
syn match qfBobPackage "||    PACKAGE.*$"
syn match qfBobPrune "||    PRUNE.*$"
syn match qfBobResult "|| Build result is in .*$"

hi def link qfBobPackageName Title

hi def link qfBobBuild vimCommand
hi def link qfBobCheckout vimCommand
hi def link qfBobPackage vimCommand

hi def link qfBobAttic ErrorMsg
hi def link qfBobPrune ErrorMsg

hi def link qfBobResult Statement
