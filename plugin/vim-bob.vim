" represents the initialization state of the plugin
let s:is_initialized = 0
" get path of the current script, which is also the path to the YCM config
" template file
let s:script_path = expand('<sfile>:h')
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
if !exists('g:bob_auto_complete_items')
	let g:bob_auto_complete_items = []
endif
if !exists('g:bob_verbose')
	let g:bob_verbose = 0
endif
if !exists('g:bob_prefix')
	let g:bob_prefix = ''
endif

function! s:RemoveInfoMessages(text)
	let l:text = a:text
	let l:text = substitute(l:text, "INFO:.\\{-}\n", '', 'g')
	let l:text = substitute(l:text, "WARNING:.\\{-}\n", '', 'g')
	let l:text = substitute(l:text, "See .\\{-}\n", '', 'g')
	return l:text
endfunction

function! s:Init(path)
	let l:bob_base_path = empty(a:path) ? getcwd() : fnamemodify(a:path, ':p')
	" not using `--directory` but `cd` instead, because when running inside of
	" a container via `g:bob_prefix` we would pass the path on the host to Bob
	" running in the container, where the path is very likely different
	let l:bob_package_list = system('cd ' . shellescape(l:bob_base_path) . '; bob ls')
	if v:shell_error
		echoerr "vim-bob not initialized, output from bob ls: " . trim(l:bob_package_list)
		return
	endif
	let l:bob_package_tree_list = system('cd ' . shellescape(l:bob_base_path) . '; ' . g:bob_prefix . ' bob ls')
	let l:bob_package_list = s:RemoveInfoMessages(l:bob_package_list)
	let l:bob_package_tree_list = s:RemoveInfoMessages(l:bob_package_tree_list)
	let l:bob_config_path = get(g:, 'bob_config_path', '')
	let l:bob_config_path_abs = l:bob_base_path.'/'.l:bob_config_path
	let l:config_names = map(globpath(l:bob_config_path_abs, '*.yaml', 0, 1), 'fnamemodify(v:val, ":t:r")')
	" everything went right, now persist the new state
	let s:bob_base_path = l:bob_base_path
	let s:bob_package_list = l:bob_package_list
	let s:bob_package_tree_list = l:bob_package_tree_list
	let s:bob_config_path = l:bob_config_path
	let s:bob_config_path_abs = l:bob_config_path_abs
	let s:config_names = l:config_names
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
		return join(g:bob_auto_complete_items, "\n")
	endif
endfunction

function! s:GotoPackageSourceDir(bang, doAll, ...)
	call s:CheckInit()
	if a:bang
		let l:command = 'cd '
	else
		let l:command = 'lcd '
	endif
	if a:0 == 0
		execute l:command . s:bob_base_path
	elseif a:0 == 1
		if ! a:doAll && exists('s:project_package_src_dirs_reduced')
			" in project mode, we already cached the source directories
			let l:dir = s:project_package_src_dirs_reduced[a:1]
		else
			" TODO use correct configuration
			" not using g:bob_prefix here, because this would return the path
			" inside the container which is of no use on the host where we
			" want to do source navigation
			let l:output = system('cd ' . shellescape(s:bob_base_path) . '; bob query-path -f "{src}" ' . a:1)
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
	echo system('cd ' . shellescape(s:bob_base_path) . '; ' . g:bob_prefix . ' bob dev --checkout-only ' . a:package)
endfunction

function! s:GetStatus(...)
	call s:CheckInit()
	if a:0 == 1
		echo system('cd ' . shellescape(s:bob_base_path) . '; ' . g:bob_prefix . ' bob status --verbose --recursive ' . a:1)
		return
	endif

	if empty(s:project_name)
		throw 'I do not know what to check status on. Run :BobProject before querying the status!'
	endif

	echo system('cd ' . shellescape(s:bob_base_path) . '; ' . g:bob_prefix . ' bob status --verbose --recursive ' . s:project_config . ' ' . join(s:project_query_options, ' ') . ' ' . s:project_name)
endfunction

