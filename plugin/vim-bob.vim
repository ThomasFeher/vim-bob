function! s:Init()
	" TODO get list of configurations, we need a path configured by the user
	" where we can search for configurations
	let g:bob_package_list = system("bob ls")
	let g:bob_base_path = expand('%:p:h')
endfunction

function! s:GotoPackageSourceDir(package)
	let l:dir = system("cd " . shellescape(g:bob_base_path) . "; bob query-path -f '{src}' " . a:package)
	echo l:dir
	if l:dir
		cd l:dir
	else
		echom "package has no sources or is not checked out"
	endif
endfunction

function! s:CheckoutPackage(package)
	echo system("cd " . shellescape(g:bob_base_path) . "; bob dev --checkout-only " . a:package)
endfunction

function! s:Dev(package)
	echo system("cd " . shellescape(g:bob_base_path) . "; bob dev " . a:package)
endfunction

command! BobInit call s:Init()
command! -nargs=1 BobGoto call s:GotoPackageSourceDir(<q-args>)
command! -nargs=1 BobCheckout call s:CheckoutPackage(<q-args>)
command! -nargs=1 BobDev call s:Dev(<q-args>)
