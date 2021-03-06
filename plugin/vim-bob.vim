" represents the initialization state of the plugin
let s:is_initialized = 0
" get path of the current script, which is also the path to the YCM config
" template file
let s:script_path = expand('<sfile>:h')
" list of additional parameters for `BobDev` and `BobProject` used for
" auto-completion
let s:additional_params = ['-DBUILD_TYPE=Release', '-DBUILD_TYPE=Debug']
" command line options that are not suitable for calling bob-querry commands
let s:query_option_filter = ['-b', '--build-only', '-v', '--verbose', '--clean', '--force']
" the name of the project, effectively the name of the Bob package
let s:project_name = ''
" the configuration used for the current project as given to `BobProject`,
" i.e. without the file ending and without the `-c` command line option
let s:project_config = ''
" all command line options for the current project excluding the configuration
" option, which is stored separately in s:project_config
let s:project_options = []
" derived from s:project_options, but options that are not usable for queries
" are removed here (see s:query_option_filter)
" these options are also suitable for usage with `bob ls` and `bob graph`
let s:project_query_options = []
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
	let s:bob_package_list = system('bob ls')
	let s:bob_package_tree_list = system('bob ls -pr')
	if match(s:bob_package_list, 'Parse error:') != -1
		echo 'vim-bob not initialized, output from bob ls:'
		echo s:bob_package_list
		return
	endif
	let s:bob_package_list = s:RemoveInfoMessages(s:bob_package_list)
	let s:bob_package_tree_list = s:RemoveInfoMessages(s:bob_package_tree_list)
	let s:bob_base_path = getcwd()
	let s:bob_config_path = get(g:, 'bob_config_path', '')
	let s:bob_config_path_abs = s:bob_base_path.'/'.s:bob_config_path
	let s:config_names = map(globpath(s:bob_config_path_abs, '*.yaml', 0, 1), 'fnamemodify(v:val, ":t:r")')
	let s:is_initialized = 1
endfunction

function! s:CheckInit()
	if !s:is_initialized
		throw 'run BobInit first!'
	endif
endfunction

function! s:Clean()
	call s:CheckInit()
	execute '!rm -r ' . s:bob_base_path . '/dev/build ' . s:bob_base_path . '/dev/dist'
endfunction

function! s:PackageComplete(ArgLead, CmdLine, CursorPos)
	return s:bob_package_list
endfunction

function! s:ProjectPackageComplete(ArgLead, CmdLine, CursorPos)
	if exists('s:project_package_src_dirs_reduced')
		return join(sort(keys(s:project_package_src_dirs_reduced)), "\n")
	else
		return s:PackageTreeComplete(a:ArgLead, a:CmdLine, a:CursorPos)
	endif
endfunction

function! s:PackageTreeComplete(ArgLead, CmdLine, CursorPos)
	return join(filter(split(s:bob_package_tree_list, "\n"), {idx, elem -> elem =~ '^' . a:ArgLead . '[^/]*$'}), "\n")
endfunction

function! s:PackageAndConfigComplete(ArgLead, CmdLine, CursorPos)
	let l:command_list = split(a:CmdLine,' ', 1)
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
		let l:command = 'cd '
	else
		let l:command = 'lcd '
	endif
	if a:0 == 0
		execute l:command . s:bob_base_path
	elseif a:0 == 1
		if exists('s:project_package_src_dirs_reduced')
			" in project mode, we already cached the source directories
			let l:dir = s:project_package_src_dirs_reduced[a:1]
		else
			" TODO use correct configuration
			let l:output = system('cd ' . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . a:1)
			let l:dir = s:RemoveWarnings(l:output)
			if empty(l:dir)
				" this check should only be necessary when not in project
				" mode, because project mode builds everything during
				" initialization which ensures that package source dirs exist
				echom 'package has no sources or is not checked out'
				return
			endif
		endif
		if empty(l:dir)
			echoerr 'package ' . a:1 . ' has no source directory'
			return
		endif
		echom l:dir
		execute l:command . s:bob_base_path . '/' . l:dir
	else
		echom 'BobGoto takes at most one parameter'
	endif
