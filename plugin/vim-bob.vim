function! s:Init()
	" TODO get list of configurations, we need a path configured by the user
	" where we can search for configurations
	let g:bob_package_list = system("bob ls")
	let g:bob_base_path = expand('%:p:h')
endfunction

function! s:GotoPackageSourceDir(...)
	if a:0 == 0
		execute "cd " . g:bob_base_path
	elseif a:0 == 1
		let l:dir = system("cd " . shellescape(g:bob_base_path) . "; bob query-path -f '{src}' " . a:1)
		if !empty(l:dir)
			execute "cd " . g:bob_base_path . "/" . l:dir
		else
			echom "package has no sources or is not checked out"
		endif
	else
		echom "BobGoto takes at most one parameter"
	endif
endfunction

function! s:CheckoutPackage(package)
	echo system("cd " . shellescape(g:bob_base_path) . "; bob dev --checkout-only " . a:package)
endfunction

function! s:Dev(package)
	echo system("cd " . shellescape(g:bob_base_path) . "; bob dev " . a:package)
endfunction

command! BobInit call s:Init()
command! -nargs=? BobGoto call s:GotoPackageSourceDir(<f-args>)
command! -nargs=1 BobCheckout call s:CheckoutPackage(<f-args>)
command! -nargs=1 BobDev call s:Dev(<f-args>)
