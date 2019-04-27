let s:is_initialized = 0
" get path of the current script, which is also the path to the YCM config
" template file
let s:script_path = expand('<sfile>:h')
let s:additional_params = ["-DBUILD_TYPE=Release", "-DBUILD_TYPE=Debug"]
" command line options that are not suitable for calling bob-querry commands
let s:query_option_filter = ["-b", "--build-only"]
let s:project_config = ''
if !exists('g:bob_reduce_goto_list')
	let g:bob_reduce_goto_list = 1
endif

function! s:RemoveInfoMessages(text)
	let l:text = a:text
	let l:text = substitute(l:text, "INFO:.\\{-}\n", '', 'g')
	let l:text = substitute(l:text, "WARNING:.\\{-}\n", '', 'g')
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
	if exists("s:project_package_src_dirs_reduced")
		return join(sort(keys(s:project_package_src_dirs_reduced)), "\n")
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
		if exists('s:project_package_src_dirs_reduced')
			" in project mode, we already cached the source directories
			let l:dir = s:project_package_src_dirs_reduced[a:1]
		else
			let l:output = system("cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . a:1)
			let l:dir = s:RemoveWarnings(l:output)
			if empty(l:dir)
				" this check should only be necessary when not in project
				" mode, because project mode builds everything during
				" initialization which ensures that package source dirs exist
				echom "package has no sources or is not checked out"
				return
			endif
		endif
		if empty(l:dir)
			echoerr "package " . a:1 . " has no source directory"
			return
		endif
		echom l:dir
		execute l:command . s:bob_base_path . "/" . l:dir
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

	" set already known project properties globally, so they are usable
	" subsequently
	" TODO use local variable so we can restore the global state in case an
	"      error occurs subsequently which does not allow proper loading of
	"      the project
	let s:project_name = a:package
	let s:project_options = a:000
	if a:0 == 0
		let s:project_config = ''
	else
		let s:project_config = ' -c ' . s:bob_config_path . '/' . a:1
	endif

	" generate list of packages needed by that root package
	let l:list = system("cd " . shellescape(s:bob_base_path) . "; bob ls --prefixed --recursive " . s:project_config . " " . a:package)
	let l:list = s:RemoveInfoMessages(l:list)
	let l:list = split(l:list, '\n')
	let s:project_package_src_dirs = {}
	echo "gather source paths …"
	for l:package in l:list
		let l:command = "cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . s:project_config . " " . l:package
		" the path contains a trailing newline, which is removed by
		" substitute()
		let s:project_package_src_dirs[l:package] = substitute(s:RemoveInfoMessages(system(l:command)), "\n", "", "")
	endfor
	let l:package_long_names = keys(s:project_package_src_dirs)
	let l:map_short_to_long_names = {}
	if g:bob_reduce_goto_list
		" generate map of all short packages names associated to a list of
		" according long packages names
		echo "generate short package names …"
		for l:long_name in l:package_long_names
			let l:short_name = substitute(l:long_name, "^.*\/", "", "")
			if has_key(l:map_short_to_long_names, l:short_name)
				let l:map_short_to_long_names[l:short_name] += [l:long_name]
			else
				let l:map_short_to_long_names[l:short_name] = [l:long_name]
			endif
		endfor
		" check if the directories are equal for each short name package
		let s:project_package_src_dirs_reduced = {}
		for l:short_name in keys(l:map_short_to_long_names)
			let l:all_dirs = []
			for l:long_name in l:map_short_to_long_names[l:short_name]
				let l:all_dirs += [s:project_package_src_dirs[l:long_name]]
			endfor
			if len(uniq(sort(l:all_dirs))) == 1
				" all directories are equal, therefor store only the short
				" name and the according directory
				let s:project_package_src_dirs_reduced[l:short_name] = s:project_package_src_dirs[l:map_short_to_long_names[l:short_name][0]]
			else
				" at least one package has a different directory, therefor
				" store all variants with there complete package name and the
				" according directories
				for l:long_name in l:map_short_to_long_names[l:short_name]
					let s:project_package_src_dirs_reduced[l:long_name] = s:project_package_src_dirs[l:long_name]
				endfor
			endif
		endfor
	else
		let s:project_package_src_dirs_reduced = s:project_package_src_dirs
	endif
	" add the root recipe to the lists
	let l:command = "cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . a:package
	" the path contains a trailing newline, which is removed by substitute()
	let s:project_package_src_dirs_reduced[a:package] = substitute(s:RemoveInfoMessages(system(l:command)), "\n", "", "")

	echo "gather build paths …"
	let s:project_package_build_dirs = {}
	for l:package in l:list
		let l:command = "cd " . shellescape(s:bob_base_path) . "; bob query-path -f '{build}' " . s:project_config . " " . l:package
		" the path contains a trailing newline, which is removed by
		" substitute()
		let s:project_package_build_dirs[l:package] = substitute(s:RemoveInfoMessages(system(l:command)), "\n", "", "")
	endfor
	" The long package names are used for specifying the build directories,
	" because in theory a package could be build multiple times with different
	" build-flags and therefor in different build folders, because its
	" dependent package introduced different build flags.
	" That doesn't really makes sense for C-packages linked into the same
	" application because it could introduced different symbols with equal
	" names multiple times.
	" On the other hand we want to stay as generic as possible. There could be
	" a project generating multiple applications or libraries for example.
	" So for comomn cases we will get a compilation databases that contains
	" redundant entries. Which should be no problem for the common, single
	" target, use case. In the multi-target use case we have a problem anyway
	" because we would have to generate multiple compilation databases, but it
	" is not possible to determine for which target a source file should be
	" checked if it is used in multiple targets.

	echo "generate configuration for YouCompleteMe …"
	call s:Ycm(a:package)
endfunction

function! s:Dev(bang, ...)
	call s:CheckInit()
	if (a:0 == 0)
		if exists('s:project_name')
			let l:package = s:project_name
			let l:optionals = s:project_options
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
	let l:output = system('cd ' . shellescape(s:bob_base_path) . '; bob query-path -f ''{build}'' ' . s:project_config . ' ' . join(filter(copy(s:project_options[1:-1]), 'match(s:query_option_filter, v:val)'), ' ') . ' ' . a:package)
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
	" TODO use this approach: https://vi.stackexchange.com/a/16059/7823
	tabnew
	" insert the correct path to the compilation database file
	execute 'read' (s:script_path . '/ycm_extra_conf.py.template')
	let l:subst_command = '%s/@db_path@/' . l:db_path_subst . '\/'
	execute(l:subst_command)
	execute 'silent! write!' (s:bob_base_path . '/dev/.ycm_extra_conf.py')
	" clean up the temporary buffer and tab
	bd!
	if filereadable(l:db_path_abs."/compile_commands.json")
		"copy the compilation database for chromatica and clangd-based
		"YouCompleteMe
		let fl = readfile(l:db_path_abs."/compile_commands.json", "b")
		call writefile(fl, s:bob_base_path."/dev/compile_commands.json", "b")
	else
		echom "No compile_commands.json file found in root package!"
		" create an empty file because the subsequent part of this function
		" relys on an existing database
		call writefile(['[', ']'], s:bob_base_path.'/compile_commands.json', 'b')
	endif
	" add contents of all depending packages to the root package compilation
	" database
	" TODO use this approach: https://vi.stackexchange.com/a/16059/7823
	execute "tabnew" fnameescape(s:bob_base_path . "/dev/compile_commands.json")
	" replace closing bracket at last line with comma for possible
	" continuation of the list
	normal Gr,
	for l:build_dir in values(s:project_package_build_dirs)
		let l:file = fnameescape(l:build_dir . "/compile_commands.json")
		if filereadable(l:file)
			execute "read" l:file
			normal ddGr,
		endif
	endfor
	" add closing bracket at last line, also removes the last comma
	normal Gr]
	execute "silent! write!"

	"workaround for error message "Key not present in Dictionary: git"
	"seems to happen only when airline and fugitive are loaded
	"found a file-scoped dictionary in
	"vim-airline/autoload/airline/extensions/branch.vim
	"is this a race condition in neovim?
	sleep 100 m

	bd!
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