endfunction

function! s:CheckoutPackage(package)
	call s:CheckInit()
	echo system('cd ' . shellescape(s:bob_base_path) . '; bob dev --checkout-only ' . a:package)
endfunction

function! s:GetStatus(package)
	call s:CheckInit()
	echo system('cd ' . shellescape(s:bob_base_path) . '; bob status --verbose --recursive ' . a:package)
endfunction

function! s:Project(bang, package, ...)
	call s:CheckInit()
	call s:DevImpl(a:bang, a:package, a:000)
	augroup bob
		autocmd!
		" make generated files not writeable, in order to prevent editing the
		" wrong file and losing the changes during Bob's rebuild
		let s:roPath = '*/dev/dist/*,*/dev/build/*'
		let s:errMsg = 'vim-bob: You are trying to edit a generated file.'
					\ .' If you really want to write to it use `set buftype=`'
					\ .' and proceed, but rebuilding will probably delete these'
					\ .' changes!'
		" using 'acwrite' so we can present a meaningful error message
		autocmd BufReadPost s:roPath set buftype=acwrite
		autocmd BufWriteCmd s:roPath echoerr s:errMsg
	augroup END

	" set already known project properties globally, so they are usable
	" subsequently
	" TODO use local variable so we can restore the global state in case an
	"      error occurs subsequently which does not allow proper loading of
	"      the project
	let s:project_name = a:package
	" the first option is always the configuration (without the '-c'), which
	" is stored separately in s:project_config
	let s:project_options = copy(a:000[1:-1])
	let s:project_query_options = filter(copy(s:project_options[0:-1]), 'match(s:query_option_filter, v:val) == -1')
	if a:0 == 0
		let s:project_config = ''
	else
		let s:project_config = ' -c ' . s:bob_config_path . '/' . a:1
	endif

	" generate list of packages needed by that root package
	let l:list = system('cd ' . shellescape(s:bob_base_path) . '; bob ls --prefixed --recursive ' . s:project_config . ' ' . join(s:project_query_options, ' ') . ' ' . a:package)
	let l:list = s:RemoveInfoMessages(l:list)
	let l:list = split(l:list, "\n")
	let l:project_package_src_dirs = {}
	echo 'gather package paths …'
	let l:command = 'cd ' . shellescape(s:bob_base_path) . "; bob query-path -f '{name} | {src} | {build}' " . s:project_config . ' ' . join(s:project_query_options, ' ') . ' ' . join(l:list, ' ') . ' 2>&1'
	let l:result = split(s:RemoveInfoMessages(system(l:command)), "\n")
	let l:idx = 0
	let s:project_package_build_dirs = {}
	for l:package in l:list
		let l:matches = matchlist(l:result[l:idx], '^\(.*\) | \(.*\) | \(.*\)$')
		if empty(l:matches)
			echom 'skipped caching of ' . l:package
		else
			echom 'caching ' . l:package . ' as ' . l:matches[1]
			let l:project_package_src_dirs[l:package] = l:matches[2]
			let s:project_package_build_dirs[l:package] = l:matches[3]
		endif
		let idx += 1
	endfor
	let l:package_long_names = keys(l:project_package_src_dirs)
	let l:map_short_to_long_names = {}
	" TODO the query-path does already reduce the list, we its only necessary
	" to remove duplicate entries from l:project_package_src_dirs and
	" s:project_package_build_dirs
	if g:bob_reduce_goto_list
		" generate map of all short packages names associated to a list of
		" according long packages names
		echo 'generate short package names …'
		for l:long_name in l:package_long_names
			let l:short_name = substitute(l:long_name, '^.*\/', '', '')
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
				let l:all_dirs += [l:project_package_src_dirs[l:long_name]]
			endfor
			if len(uniq(sort(l:all_dirs))) == 1
				" all directories are equal, therefor store only the short
				" name and the according directory
				let s:project_package_src_dirs_reduced[l:short_name] = l:project_package_src_dirs[l:map_short_to_long_names[l:short_name][0]]
			else
				" at least one package has a different directory, therefor
				" store all variants with there complete package name and the
				" according directories
				for l:long_name in l:map_short_to_long_names[l:short_name]
					let s:project_package_src_dirs_reduced[l:long_name] = l:project_package_src_dirs[l:long_name]
				endfor
			endif
		endfor
	else
		let s:project_package_src_dirs_reduced = l:project_package_src_dirs
	endif
	" add the root recipe to the lists
	let l:command = 'cd ' . shellescape(s:bob_base_path) . "; bob query-path -f '{src}' " . s:project_config . ' ' . join(s:project_query_options, ' ') . ' ' . a:package
	" the path contains a trailing newline, which is removed by substitute()
	let s:project_package_src_dirs_reduced[a:package] = substitute(s:RemoveInfoMessages(system(l:command)), "\n", '', '')

	" The long package names are used for specifying the build directories,
	" because in theory a package could be build multiple times with different
	" build-flags and therefor in different build folders, because its
	" dependent package introduced different build flags.
	" That doesn't really makes sense for C-packages linked into the same
	" application because it could introduced different symbols with equal
	" names multiple times.
	" On the other hand we want to stay as generic as possible. There could be
	" a project generating multiple applications or libraries for example.
	" So for common cases we will get a compilation databases that contains
	" redundant entries. Which should be no problem for the common, single
	" target, use case. In the multi-target use case we have a problem anyway
	" because we would have to generate multiple compilation databases, but it
	" is not possible to determine for which target a source file should be
	" checked if it is used in multiple targets.

	echo 'generate configuration for YouCompleteMe …'
	call s:Ycm(a:package)