function! s:Project(bang, package, ...)
	call s:CheckInit()

	" build the project
	if empty(g:bob_prefix)
		" try to build the project completely from the start
		try
			let l:original_makeprg = &makeprg
			let l:project_command = s:DevImpl(a:bang, a:package, 0, a:000)
		catch
			echohl WarningMsg
			echo 'Running Bob failed. Trying only checkout step …'
			echohl None
			try
				let l:project_makeprg = &makeprg
				let l:project_command = s:DevImpl(a:bang, a:package, 0, copy(a:000) + ['--checkout-only'])
				" running :make should still try to build not only checkout
				let &makeprg = l:project_makeprg
				echohl WarningMsg
				echo'Running Bob failed after the checkout step. Not all features of vim-bob''s project mode might be available. Re-run :BobProject as soon as these errors are fixed'
				echohl None
			catch
				" project failded completely, going back to the original makoprg
				let &makeprg = l:original_makeprg
				echoerr 'Running Bob failed even when only using checkout step. No new project was created.'
				return
			finally
				" the result of the last build is not really of interest, what is
				" interesting is the previous run, because that one failed and
				" must be fixed in order to get a completely working project
				colder
			endtry
		endtry
	else
		" first try to checkout the project natively and afterwards build it
		" inside the container
		try
			let l:original_makeprg = &makeprg
			" do checkout on the host (i.e., use no prefix), as the container
			" might not be able to do checkouts due to lack of tools installed or
			" lack of permissions
			let l:project_command = s:DevImpl(a:bang, a:package, 0, copy(a:000) + ['--checkout-only'])
		catch
			" project failded completely, going back to the original makoprg
			let &makeprg = l:original_makeprg
			echoerr 'Running Bob failed even when only using checkout step. No new project was created.'
			return
		endtry
		try
			" do build in the container
			" avoid checking out, because the container might not be able to
			" do so
			let l:project_command = s:DevImpl(a:bang, a:package, 1, a:000 + ['--build-only'])
		catch
			echohl WarningMsg
			echo'Running Bob failed after the checkout step. Not all features of vim-bob''s project mode might be available. Re-run :BobProject as soon as these errors are fixed'
			echohl None
		endtry
	endif

	" set already known project properties locally, so they are usable
	" subsequently
	let l:project_name = a:package
	" the first option is always the configuration (without the '-c'), which
	" is stored separately in s:project_config
	let l:project_options = copy(a:000[1:-1])
	let l:project_query_options = filter(copy(l:project_options[0:-1]), 'match(s:query_option_filter, v:val) == -1')
	if a:0 == 0
		let l:project_config = ''
	else
		let l:project_config = ' -c ' . s:bob_config_path . '/' . a:1
	endif

	" generate list of packages needed by that root package
	let l:list = system('cd ' . shellescape(s:bob_base_path) . '; bob ls --prefixed --recursive ' . l:project_config . ' ' . join(l:project_query_options, ' ') . ' ' . a:package)
	let l:list = s:RemoveInfoMessages(l:list)
	" add root package to the list
	let l:list = split(l:list, "\n")
	call add(l:list, a:package)
	let l:project_package_src_dirs = {}
	echo 'gather package paths …'
	" not using g:bob_prefix here, because this would return the path inside
	" the container which is of no use on the host where we want to use code
	" navigation (which needs the source directories) and language servers
	" (which need the compilation databases from the build directories)
	let l:command = 'cd ' . shellescape(s:bob_base_path) . '; bob query-path -f "{name} | {src} | {build}" ' . l:project_config . ' ' . join(l:project_query_options, ' ') . ' ' . join(l:list, ' ') . ' 2>&1'
	let l:result = split(s:RemoveInfoMessages(system(l:command)), "\n")
	let l:idx = 0
	let l:project_package_build_dirs = {}
	for l:package in l:list
		let l:matches = matchlist(l:result[l:idx], '^\(.*\) | \(.*\) | \(.*\)$')
		if empty(l:matches)
			if g:bob_verbose
				echom 'skipped caching of ' . l:package
			endif
		else
			if g:bob_verbose
				echom 'caching ' . l:package . ' as ' . l:matches[1]
			endif
			let l:project_package_src_dirs[l:package] = l:matches[2]
			let l:project_package_build_dirs[l:package] = l:matches[3]
		endif
		let idx += 1
	endfor
	let l:package_long_names = keys(l:project_package_src_dirs)
	let l:map_short_to_long_names = {}
	" TODO the query-path does already reduce the list, we its only necessary
	" to remove duplicate entries from l:project_package_src_dirs and
	" l:project_package_build_dirs
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
		let l:project_package_src_dirs_reduced = {}
		for l:short_name in keys(l:map_short_to_long_names)
			let l:all_dirs = []
			for l:long_name in l:map_short_to_long_names[l:short_name]
				let l:all_dirs += [l:project_package_src_dirs[l:long_name]]
			endfor
			if len(uniq(sort(l:all_dirs))) == 1
				" all directories are equal, therefor store only the short
				" name and the according directory
				let l:project_package_src_dirs_reduced[l:short_name] = l:project_package_src_dirs[l:map_short_to_long_names[l:short_name][0]]
			else
				" at least one package has a different directory, therefor
				" store all variants with there complete package name and the
				" according directories
				for l:long_name in l:map_short_to_long_names[l:short_name]
					let l:project_package_src_dirs_reduced[l:long_name] = l:project_package_src_dirs[l:long_name]
				endfor
			endif
		endfor
	else
		let l:project_package_src_dirs_reduced = l:project_package_src_dirs
	endif

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

	" persist new state
	augroup vim_bob_readonly_dist
		autocmd!
		" make generated files not writeable, in order to prevent editing the
		" wrong file and losing the changes during Bob's rebuild
		let l:roPath = s:bob_base_path . '/dev/dist/*,' . s:bob_base_path . '/dev/build/*'
		execute 'autocmd BufReadPost ' . l:roPath . ' setlocal readonly'
	augroup END
	augroup vim_bob_cd_source
		autocmd!
		" set the local working directory to the root source dir of the
		" respective package
		execute 'autocmd BufWinEnter ' . s:bob_base_path . '/* lcd ' . s:bob_base_path
		for l:path in values(l:project_package_src_dirs_reduced)
			let l:path_full = s:bob_base_path . '/' . l:path
			execute 'autocmd BufWinEnter ' . l:path_full . '/* lcd ' . l:path_full
		endfor
	augroup END
	let s:project_name = l:project_name
	let s:project_options = l:project_options
	let s:project_query_options = l:project_query_options
	let s:project_config = l:project_config
	let s:project_package_build_dirs = l:project_package_build_dirs
	let s:project_package_src_dirs = l:project_package_src_dirs
	let s:project_package_src_dirs_reduced = l:project_package_src_dirs_reduced

	echo 'generate configuration for YouCompleteMe …'
	call s:Ycm(a:package)

	" store bob command to file
	if writefile([l:project_command], s:bob_base_path . '/.vim-bob_project.log', 'a') == -1
		echom 'error writing to .vim-bob_project.log'
	endif
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
	" do build in the container
	call s:DevImpl(a:bang, l:package, 1, l:optionals)
