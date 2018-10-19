let s:is_initialized = 0
" get path of the current script, which is also the path to the YCM config
" template file
let s:script_path = expand('<sfile>:h')
let s:additional_params = ["-DBUILD_TYPE=Release", "-DBUILD_TYPE=Debug"]

function! s:RemoveInfoMessages(text)
	let l:text = a:text
	let l:text = substitute(l:text, "INFO:.\\{-}\n", '', 'g')
	let l:text = substitute(l:text, "See .\\{-}\n", '', 'g')
	return l:text
endfunction

function! s:Init()
	let s:bob_package_list = system("bob ls")
	let s:bob_package_tree_list = system("bob ls -pr")
	if match(s:bob_package_list, "Parse error:") != -1
		echo "vim-bob not initialized, output from bob ls:"
		echo s:bob_package_list
		return
	endif
	let s:bob_package_list = s:RemoveInfoMessages(s:bob_package_list)
	let s:bob_package_tree_list = s:RemoveInfoMessages(s:bob_package_tree_list)
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

function! s:ProjectPackageComplete(ArgLead, CmdLine, CursorPos)
	if exists("s:current_project_package_list")
		return join(filter(s:current_project_package_list, {idx, elem -> elem =~ '^' . a:ArgLead}), "\n")
	else
		return s:PackageTreeComplete(a:ArgLead, a:CmdLine, a:CursorPos)
	endif
endfunction

function! s:PackageTreeComplete(ArgLead, CmdLine, CursorPos)
	return join(filter(split(s:bob_package_tree_list, "\n"), {idx, elem -> elem =~ '^' . a:ArgLead . '[^/]*$'}), "\n")
endfunction

function! s:PackageAndConfigComplete(ArgLead, CmdLine, CursorPos)
	let l:command_list = split(a:CmdLine," ", 1)
	if len(l:command_list) < 3
		" first argument
		return s:PackageComplete(a:ArgLead, a:CmdLine, a:CursorPos)
	elseif len(l:command_list) < 4
		return join(s:config_names, "\n")
	else
		return join(s:additional_params, "\n")
	endif
endfunction