endfunction

function! s:Dev(bang, ...)
	call s:CheckInit()
	if (a:0 == 0)
		if !empty(s:project_name)
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
" other functions as well as commands. Forwarding from functions does work with
" a list of arguments exclusively, whereas commands provide optional arguments
" as separate variables (a:0, a:1, etc.).
function! s:DevImpl(bang, package, optionals)
	let l:command = 'cd ' . shellescape(s:bob_base_path) . '; bob dev ' . a:package
	if len(a:optionals) == 0
		let &makeprg = l:command
	else
		let l:config = ' -c ' . s:bob_config_path . '/' . a:optionals[0]
		let &makeprg = l:command . l:config
	endif

	if len(a:optionals) > 1
		let l:args = join(a:optionals[1:-1])
		let &makeprg = l:command . l:config . ' ' . l:args
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
	"check if last line is also a warning, in that case the actual output of
	"query-path is empty
	if l:output !~# '^WARNING: .*$' && l:output !~# '^INFO: .*$' && l:output !~# '^See .*$'
		return l:output
	endif
	"return nothing, because the output contained only warnings
endfunction

function! s:Ycm(package,...)
	call s:CheckInit()
	" get build path, which is also the path to the compilation database
	let l:output = system('cd ' . shellescape(s:bob_base_path) . '; bob query-path -f ''{build}'' ' . s:project_config . ' ' . join(s:project_query_options, ' ') . ' ' . a:package)
	let l:db_path = s:RemoveWarnings(l:output)
	if empty(l:db_path)
		echohl WarningMsg | echo a:package ' has not been built yet.' | echohl None
		return
	endif
	" make the path absolute
	let l:db_path_abs = substitute(l:db_path, '^', s:bob_base_path.'/', '')
	" escape slashes
	let l:db_path_subst = substitute(l:db_path_abs, '/', '\\/', 'g')
	" remove newlines (output of bob query-path contains a trailing newline)
	let l:db_path_subst = substitute(l:db_path_subst, '\n', '', 'g')
	" copy the template into the dev directory and insert the correct path to
	" the compilation database file
	let l:text = readfile(s:script_path . '/ycm_extra_conf.py.template')
	call map(l:text, 'substitute(v:val, "@db_path@", s:bob_base_path."/dev", "g")')
	call writefile(l:text, s:bob_base_path . '/dev/.ycm_extra_conf.py')
	if filereadable(l:db_path_abs.'/compile_commands.json')
		"copy the compilation database for chromatica and clangd-based
		"YouCompleteMe
		let fl = readfile(l:db_path_abs.'/compile_commands.json', 'b')
		call writefile(fl, s:bob_base_path.'/dev/compile_commands.json', 'b')
	else
		echom 'No compile_commands.json file found in root package!'
		" create an empty file because the subsequent part of this function
		" relies on an existing database
		call writefile(['[', ']'], s:bob_base_path.'/dev/compile_commands.json')
	endif
	" add contents of all depending packages to the root package compilation
	" database
	let l:fileName = fnameescape(s:bob_base_path . '/dev/compile_commands.json')
	let l:text = readfile(l:fileName)
	" replace closing bracket at last line with comma for possible
	" continuation of the list
	let l:text[-1] = ','
	for l:build_dir in values(s:project_package_build_dirs)
		let l:file = fnameescape(l:build_dir . '/compile_commands.json')
		if filereadable(l:file)
			let l:textToAdd = readfile(l:file)
			" append without the surrounding brackets (first and last line)
			call extend(l:text, l:textToAdd[1:-2])
			" add comma for possible continuation
			call add(l:text, ',')
		endif
	endfor
	" replace last comma with closing bracket
	let l:text[-1] = ']'
	call writefile(l:text, l:fileName)