endfunction

" we need this extra function to be able to forward optional parameters from
" other functions as well as commands. Forwarding from functions does work with
" a list of arguments exclusively, whereas commands provide optional arguments
" as separate variables (a:0, a:1, etc.).
function! s:DevImpl(bang, package, use_prefix, optionals)
	let l:command = 'cd ' . shellescape(s:bob_base_path) . ';'
	if a:use_prefix
		let l:command = l:command . ' ' . g:bob_prefix
	endif
	let l:command = l:command . ' bob dev ' . a:package
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

	try
		" we need to get the error code from the actual make command instead
		" of the `tee` command, therefore modifying &shellpipe temporarily
		let shellpipe = &shellpipe
		if &shellpipe ==# '2>&1| tee'
			let &shellpipe = '2>&1| tee %s;exit ${PIPESTATUS[0]}'
		endif
		execute 'make'.a:bang
	finally
		let &shellpipe = shellpipe
	endtry
	if v:shell_error
		throw 'Running Bob failed.'
	endif
	return &makeprg
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
	" not using g:bob_prefix here, because this would return the path inside
	" the container which is of no use on the host where we want to use YCM
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
	" translate path from inside the container to outside, where the LSP will
	" be used
	if ! empty(g:bob_prefix)
		let l:prefix_path = trim(system(g:bob_prefix . ' pwd'))
		" ensure that only the begin of a path is replaced
		" preciding characters are: double quotes, single quotes, equal signs,
		" include flags (`-i` and `-I`) and spaces that are not escaped with a
		" backslash
		let l:path_preceding_chars = '\(["''=]\| -i\| -I\|\(\\\)\@<! \)\zs'
		let l:pattern = l:path_preceding_chars . l:prefix_path . '/'
		let l:substitute = s:bob_base_path . '/'
		let l:text_subst = []
		for l:line in l:text
			let l:line_subst = substitute(l:line, l:pattern, l:substitute, 'g')
			let l:text_subst = add(l:text_subst, l:line_subst)
		endfor
		let l:text = l:text_subst
	endif
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
	if empty(s:project_name)
		throw 'I do not know what to draw. Run :BobProject before drawing a dependency graph!'
	endif
	if !exists('g:bob_graph_type')
		" using the same default as Bob currently uses (as of v0.16)
		let g:bob_graph_type = 'd3'
	endif

	" run `bob graph`
	let l:graph_type = '-t ' . g:bob_graph_type
	let l:filename = substitute(s:project_name, '[_:-]', '', 'g')
	" not using g:bob_prefix here, because this would return the path inside
	" the container assuming that the host is more likely capable of producing
	" graphs
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