function! s:GotoPackageSourceDir(bang, ...)
	call s:CheckInit()
	if a:bang
		let l:command = "cd "
	else
		let l:command = "lcd "
	endif
	if a:0 == 0
		execute l:command . s:bob_base_path
	elseif a:0 == 1
		let l:output = system("cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . a:1)
		let l:dir = s:RemoveWarnings(l:output)
		echom l:dir
		if !empty(l:dir)
			execute l:command . s:bob_base_path . "/" . l:dir
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

function! s:GetStatus(package)
	call s:CheckInit()
	echo system("cd " . shellescape(s:bob_base_path) . "; bob status --verbose --recursive " . a:package)
endfunction

function! s:Project(bang, package, ...)
	call s:CheckInit()
	call s:DevImpl(a:bang, a:package, a:000)

	" generate list of packages needed by that root package
	let l:list = system("cd " . shellescape(s:bob_base_path) . "; bob ls --all --recursive " . a:package)
	let l:list = s:RemoveInfoMessages(l:list)
	let l:list = split(l:list, '\n')
	" remove the ascii tree
	let l:list = map(l:list, {key, val -> substitute(val, '.* \(\S*\)$', '\1', '')})
	let l:list = sort(l:list)
	let l:list = uniq(l:list)
	let s:current_project_package_list = l:list
	let s:current_project_name = a:package
	let s:current_project_options = a:000

	" generate configuration for YouCompleteMe
	call s:Ycm(a:package)
endfunction

function! s:Dev(bang, ...)
	call s:CheckInit()
	if (a:0 == 0)
		if exists('s:current_project_name')
			let l:package = s:current_project_name
			let l:optionals = s:current_project_options
		else
			echom 'error: provide a package name or run :BobProject first'
			return
		endif
	else
		let l:package = a:1
		let l:optionals = copy(a:000)
		call remove(l:optionals, 0)
	endif
	call s:DevImpl(a:bang, l:package, l:optionals)
endfunction

" we need this extra function to be able to forward optional parameters from
" other functions as well as comands. Forwarding from functions does work with
" a list of arguments exclusively, whereas commands provide optional arguments
" as separte variables (a:0, a:1, etc.).
function! s:DevImpl(bang, package, optionals)
	let l:command = "cd " . shellescape(s:bob_base_path) . "; bob dev " . a:package
	echo a:optionals
	if len(a:optionals) == 0
		let &makeprg = l:command
	else
		let l:config = " -c " . s:bob_config_path . "/" . a:optionals[0]
		let &makeprg = l:command . l:config
	endif

	if len(a:optionals) > 1
		let l:args = join(a:optionals[1:-1])
		let &makeprg = l:command . l:config . " " . l:args
	endif

	execute 'make'.a:bang
endfunction

function! s:RemoveWarnings(bob_output)
	if empty(a:bob_output)
		return a:bob_output
	endif

	"Assumption: Only last line of output is the actual output, everything
	"else is a warning
	let l:output = split(a:bob_output, "\n")[-1]
	"check if last line is also a warning because the actual output is
	"of query-path is empty
	if l:output !~ "^WARNING: .*$" && l:output !~ "^INFO: .*$" && l:output !~ "^See .*$"
		return l:output
	endif
	"return nothing, because the output contained only warnings
endfunction

function! s:Ycm(package,...)
	call s:CheckInit()
	" get build path, which is also the path to the compilation database
	" TODO generic function for building the bob command from the given
	" parameters, as we could use the configuration here, too.
	let l:output = system("cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{build}' " . a:package)
	let l:db_path = s:RemoveWarnings(l:output)
	if empty(l:db_path)
		echohl WarningMsg | echo a:package " has not been built yet." | echohl None
		return
	endif
	" make the path absolute
	let l:db_path_abs = substitute(l:db_path, '^', s:bob_base_path.'/', '')
	" escape slashes
	let l:db_path_subst = substitute(l:db_path_abs, '/', '\\/', 'g')
	" remove newlines (output of bob query-path contains a trailing newline)
	let l:db_path_subst = substitute(l:db_path_subst, '\n', '', 'g')
	" copy the template into the dev directory
	tabnew
	" insert the correct path to the compilation database file
	execute 'read' (s:script_path . '/ycm_extra_conf.py.template')
	let l:subst_command = '%s/@db_path@/' . l:db_path_subst . '\/'
	execute(l:subst_command)
	execute 'silent! write!' (s:bob_base_path . '/dev/.ycm_extra_conf.py')
	" clean up the temporary buffer and tab
	bw!
	"copy the compilation database for chromatica
	let fl = readfile(l:db_path_abs."/compile_commands.json", "b")
	call writefile(fl, s:bob_base_path."/dev/compile_commands.json", "b")
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
command! -bang -nargs=? -complete=custom,s:ProjectPackageComplete BobGoto call s:GotoPackageSourceDir("<bang>", <f-args>)
command! -bang -nargs=? -complete=custom,s:PackageTreeComplete BobGotoAll call s:GotoPackageSourceDir("<bang>", <f-args>)
command! -nargs=? -complete=custom,s:PackageTreeComplete BobStatus call s:GetStatus(<f-args>)
command! -nargs=1 -complete=custom,s:PackageTreeComplete BobCheckout call s:CheckoutPackage(<f-args>)
command! -bang -nargs=* -complete=custom,s:PackageAndConfigComplete BobDev call s:Dev("<bang>",<f-args>)
command! -bang -nargs=* -complete=custom,s:PackageAndConfigComplete BobProject call s:Project("<bang>",<f-args>)
command! -nargs=* -complete=custom,s:PackageAndConfigComplete BobYcm call s:Ycm(<f-args>)