endfunction

" try to load the given file and return it's content
function! s:LoadCompileCommands(file)
	if empty(glob(a:file))
		return ''
	endif
	return join(readfile(a:file), "\n")
endfunction

function! s:HandleError(job_id, data, event)
	echom join(a:data)
endfunction
function! s:Graph()
	call s:CheckInit()
	if !exists('g:bob_graph_type')
		" using the same default as Bob currently uses (as of v0.16)
		let g:bob_graph_type = 'd3'
	endif

	" run `bob graph`
	let l:graph_type = '-t ' . g:bob_graph_type
	let l:filename = substitute(s:project_name, '[_:-]', '', 'g')
	let l:command = 'cd ' . shellescape(s:bob_base_path) . '; bob graph ' . s:project_config . ' ' . join(s:project_query_options) . ' ' . l:graph_type . ' -f ' . l:filename . ' ' . s:project_name
	" using s:project_query_options because `bob graph` seems to dislike the
	" same options as the query commands
	echo system(l:command)

	" open generated graph
	let l:open_options = {'detach': 1, 'on_stderr': funcref('s:HandleError')}
	if g:bob_graph_type ==? 'dot'
		" generate graphic from dot file
		let l:gen_command = 'cd ' . shellescape(s:bob_base_path) . '/graph/' . '; dot -Tpng -o ' . l:filename . '.png ' . l:filename . '.dot'
		echo system(l:gen_command)
		" open graphic
		let l:open_command = ['xdg-open', s:bob_base_path.'/graph/'.l:filename.'.png']
		call jobstart(l:open_command, l:open_options)
	elseif g:bob_graph_type ==? 'd3'
		let l:open_command = ['xdg-open', s:bob_base_path.'/graph/'.l:filename.'.html']
		call jobstart(l:open_command, l:open_options)
	endif
endfunction

command! BobInit call s:Init()
command! BobClean call s:Clean()
command! BobGraph call s:Graph()
command! -bang -nargs=? -complete=custom,s:ProjectPackageComplete BobGoto call s:GotoPackageSourceDir("<bang>", <f-args>)
command! -bang -nargs=? -complete=custom,s:PackageTreeComplete BobGotoAll call s:GotoPackageSourceDir("<bang>", <f-args>)
command! -nargs=? -complete=custom,s:PackageTreeComplete BobStatus call s:GetStatus(<f-args>)
command! -nargs=1 -complete=custom,s:PackageTreeComplete BobCheckout call s:CheckoutPackage(<f-args>)
command! -bang -nargs=* -complete=custom,s:PackageAndConfigComplete BobDev call s:Dev("<bang>",<f-args>)
command! -bang -nargs=* -complete=custom,s:PackageAndConfigComplete BobProject call s:Project("<bang>",<f-args>)
command! -nargs=* -complete=custom,s:PackageAndConfigComplete BobYcm call s:Ycm(<f-args>)
