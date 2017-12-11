let s:is_initialized = 0
" get path of the current script, which is also the path to the YCM config
" template file
let s:script_path = expand('<sfile>:h')
let s:additional_params = ["-DBUILD_TYPE=Release", "-DBUILD_TYPE=Debug"]

function! s:Init()
	let s:bob_package_list = system("bob ls")
	if match(s:bob_package_list, "Parse error:") != -1
		echo "vim-bob not initialized, output from bob ls:"
		echo s:bob_package_list
		return
	endif
	while s:bob_package_list =~ "^INFO:.*\n" || s:bob_package_list =~ "^See .*\n"
		let s:bob_package_list = substitute(s:bob_package_list, 'INFO:.\{-}\n', '', 'g')
		let s:bob_package_list = substitute(s:bob_package_list, 'See .\{-}\n', '', 'g')
	endwhile
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
		return join(s:additional_params, "\n")
	endif
endfunction

function! s:GotoPackageSourceDir(...)
	call s:CheckInit()
	if a:0 == 0
		execute "cd " . s:bob_base_path
	elseif a:0 == 1
		let l:output = system("cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . a:1)
		let l:dir = s:RemoveWarnings(l:output)
		echom l:dir
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

function! s:GetStatus(package)
	call s:CheckInit()
	echo system("cd " . shellescape(s:bob_base_path) . "; bob status --recursive " . a:package)
endfunction

function! s:Dev(bang,package,...)
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

	execute 'make'.a:bang
endfunction

function! s:RemoveWarnings(bob_output)
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
	let l:db_path_subst = substitute(l:db_path, '^', s:bob_base_path.'/', '')
	" escape slashes
	let l:db_path_subst = substitute(l:db_path_subst, '/', '\\/', 'g')
	" remove newlines (output of bob query-path contains a trailing newline)
	let l:db_path_subst = substitute(l:db_path_subst, '\n', '', 'g')
	" copy the template into the dev directory
	tabnew
	" insert the correct path to the compilation database file
	execute 'read' (s:script_path . '/ycm_extra_conf.py.template')
	let l:subst_command = '%s/@db_path@/' . l:db_path_subst . '\/'
	execute(l:subst_command)
	execute 'write!' (s:bob_base_path . '/dev/.ycm_extra_conf.py')
	" clean up the temporary buffer and tab
	bw!
	"copy the compilation database for chromatica
	let fl = readfile(l:db_path."/compile_commands.json", "b")
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
command! -nargs=? -complete=custom,s:PackageComplete BobGoto call s:GotoPackageSourceDir(<f-args>)
command! -nargs=? -complete=custom,s:PackageComplete BobStatus call s:GetStatus(<f-args>)
command! -nargs=1 -complete=custom,s:PackageComplete BobCheckout call s:CheckoutPackage(<f-args>)
command! -bang -nargs=* -complete=custom,s:PackageAndConfigComplete BobDev call s:Dev("<bang>",<f-args>)
command! -nargs=* -complete=custom,s:PackageAndConfigComplete BobYcm call s:Ycm(<f-args>)
