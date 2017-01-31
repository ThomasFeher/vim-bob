function! s:PackageComplete(ArgLead, CmdLine, CursorPos)
	return s:bob_package_list
endfunction

function! s:Init()
	let s:bob_package_list = system("bob ls")
	let s:bob_base_path = expand('%:p:h')
	let s:bob_config_path = get(g:, 'bob_config_path', "")
	let s:bob_config_path_abs = s:bob_base_path."/".s:bob_config_path
	let s:config_names = map(globpath(s:bob_config_path_abs, '*.yaml', 0, 1), 'fnamemodify(v:val, ":t:r")')
endfunction

function! s:GotoPackageSourceDir(...)
	if a:0 == 0
		execute "cd " . s:bob_base_path
	elseif a:0 == 1
		let l:dir = system("cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . a:1)
		if !empty(l:dir)
			execute "cd " . s:bob_base_path . "/" . l:dir
		else
			echom "package has no sources or is not checked out"
		endif
	else
		echom "BobGoto takes at most one parameter"
	endif
endfunction

function! s:CheckoutPackage(package)
	echo system("cd " . shellescape(s:bob_base_path) . "; bob dev --checkout-only " . a:package)
endfunction

function! s:Dev(package)
	echo system("cd " . shellescape(s:bob_base_path) . "; bob dev " . a:package)
endfunction

command! BobInit call s:Init()
command! -nargs=? -complete=custom,s:PackageComplete BobGoto call s:GotoPackageSourceDir(<f-args>)
command! -nargs=1 -complete=custom,s:PackageComplete BobCheckout call s:CheckoutPackage(<f-args>)
command! -nargs=1 -complete=custom,s:PackageComplete BobDev call s:Dev(<f-args>)
