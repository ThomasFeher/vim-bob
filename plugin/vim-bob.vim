let s:is_initialized = 0

function! s:Init()
	let s:bob_package_list = system("bob ls")
	let s:bob_base_path = getcwd()
	let s:bob_config_path = get(g:, 'bob_config_path', "")
	let s:bob_config_path_abs = s:bob_base_path."/".s:bob_config_path
	let s:config_names = map(globpath(s:bob_config_path_abs, '*.yaml', 0, 1), 'fnamemodify(v:val, ":t:r")')
	let s:is_initialized = 1
endfunction

function! s:CheckInit()
	if !s:is_initialized
		throw "run BobInit first!"
	endif
endfunction

function! s:Clean()
	call s:CheckInit()
	execute "!rm -r " . s:bob_base_path . "/dev/build " . s:bob_base_path . "/dev/dist"
endfunction

function! s:PackageComplete(ArgLead, CmdLine, CursorPos)
	return s:bob_package_list
endfunction

function! s:PackageAndConfigComplete(ArgLead, CmdLine, CursorPos)
	let l:command_list = split(a:CmdLine," ", 1)
	if len(l:command_list) < 3
		" first argument
		return s:bob_package_list
	elseif len(l:command_list) < 4
		return join(s:config_names, "\n")
	else
		return ""
	endif
endfunction

function! s:GotoPackageSourceDir(...)
	call s:CheckInit()
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
	call s:CheckInit()
	echo system("cd " . shellescape(s:bob_base_path) . "; bob dev --checkout-only " . a:package)
endfunction

function! s:Dev(package,...)
	call s:CheckInit()
	let l:command = "cd " . shellescape(s:bob_base_path) . "; bob dev " . a:package
	if a:0 == 0
		let &makeprg = l:command
	else
		let l:config = " -c " . s:bob_config_path . "/" . a:1
		let &makeprg = l:command . l:config
	endif

	if a:0 > 1
		let l:args = join(a:000[1:-1])
		let &makeprg = l:command . l:config . " " . l:args
	endif

	make
endfunction

function! s:CreateCompileCommandsFile(package)
	call s:CheckInit()
	" get build paths to all modules necessary for building the package
	let l:paths = system("cd " . shellescape(s:bob_base_path) . "; bob query-path -r -f '{build}' " . a:package)
	let l:paths = split(l:paths, "\n")
	" replace the paths with the actual content of the compile commands file
	" in that paths
	let l:content = map(l:paths, 's:LoadCompileCommands(v:val . "/compile_commands.json")')
	" remove the list operator around each individual compile command
	" expression and add a comma at the end
	let l:content = map(l:content, 'substitute(v:val, "\\[\\(.*\\)\\]", "\\1,", "")')
	" join all expressions into one
	let l:content = join(l:paths, "\n")
	" add opening bracket at begin and replace last comma with closing bracket
	" and finish with a newline
	let l:content = substitute(l:content, "\\(.*\\),", "[\\1]\\n", "")
	" get the source directory of the package, we want to put the resulting
	" compile commands file there
	let l:target_path = system("cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' ". a:package)
	" remove /workspace so we do not clutter the repository, and also remove
	" trailing newline
	let l:target_file = substitute(l:target_path, "workspace\\n$", "compile_commands.json", "")
	execute "redir! > " . l:target_file
		silent echo l:content
	redir END
endfunction

" try to load the given file and return it's content
function! s:LoadCompileCommands(file)
	if empty(glob(a:file))
		return ""
	endif
	return join(readfile(a:file), "\n")
endfunction

command! BobInit call s:Init()
command! BobClean call s:Clean()
command! -nargs=? -complete=custom,s:PackageComplete BobGoto call s:GotoPackageSourceDir(<f-args>)
command! -nargs=1 -complete=custom,s:PackageComplete BobCheckout call s:CheckoutPackage(<f-args>)
command! -nargs=* -complete=custom,s:PackageAndConfigComplete BobDev call s:Dev(<f-args>)
command! -nargs=* -complete=custom,s:PackageAndConfigComplete BobDevAndBuildCompilationDatabase call s:Dev(<f-args>) | call s:CreateCompileCommandsFile(<f-args>)