function! s:SearchSource(pattern, bang)
	if empty(s:project_name)
		throw 'I do not know where to search. Run :BobProject before doing a search!'
	endif
	if ! executable('rg')
		throw '"rg" needs to be installed!'
	endif
	let l:old_path = getcwd()
	let l:spec = {'dir': s:bob_base_path}
	call fzf#vim#grep(
				\   'rg --column --line-number --no-heading --color=always ' 
				\  . (len(a:pattern) > 0 ? a:pattern : '""') . ' '
				\  . join(values(s:project_package_src_dirs_reduced), ' ')
				\  , 1,
				\   a:bang ? fzf#vim#with_preview(spec, 'up:60%')
				\           : fzf#vim#with_preview(spec, 'right:50%:hidden', '?'),
				\   a:bang)
endfunction

function! s:Persist()
	call s:CheckInit()
	if empty(s:project_name)
		throw 'I do not know what to persist. Run :BobProject before persisting the current state!'
	endif

	" TODO check for branches, these are not persistent, only commit-IDs and
	"      tags are
	" get the status of all repositories
	let l:package_list = {}
	let l:package_name = ''
	" not using g:bob_prefix here, because this would return the path inside
	" the container but we want to modify the source file on the host
	let l:query_command = 'bob status -rv ' . s:project_config . ' '
				\ . join(s:project_query_options, ' ') . ' ' . s:project_name
	let l:query_result = systemlist(l:query_command)
	echo 'Output of ''' . l:query_command . ''':'
	echo join(l:query_result, "\n")
	for l:line in l:query_result
		let l:package_match = matchlist(l:line, '^>> \([^ ]*\)')
		if len(l:package_match) > 1
			" found new package to parse
			let l:package_name = l:package_match[1]
			let l:package_list[l:package_name] = {}
		else
			" if we are currently parsing a package
			if ! empty(l:package_name)
				" ignoring 'u' because that is not of interest for persisting
				" as recipe, that's rather persisting the sources (but not the
				" currently used one)
				" also ignoring overrides, not sure if that is correct, though
				let l:package_status = matchlist(l:line, '^   STATUS \([ACEMNSU\?]*\)')
				if len(l:package_status) > 1
					let l:package_list[l:package_name]['status'] = l:package_status[1]
					if l:package_status[1] =~# '[ACEN\?]'
						let l:package_list[l:package_name]['error'] = 1
					else
						let l:package_list[l:package_name]['error'] = 0
					endif
					if l:package_status[1] =~# 'M'
						let l:package_list[l:package_name]['modified'] = 1
					else
						let l:package_list[l:package_name]['modified'] = 0
					endif
					if l:package_status[1] =~# 'S'
						let l:package_list[l:package_name]['switched'] = 1
					else
						let l:package_list[l:package_name]['switched'] = 0
					endif
					if l:package_status[1] =~# 'U'
						let l:package_list[l:package_name]['unpushed'] = 1
					else
						let l:package_list[l:package_name]['unpushed'] = 0
					endif
				endif
			endif
		endif
	endfor
	" find recipes that specify a branch
	let l:query_command = 'bob query-scm ' . s:project_config . ' '
				\ . join(s:project_query_options, ' ')
				\ . ' -r -f git="git {package} {branch}" '
				\ . s:project_name
				"\ . join(keys(s:project_package_src_dirs), ' ')
	let l:query_result = systemlist(l:query_command)
	for l:line in l:query_result
		" first group is the package name, second group ist the configured
		" branch, if any
		let l:match = matchlist(l:line, 'git \(\S*\) \(\S*\)')
		let l:package = l:match[1]
		if ! empty(l:match[2])
			let l:branch = l:match[2]
			if ! has_key(l:package_list, l:package)
				let l:package_list[l:package] = {}
			endif
			let l:package_list[l:package]['branched'] = 1
			let l:package_list[l:package]['branch'] = {}
			let l:package_list[l:package]['branch']['name'] = l:branch
			" get commit ID and tags pointing at the current commit, to
			" provide them as alternative to the branch
			let l:result = systemlist('git -C '.s:project_package_src_dirs[l:package].' rev-parse HEAD')
			let l:package_list[l:package]['branch']['commit'] = l:result[0]
			let l:result = systemlist('git -C '.s:project_package_src_dirs[l:package].' tag --points-at HEAD')
			let l:package_list[l:package]['branch']['tag'] = l:result
		"else
			"let l:package_list[l:package]['branched'] = 0
		endif
	endfor

	" do some statistics
	let l:error_list = []
	let l:repo_action_list = []
	let l:recipe_change_list = []
	let l:branch_list = []
	for l:package in items(l:package_list)
		" count errors
		if has_key(l:package[1], 'error') && l:package[1]['error']
			call add(l:error_list, l:package[0])
		endif
		" count necessary actions on source repositories
		if (has_key(l:package[1], 'modified') && l:package[1]['modified'])
					\ || (has_key(l:package[1], 'unpushed') && l:package[1]['unpushed'])
			call add(l:repo_action_list, l:package[0])
		endif
		" count necessary recipe changes
		if has_key(l:package[1], 'switched') && l:package[1]['switched']
			call add(l:recipe_change_list, l:package[0])
		endif
		" count recipes that specify branches
		if has_key(l:package[1], 'branched') && l:package[1]['branched']
			call add(l:branch_list, l:package[0])
		endif
	endfor
	" print status
	echo ''
	echo len(l:error_list) . ' repositories are in erronious state'
	if len(l:error_list) > 0
		echo '  ''' . join(l:error_list, ''', ''') . ''''
		echo 'see result of `bob status` for more information'
	endif
	echo len(l:repo_action_list) . ' repositories need action'
	if len(l:repo_action_list) > 0
		echo '  ''' . join(l:repo_action_list, ''', ''') . ''''
		echo '  see info comment at the first line of the recipe, commit changes and push them, delete comment afterwards'
		echo '  then re-run :BobPersist to check for success'
	endif
	echo len(l:recipe_change_list) . ' recipies need changes'
	if len(l:recipe_change_list) > 0
		echo '  ''' . join(l:recipe_change_list, ''', ''') . ''''
		echo '  change recipes according to info comment at the first line and delete the comment afterwards'
		echo '  then re-run :BobPersist to check for success'
	endif
	echo len(l:branch_list) . '  recipes configure branches'
	if len(l:branch_list) > 0
		echo '  ''' . join(l:branch_list, ''', ''') . ''''
		echo '  branches are not persistent'
		echo '  change recipes according to info comment at the first line and delet the comment afterwards'
		echo '  then re-run :BobPersist to check for success'
	endif
	if len(l:error_list) == 0 && len(l:repo_action_list) == 0 && len(l:recipe_change_list) == 0 && len(l:branch_list) == 0
		echo 'Recipies are up to date. Nothing to persist.'
	endif

	" adjust recipies
	let l:comment_begin = '# vim-bob persist:'
	for l:package_name in keys(l:package_list)
		let l:query = 'cd ' . shellescape(s:bob_base_path) . '; '
					\ . ' bob query-recipe' . s:project_config . ' '
					\ . join(s:project_query_options) . ' ' . l:package_name
		let l:query_result = systemlist(l:query)
		let l:idx = match(l:query_result, 'recipes\/')
		if l:idx == -1
			echoerr 'internal error: first line of output of `bob query-recipe`'
						\ . 'should contain a recipe file, but did not, '
						\ . 'query was: ' . l:query . ' result was: '
						\ . join(l:query_result, ' --- ')
			return
		endif
		let l:recipe_file = l:query_result[l:idx]
		let l:file_content = readfile(l:recipe_file)
		let l:comment = l:comment_begin . ' ''' . l:package_name . ''':'
		if has_key(l:package_list[l:package_name], 'modified') && l:package_list[l:package_name]['modified']
			let l:comment = l:comment . ' Commit your changes!'
		elseif has_key(l:package_list[l:package_name], 'switched') && l:package_list[l:package_name]['switched']
			let l:dir = s:project_package_src_dirs[l:package_name]
			let l:current_commit = trim(system('cd '.l:dir.' && git rev-parse HEAD'))
			let l:current_tags = trim(system('cd '.l:dir.' && git tag --points-at HEAD'))
			let l:comment = l:comment . ' Update SCM in recipe to commit ID '''
						\ . l:current_commit . ''''
			if !empty(l:current_tags)
				let l:comment = l:comment . ' or to tag(s) ''refs/tags/'
							\ . substitute(l:current_tags, ' ', ''' ''refs/tags/', 'g') . ''''
			endif
			let l:comment = l:comment . '!'
		elseif has_key(l:package_list[l:package_name], 'unpushed') && l:package_list[l:package_name]['unpushed']
			let l:comment = l:comment . ' Push to remote!'
		elseif has_key(l:package_list[l:package_name], 'branch')
			let l:comment = l:comment . ' Change from branch to commit '''
						\ . l:package_list[l:package_name]['branch']['commit'] . ''''
			if has_key(l:package_list[l:package_name]['branch'], 'tag')
				if len(l:package_list[l:package_name]['branch']['tag']) == 1
					let l:comment = l:comment . ' or to tag '''
								\ . l:package_list[l:package_name]['branch']['tag'] . ''''
				elseif len(l:package_list[l:package_name]['branch']['tag']) > 1
					let l:comment = l:comment . ' or to one of the tags: ''refs/tags/'
								\ . join(l:package_list[l:package_name]['branch']['tag'], ''', ''refs/tags/') . ''''
				endif
			endif
		endif
		" put persist comment as first line
		if l:file_content[0] =~# '^' . l:comment_begin
			" replace an existing persist comment, it makes no sense having
			" multiple of those in one file
			let l:file_content[0] = l:comment
		else
			" put comment before the current first line
			call insert(l:file_content, l:comment)
		endif
		call writefile(l:file_content, l:recipe_file)
	endfor
endfunction

function! s:OpenTelescope(dir)
" seems like we can only access global variables in Lua
let b:dir = a:dir
lua << EOF
require('telescope.builtin').find_files({ search_dirs = {vim.b.dir} })
EOF
unlet! b:dir
endfunction

function! s:OpenFzf(dir)
	" moving to the directory before calling FZF because FZF will try to
	" remain in the directory it was before being called, which does revert
	" the effect of the vim-bob autocmd (see FIXME comment in fzf.vim line
	" 590)
	" TODO how to avoid being in that dir, when FZF was abortet with <ESC>?
	execute 'lcd ' . a:dir
	call fzf#run({'dir': a:dir, 'sink': 'e'})
endfunction

function! s:Open(...)
	if a:0 == 0
		let l:dir = s:bob_base_path
	elseif exists('s:project_package_src_dirs_reduced')
		let l:dir = s:bob_base_path . '/' . s:project_package_src_dirs_reduced[a:1]
	else
		echoerr 'BobOpen is only available in a project context. Call BobProject first!'
		return
	endif
	" Prefering fzf.vim over telescope.nvim because for fzf we can provide a
	" path which avoids showing the complete path from the recipe repository
	" to the source repository during selection.
	if exists('g:loaded_fzf_vim')
		return s:OpenFzf(l:dir)
	endif
	if exists('g:loaded_telescope')
		return s:OpenTelescope(l:dir)
	endif
	message('No file selection backend found. Install fzf.vim or telescope.nvim to use :BobOpen')
endfunction

command! -nargs=? -complete=dir BobInit call s:Init("<args>")
command! BobClean call s:Clean()
command! BobGraph call s:Graph()
command! -bang -nargs=? -complete=custom,s:ProjectPackageComplete BobGoto call s:GotoPackageSourceDir("<bang>", 0, <f-args>)
command! -bang -nargs=? -complete=custom,s:PackageTreeComplete BobGotoAll call s:GotoPackageSourceDir("<bang>", 1, <f-args>)
command! -nargs=? -complete=custom,s:PackageTreeComplete BobStatus call s:GetStatus(<f-args>)
command! -nargs=1 -complete=custom,s:PackageTreeComplete BobCheckout call s:CheckoutPackage(<f-args>)
command! -bang -nargs=* -complete=custom,s:PackageAndConfigComplete BobDev call s:Dev("<bang>",<f-args>)
command! BobPersist call s:Persist()
command! -bang -nargs=* -complete=custom,s:PackageAndConfigComplete BobProject call s:Project("<bang>",<f-args>)
command! -nargs=* -complete=custom,s:PackageAndConfigComplete BobYcm call s:Ycm(<f-args>)
command! -bang -nargs=* BobSearchSource call s:SearchSource(<q-args>, <bang>0)
command! -nargs=? -complete=custom,s:ProjectPackageComplete BobOpen call s:Open(<f-args>)
