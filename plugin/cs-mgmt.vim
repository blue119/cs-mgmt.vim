" cs-mgmt.vim:   Vim plugin providing cscope's database management
" Author:           Yao-Po Wang
" HomePage:         https://bitbucket.org/blue119/cs-mgmt.vim
" Version:          0.4.1
" Note:
"       the name of reference file : {parent name}*_{reference_name}.out
"       all cscope's cross-reference file is place in g:CsMgmtRefHome that 
"       default setting is $HOME/.cs-mgmt/
"       
"       simple item -> \ {O|X}\ {db_name}\ {timestamp}\ [Attach]
"       a projet -> \ {prj_name}
"                      \ \ \ \ \ {O|X}\ {db_name}\ {timestamp}\ [Attach]
"
" Usage:
"      :Csmgmtadd {'file' | 'url'} {file path} [{reference name}] [{parent path}]
"      it is going to take source code from file, web url, or dpkg, and put it
"      to your g:CsMgmtRefHome/.source. it will add this source item to json file
"      as well.
"
"      taking from apt, it will get source from apt mirrot server and do
"      dpkg-source. it would provide a buffer to show mult-candidate when the
"      package term is not precision.
"
"      take from file procedure: Now it only support tarball file
"          1. checking file readable
"          2. copy to g:CsMgmtRefHome/.source, and then unpack it
"          3. add this item to json struct, and then write to file
"          4. udpate the buffer of the cs-mgmt
"          

if exists('g:loaded_cs_mgmt') || &cp
  finish
endif

if !exists('chk_cscope_cmd')
    if executable('cscope')
        let cscope_cmd = 'cscope'
    else
        echomsg 'cs-mgmt: cscope command not found in PATH.'
        finish
    endif
endif
let g:loaded_cs_mgmt = 1

" debug mode on/off
let s:debug_enable = 0
func! s:dprint(...)
    if s:debug_enable
        call Decho(a:000)
    endif
endf

" echo for warning
func! s:echo_waring(msg)
    echohl WarningMsg 
        \ | echo a:msg
        \ | echohl None
endf

" where are your database
if !exists('g:CsMgmtRefHome')
    let g:CsMgmtRefHome = $HOME.'/.cs-mgmt/'
endif

" where are your config file
" by default, it will be put on $HOME/.cs-mgmt.json
if !exists('g:CsMgmtDbFile')
    let g:CsMgmtDbFile = g:CsMgmtRefHome.'/.cs-mgmt.json'
endif

" with CsMgmtAdd, that all source will be put into the folder.
if !exists('g:CsMgmtSrcDepot')
    let g:CsMgmtSrcDepot = g:CsMgmtRefHome . '.source_depot/'
endif

" re-attach the refernece file after rebuild
if !exists('g:CsMgmtReAttach')
    let g:CsMgmtReAttach = 1
endif

" It will also create a tags file of ctags after creating referencing file of 
" cscope
if exists('g:CsMgmtCtags') && g:CsMgmtCtags == 1
	if executable('ctags')
		let ctags_cmd = 'ctags'
	else
		echomsg 'cs-mgmt: ctags command not found in PATH.'
		echomsg 'cs-mgmt: disable g:CsmgmtCtags variable.'
		let g:CsMgmtCtags = 0
	endif
else
	let g:CsMgmtCtags = 0
endif

func! s:cm_add_tag_to_tags(tag)
	exec printf("set tags=%s;%s", &tags, a:tag)
endf

func! s:cm_del_tag_from_tags(tag)
	let l:new_tags = ""
	for t in split(&tags, ";")
		if t != a:tag
			if l:new_tags == ""
				let l:new_tags = t
			else
				let l:new_tags = l:new_tags . ';' . t
			endif
		endif
	endfor
	exec printf("set tags=%s", l:new_tags)
endf

func! s:cm_get_src_from_file(path)
    if !filereadable(a:path)
        call s:echo_waring( a:path . ' is not readable.' )
        return -1
    endif

    let l:decomp_cmd = ''
    let l:tmpfolder = ''
    " to check compressed type
    " TODO: tmpfolder should using makename
    " TODO: filename can add a random number on postfix
    if a:path[-len(".tar.gz"):] == ".tar.gz"
        let l:filename = split(a:path, '\/')[-1][:-len(".tar.gz")-1]
        let l:tmpfolder = g:CsMgmtSrcDepot . l:filename . '.tmp'
        let l:decomp_cmd = 'tar zxvf ' . a:path . ' -C ' . l:tmpfolder 
    elseif a:path[-len(".tar.bz2"):] == ".tar.bz2"
        let l:filename = split(a:path, '\/')[-1][:-len(".tar.bz2")-1] 
        let l:tmpfolder = g:CsMgmtSrcDepot . l:filename . '.tmp'
        let l:decomp_cmd = 'tar jxvf ' . a:path . ' -C ' . l:tmpfolder
    else
        echo 'the type of file do not support.'
        return -1
    endif

    if isdirectory(l:tmpfolder)
        echo l:tmpfolder . ' folder conflict!! you have to remove it before.'
        return -1
    else
        " 1. create a tmp folder on g:CsMgmtSrcDepot that name is its file name.
        if mkdir(l:tmpfolder) != 1
            call s:echo_waring( 'Can not create the tmpfolder ' . l:tmpfolder )
            return -1
        endif
    endif

    " 2. decompress into tmp folder
    let ret = split(system(l:decomp_cmd), '\n')

    " 3. if only one folder on tmp folder and same as ret[0]
    "   move the folder to up-layer and del the tmp folder
    " 4. if there are more file in the tmp folder, the tmp folder will
    " become real folder
    if match(ret[0], 'tar:') == 0
        let ret = ret[1:]
    endif

    let l:first_folder = ret[0]
    let l:bundle = 1
    for f in ret[1:]
        if match(f, l:first_folder, 0) != 0
            let l:bundle = 0
        endif
    endfor

    if l:bundle == 1
        let l:finalfolder = g:CsMgmtSrcDepot . l:first_folder
        if isdirectory(l:finalfolder)
            call system('rm -rf ' . l:tmpfolder)
            call s:echo_waring( l:finalfolder 
                    \ . ' folder conflict!! you have to remove it before.' )
            return -1
        else
            call system( 
                \ printf('mv %s/%s %s', l:tmpfolder, l:first_folder, l:finalfolder))
            call system('rm -rf ' . l:tmpfolder)
        endif
    else
        let l:finalfolder = g:CsMgmtSrcDepot . l:filename
        " call s:dprint(printf('mv %s %s', l:tmpfolder, l:finalfolder))
        call system(printf('mv %s %s', l:tmpfolder, l:finalfolder))
    endif

    return l:finalfolder
endf

func! s:cm_get_src_from_dir(path)
    if !isdirectory(a:path)
        call s:echo_waring( a:path . ' is not a directory.' )
        return
    endif

    return a:path
endf

" to verify the name conflict of grouping path in CsMgmtDb
" return [g_parent, g_name]
func! s:parser_grouping_name(group)
    " to check reserved words in g_name excepting '/' word, and
    " reduce the repeating '/' to onece.
    let l:g_name = []
    let l:g_parent = []
    for i in split(a:group, "/")
        if len(i)
            if len(s:cm_filename_resv_words(i))
                call s:echo_waring("Don't contain reserved words in group name.")
                return
            endif
            call add(l:g_name, i)
        endif
    endfor

    let l:db = copy(s:cm_get_db())
    while len(l:g_name)
        let k = l:g_name[0]
        if has_key(l:db, k)
            if type(l:db[k]) != 4
                call s:echo_waring("name conflict.")
                return
            endif
            call add(l:g_parent, k)
            call remove(l:g_name, 0)
            let l:db = l:db[k]
        else
            break
        endif
    endwhile
    return [l:g_name, l:g_parent]
endf

" Examples
" :CsMgmtAdd file /home/blue119/iLab/gspca-ps3eyeMT-0.5.tar.gz
" :CsMgmtAdd dir /home/blue119/iLab/vte/lilyterm-0.9.8
func! CsMgmtAdd(...) abort
    " a:000[0]: protocol
    " a:000[1]: file path
    " a:000[2]: ref_name <- it is not necessary.
    " a:000[3]: group <- it is not necessary.
    if len(a:000) > 4 || len(a:000) < 2
        echo ":Csmgmtadd {dir|file} {src path} [{ref_name}]"
        echo "    example: :Csmgmtadd dir /tmp/foo"
        echo "    example: :Csmgmtadd dir /tmp/foo bar"
        echo " "
        echo ":Csmgmtadd {dir|file} {src path} {ref_name} [group]"
        echo "    example: :Csmgmtadd dir /tmp/foo bar fooBar"
        echo "    example: :Csmgmtadd dir /tmp/foo bar fooBar/Foobar"
        return
    endif

    if !exists('g:cm_view') 
        if s:cm_init_check() == -1
            return
        endif
    endif

    if !isdirectory(g:CsMgmtSrcDepot)
        call mkdir(g:CsMgmtSrcDepot)
    endif

    " TODO: json - add lot of entry at one time.
    " let l:prot_type = ['file', 'dir', ]
    let l:prot_type = ['file', 'dir']
    let l:argc = len(a:000)
    let l:type = a:000[0]
    let l:path = a:000[1]
    let l:ref_name = ''
    let l:grp_parent = []
    let l:grp_new = []

    if l:argc > 2
        let l:ref_name = a:000[2]

        " check reserved words in filename
        if len(s:cm_filename_resv_words(l:ref_name))
            call s:echo_waring("Don't contain reserved words in ref_name.")
            return
        endif

        if l:argc == 4
            let l:grouping = s:parser_grouping_name(a:000[3])
            " if correct, it should return length 2.
            if len(l:grouping) == 1
                return
            endif

            let l:grp_new = l:grouping[0]
            let l:grp_parent = l:grouping[1]
        endif

        if !len(l:grp_new)
            "check key whenter existed in json befor
            let l:db = s:cm_get_db()

            " roll into its parent
            for k in l:grp_parent
                let l:db = l:db[k]
            endfor

            if has_key(l:db, l:ref_name)
                call s:echo_waring( l:ref_name . " has existed in " 
                            \ . join(l:grp_parent, "/") . ".")
                return
            endif
        endif " if len(l:grp_new)
    endif

    let l:type_func = ''
    for t in l:prot_type
        if l:type == t
            let l:type_func = 's:cm_get_src_from_' . l:type
            if l:type_func == -1
                return -1
            endif
        endif
    endfor

    if l:type_func == ''
        call s:echo_waring( 'Not support '. l:type .' protocol type' )
        return
    endif

    " symbol replacement
    if l:path[0] == '~'
        let l:path = $HOME . l:path[1:]
    elseif l:path[0:2] == '../'
        let l:path = $PWD . '/' . l:path
    elseif l:path[0:1] == './'
        let l:path = $PWD . l:path[1:]
    elseif l:path[0:3] == '$PWD'
        let l:path = $PWD . l:path[4:]
    else
        let l:path = $PWD . '/' . l:path
    endif

    let l:path = simplify(l:path)

    let l:source_path = eval(l:type_func . '("' . l:path . '")')

    if l:source_path == ''
        echoerr 'program error ??'
        echoerr 'type_func: ' . l:type_func
        echoerr 'path: ' . l:path
        return
    endif

    if l:ref_name == ''
        let l:ref_name = split(l:source_path, '/')[-1]
    endif

    " craete add_dict
    let l:add_dict = {}
    if len(l:grp_new) != 0
        let l:grp_new = reverse(l:grp_new)
        let l:add_dict[l:grp_new[0]] = {l:ref_name : [l:source_path]}
        call remove(l:grp_new, 0)

        while len(l:grp_new)
            let l:add_dict = {l:grp_new[0]:copy(l:add_dict)}
            call remove(l:grp_new, 0)
        endwhile
    endif

    " find adding entrance
    let l:db = s:cm_get_db()
    while len(l:grp_parent)
        let l:db = l:db[l:grp_parent[0]]
        call remove(l:grp_parent, 0)
    endwhile

    if len(l:add_dict)
        let l:db[keys(l:add_dict)[0]] = values(l:add_dict)[0]
    els
        let l:db[l:ref_name] = [l:source_path]
    endif

    call s:cm_json2file()
    call s:cm_buf_refresh(line("."))
endf

func! CsMgmt() abort
    if s:cm_init_check() == -1
        return
    endif

    call s:cm_buf_show(s:cm_buf_view(s:cm_get_db()))
endf

func! s:cm_buf_view(json)
    let l:view_data = []
    for k in keys(a:json)

        " if it is simple prj, just show it
        if type(a:json[k]) == 1
            call add(l:view_data, s:cm_show_item_construct(0, '', k))

        elseif type(a:json[k]) == 3
            call add(l:view_data, s:cm_show_item_construct(0, '', k))

        " it is a ref config
        elseif type(a:json[k]) == 4
            let l:deep_collect = []
            call add(l:view_data, printf('%s:', k))
            call s:cm_deep_grp_collect(0, l:deep_collect, a:json[k], k)
            for d in l:deep_collect
                call add(l:view_data, d)
            endfor
        endif
    endfor

    return l:view_data
endf

func! s:cm_deep_grp_collect(indent_level, collect_list, config, parent)
    let l:indent_level = a:indent_level + 1

    for k in keys(a:config)
        if type(a:config[k]) == 3
            call add(a:collect_list, 
                    \ s:cm_show_item_construct(l:indent_level, a:parent, k))
        elseif type(a:config[k]) == 4
            call add(a:collect_list, printf('%s:', s:cm_str_add_indent(l:indent_level, k)))
            call s:cm_deep_grp_collect(l:indent_level, a:collect_list, 
                        \ a:config[k], printf('%s_%s', a:parent, k))
        endif
    endfor
endf

func! s:cm_str_add_indent(indent_level, str)
    return repeat(s:cm_indent_token, a:indent_level).a:str
endf

let s:ref_exist_token = 'O'
let s:ref_nonexist_token = 'X'
let s:cm_indent_token = '    '
if !exists('s:ref_attach_list')
    let s:ref_attach_list = []
endif

" let s:db_item_re = '\(^\s*\)'
                " \ .'\(['.db_exist_token.db_nonexist_token.']\)\s'
                " \ .'\(\w*\)\s'
                " \ .'\(\d\{8}T\d\{6}Z\)\s\{}'
                " \ .'\(Attach\)\{}'

let s:ref_grp_re = '\(^\s\{}\)'
                \ .'\(.*\):'

let s:ref_nonexist_re = '^\(\s\{}\)'
                \ .'\([OX]\)\s'
                \ .'\([0-9a-zA-Z\-._~+]\{}\)\s\{}'

let s:ref_exist_re = '^\(\s\{}\)'
                \ .'\([OX]\)\s'
                \ .'\([0-9a-zA-Z\-._~+]\{}\)\s\{}'
                \ .'\(\d\{4}\.\d\{2}\.\d\{2}\s\d\{2}\:\d\{2}\)'
                \ .'\(Attach\)\{}'


" Reserved characters and words
func! s:cm_filename_resv_words(str)
    let l:resv_words_re = '[\/\\\?\%\*\:\|\"\>\<]'
    return matchstr(a:str, l:resv_words_re)
endf

func! s:cm_str_strip(str)
    let l:str_strip_re = '^\s\{}\(.*\)\s\{}$'
    let l:l = matchstr(a:str, l:str_strip_re)
    return substitute(l:l, l:str_strip_re, '\1', '')
endf

func! s:cm_get_rep(line)
    let l:str = s:cm_str_strip(a:line)

    if l:str[-1:] == ':'
        return s:ref_grp_re
    elseif l:str[0:len(s:ref_exist_token)-1] == s:ref_exist_token
        return s:ref_exist_re
    elseif l:str[0:len(s:ref_nonexist_token)-1] == s:ref_nonexist_token
        return s:ref_nonexist_re
    endif
endf

func! s:get_ref_item_indent(line)
    let l:rep = s:cm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\1', '')
endf

func! s:get_ref_item_status(line)
    let l:rep = s:cm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\2', '')
endf

func! s:get_ref_item_name(line)
    let l:rep = s:cm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\3', '')
endf

func! s:get_ref_item_timestamp(line)
    let l:rep = s:cm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\4', '')
endf

func! s:get_ref_item_attach(line)
    let l:rep = s:cm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\5', '')
endf

func! s:cm_which_level_is_it(line)
    return (len(s:get_ref_item_indent(a:line))/len(s:cm_indent_token))
endf

func! s:cm_show_item_construct(indent_level, parent, ref_name)
    " return string format 'l:ref_status_token l:db_name l:ref_ftime l:db_attach'
    let l:ref_full_name = (a:parent == '') ? 
                \   (a:ref_name):
                \   (a:parent.'_'.a:ref_name)
    let l:ref_status_token = s:ref_nonexist_token
    let l:ref_attach = ''
    let l:ref_indent = repeat(s:cm_indent_token, a:indent_level)

    " to check the status of the reference file
    " call s:dprint(g:CsMgmtRefHome.l:ref_full_name.'.out')
    if filereadable(g:CsMgmtRefHome.l:ref_full_name.'.out')
        let l:ref_status_token = s:ref_exist_token
        let l:ref_ftime = strftime("%Y.%m.%d %H:%M", 
                    \ getftime(g:CsMgmtRefHome.l:ref_full_name.'.out'))

        if index(s:ref_attach_list, l:ref_full_name) != -1
            let l:ref_attach = ' Attach'
        endif
    endif

    if l:ref_status_token == s:ref_exist_token
        return printf("%s%s %s %s%s", 
                    \ l:ref_indent, l:ref_status_token, 
                    \ a:ref_name, l:ref_ftime, l:ref_attach)
    else
        return printf("%s%s %s", l:ref_indent, l:ref_status_token, a:ref_name)
    endif
endf

func! s:cm_chk_new_RefHome()
    if !isdirectory(g:CsMgmtRefHome)
        if filereadable(g:CsMgmtRefHome)
            call s:echo_waring( g:CsMgmtRefHome . " must be a directory." )
            return -1
        endif

        if mkdir(g:CsMgmtRefHome) != 1
            call s:echo_waring( 'Can not create ' . g:CsMgmtRefHome)
            return -1
        endif
    endif
endf

func! s:cm_init_check()
    if !filereadable(g:CsMgmtDbFile)
        call s:echo_waring( "you need have a config file befor" )
        return -1
    endif

    if s:cm_chk_new_RefHome() == -1
        return -1
    endif
endf

func! s:cm_get_db_from_file()
    if !filereadable(g:CsMgmtDbFile)
		if s:cm_chk_new_RefHome() == -1
			return -1
		endif

        " default config
        call writefile(["{'usr_include' : ['/usr/include/', ],}"], g:CsMgmtDbFile )
    endif

    return eval(join(readfile(g:CsMgmtDbFile)))
endf

func! s:cm_get_db()
    if !exists('s:CsMgmtDb') || &cp
        let s:CsMgmtDb = s:cm_get_db_from_file()
    endif

    return s:CsMgmtDb
endf

" look down and only included more level than it until it run into a blank line
func! s:cm_get_children_pos_list_from_buf(level, line, pos)
    let l:pos = a:pos
    let l:level = a:level
    let l:children_pos_list = []

    while 1
        let l:pos += 1
        if s:cm_which_level_is_it(getline(l:pos)) > (l:level) 
                \ && s:cm_is_it_a_unexpect_line(getline(l:pos)) == 0
            call insert(l:children_pos_list, l:pos, 0)
        endif

        if s:cm_is_it_a_blank_line(getline(l:pos)) == 1
            break
        endif
    endwhile

    return l:children_pos_list
endf

func! s:cm_get_parent_list_from_buf(level, line, pos)
    let l:pos = a:pos
    let l:level = a:level
    let l:parent_list = []

    if l:level == 0
        return ''
    endif

    while 1
        let l:pos -= 1
        if s:cm_which_level_is_it(getline(l:pos)) == (l:level - 1)
            call insert(l:parent_list, s:cm_str_strip(getline(l:pos))[:-2], 0)
            let l:level -= 1

            if s:cm_which_level_is_it(getline(l:pos)) == 0
                break
            endif
        endif

        if l:pos == 0
            "feel more safe
            echoerr 'program error'
            exit
        endif
    endwhile

    return l:parent_list
endf

func! s:cm_is_it_a_comment(line)
    if a:line[0] == '"' 
        return 1
    else
        return 0
    endif
endf

func! s:cm_is_it_a_group_title(line)
    if a:line[-1:] == ':'
        return 1
    else
        return 0
    endif
endf

func! s:cm_is_it_a_blank_line(line)
    if a:line == '' 
        return 1
    else
        return 0
    endif
endf

func! s:cm_is_it_a_unexpect_line(line)
    if   s:cm_is_it_a_blank_line(a:line)
    \ || s:cm_is_it_a_group_title(a:line)
    \ || s:cm_is_it_a_comment(a:line)
        return 1
    else
        return 0
    endif
endf

func! s:cm_get_write_mode()
    setl buftype=
    setl modifiable
endf

func! s:cm_get_readonly_mode()
    setl nomodifiable
    setl buftype=nofile
endf

func! CsMgmtAttachByGroup(line, pos)
    if s:cm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtAttach(getline(p), p)
    endfor
endf

func! CsMgmtDetachByGroup(line, pos)
    if s:cm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtDetach(getline(p), p)
    endfor
endf

func! CsMgmtBuildByGroup(line, pos)
    if s:cm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtBuild(getline(p), p)
    endfor
endf

func! CsMgmtRebuildByGroup(line, pos)
    if s:cm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtRebuild(getline(p), p)
    endfor
endf

func! CsMgmtAttach(line, pos)
    if s:cm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    if s:cm_str_strip(a:line)[0] == s:ref_nonexist_token
        call s:echo_waring("Hasn't build") 
        return
    endif

    let l:ref_level = s:cm_which_level_is_it(a:line)
    let l:parent_list = s:cm_get_parent_list_from_buf(l:ref_level, a:line, a:pos)
    let l:ref_name = s:get_ref_item_name(a:line)

    let l:ref_full_name = (len(l:parent_list) == 0) ? 
                \   (l:ref_name):
                \   (join(l:parent_list, '_').'_'.l:ref_name)

    if index(s:ref_attach_list, l:ref_full_name) != -1
        " call s:echo_waring("Don\'t Attach Twice") 
        return
    endif

    " add to attach list
    call add(s:ref_attach_list, l:ref_full_name)

    " add a Attach word on the end of line
    call s:cm_get_write_mode()
    call setline(a:pos, a:line." Attach")
    call s:cm_get_readonly_mode()
 
    exec "cs add ".g:CsMgmtRefHome.l:ref_full_name.'.out'
	
	" for ctags
	if g:CsMgmtCtags == 1
		call s:cm_add_tag_to_tags(g:CsMgmtRefHome . l:ref_full_name . '.tags')
	endif
endf

func! s:cm_del_db(line, pos)
    if s:cm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    " if it has attached
    call CsMgmtDetach(a:line, a:pos)

    " look for key of deletion
    let l:ref_level = s:cm_which_level_is_it(a:line)
    let l:parent_list = s:cm_get_parent_list_from_buf(l:ref_level, a:line, a:pos)
    let l:ref_name = s:get_ref_item_name(a:line)
    let l:parent_key = s:cm_get_db()

    if len(l:parent_list)
        for p in l:parent_list
            let l:parent_key = l:parent_key[p]
        endfor
    endif

	let l:suffixs = ['.files', '.out', '.out.in', '.out.po']

	if g:CsMgmtCtags == 1
		call add(l:suffixs, '.tags')
	endif

    for suffix in l:suffixs
        call delete(g:CsMgmtRefHome . l:ref_name . suffix)
    endfor

    " delete
    unlet l:parent_key[l:ref_name]
endf

func! s:cm_del_db_by_group(line, pos)
    " find childrens
    let l:level = s:cm_which_level_is_it(a:line)
    let l:ref_name = s:cm_str_strip(getline(a:pos))[:-2]
    let l:pos = a:pos

    while 1
        let l:pos += 1
        if s:cm_which_level_is_it(getline(l:pos)) <= l:level
            break
        endif

        let l:line = getline(l:pos)
        if s:cm_is_it_a_unexpect_line(l:line) == 0
            " echo l:line
            call s:cm_del_db(l:line, l:pos)
        endif
    endwhile

    let l:parent_list = s:cm_get_parent_list_from_buf(l:level, a:line, a:pos)
    let l:parent_key = s:cm_get_db()

    if len(l:parent_list)
        for p in l:parent_list
            let l:parent_key = l:parent_key[p]
        endfor
    endif

    " delete
    unlet l:parent_key[l:ref_name]
endf

func! CsMgmtOpenAllFile(line, pos)

    if s:cm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    if s:cm_str_strip(a:line)[0] == s:ref_nonexist_token
        call s:echo_waring("You have not built its cross-reference.") 
        return
    endif

    " look for key of its full name.
    let l:ref_level = s:cm_which_level_is_it(a:line)
    let l:parent_list = s:cm_get_parent_list_from_buf(l:ref_level, a:line, a:pos)
    let l:ref_name = s:get_ref_item_name(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ? 
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:ref_full_name = (l:parent == '') ? 
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    let l:abs_path = g:CsMgmtRefHome . l:ref_full_name . ".files"
    let l:file_list = readfile(l:abs_path)
    
    " move to main buffer
    wincmd l

    " let l:time_s = localtime()

    " open all file into buffer
    for f in l:file_list
        exec "edit " . f
    endfor

    " let l:elapsed = localtime() - l:time_s
    " echo "Spend " . l:elapsed
    "
    " back to menu buffer
    wincmd h

endf

func! CsMgmtDelete(line, pos)
    if s:cm_is_it_a_unexpect_line(a:line) == 1
        if s:cm_is_it_a_group_title(a:line) == 1
            " delete a group
            call s:cm_del_db_by_group(a:line, a:pos)
            call s:cm_json2file()
            call s:cm_buf_refresh(line("."))
        endif
    else
        call s:cm_del_db(a:line, a:pos)
        call s:cm_json2file()
        call s:cm_buf_refresh(line("."))
    endif
endf

func! CsMgmtDetach(line, pos)
    if s:cm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    let l:ref_level = s:cm_which_level_is_it(a:line)
    let l:parent_list = s:cm_get_parent_list_from_buf(l:ref_level, a:line, a:pos)
    let l:ref_name = s:get_ref_item_name(a:line)

    let l:ref_full_name = (len(l:parent_list) == 0) ? 
                \   (l:ref_name):
                \   (join(l:parent_list, '_').'_'.l:ref_name)

    if index(s:ref_attach_list, l:ref_full_name) == -1
        " call s:echo_waring("Need Attach Befor") 
        return
    endif

    " remove from attach list
    call filter(s:ref_attach_list, 'v:val !~ "'.l:ref_full_name.'"')

    " add a Attach word on the end of line
    call s:cm_get_write_mode()
    call setline(a:pos, a:line[0:-len(" Attach")-1])
    call s:cm_get_readonly_mode()
 
    exec "cs kill ".g:CsMgmtRefHome.l:ref_full_name.'.out'

	" for ctags
	if g:CsMgmtCtags == 1
		call s:cm_del_tag_from_tags(g:CsMgmtRefHome . l:ref_full_name . '.tags')
	endif
endf

func! s:cm_path_walk(path, all_file_list)
    let l:file_list = split(globpath(a:path, '*'), '\n')
    for file in l:file_list
        if isdirectory(file)
            call s:cm_path_walk(file, a:all_file_list)
        else
            if match(file, '\.[chsS]$') >= 0 ||
                \ match(file, '\.cpp$') >= 0 ||
                \ match(file, '\.cxx$') >= 0 ||
                \ match(file, '\.CC$') >= 0 ||
                \ match(file, '\.hpp$') >= 0 ||
                \ match(file, '\.hxx$') >= 0
                call add(a:all_file_list, file)
            endif
        endif
    endfor
endf

func! s:cm_db_cs_build(ref_name)
    let l:cmd_string = printf('cd %s && cscope -b -q -k -i%s.files -f%s.out', 
            \ g:CsMgmtRefHome, a:ref_name, a:ref_name)

    echohl TabLine
        \ | echo a:ref_name.' building for cscope .... '
        \ | echohl None
    call system(l:cmd_string)
    echohl Title
        \ | echo a:ref_name.' built success.'
        \ | echohl None
endf

func! s:cm_db_ctags_build(ref_name)
    let l:cmd_string = printf('cd %s && ctags -L %s.files -f %s.tags', 
            \ g:CsMgmtRefHome, a:ref_name, a:ref_name)

    echohl TabLine
        \ | echo a:ref_name.' building for ctags .... '
        \ | echohl None
    call system(l:cmd_string)
    echohl Title
        \ | echo a:ref_name.' built success.'
        \ | echohl None
endf

func! s:cm_get_path_list_from_config(parent_list, ref_name)
    let l:config = s:cm_get_db()

    if len(a:parent_list) > 0
        for p in a:parent_list
            let l:config = config[p]
        endfor
    endif

    return l:config[a:ref_name]
endf

func! CsMgmtBuild(line, pos)
    if s:cm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    let l:ref_level = s:cm_which_level_is_it(a:line)
    let l:parent_list = s:cm_get_parent_list_from_buf(l:ref_level, a:line, a:pos)
    let l:ref_name = s:get_ref_item_name(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ? 
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:ref_full_name = (l:parent == '') ? 
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    if filereadable(g:CsMgmtRefHome.l:ref_full_name.'.out')
        let l:msg = "it has existed on " . g:CsMgmtRefHome 
                    \ . ' you can try to rebuild it.'
        call s:echo_waring(l:msg)
        return
    endif

    " file create
    call writefile(l:all_file_list, g:CsMgmtRefHome.l:ref_full_name.'.files')

    let l:path_list = s:cm_get_path_list_from_config(l:parent_list, l:ref_name)

    " if type(l:path_list) == 1
        " let l:path_list = [l:path_list]
    " endif

    echohl TabLineFill
        \ | echo l:ref_name.' collecting.... '
        \ | echohl None

    let l:include_path_list = []
    let l:knock_out_path_list = []
    for p in (type(l:path_list) == 1 ? [l:path_list] : l:path_list)
        if p[0] == '-'
            call add(l:knock_out_path_list, p[1:])
        else
            call add(l:include_path_list, p)
        endif
    endfor

    for p in l:include_path_list
        call s:cm_path_walk(p, l:all_file_list)
    endfor

    for p in l:knock_out_path_list
        call filter(l:all_file_list, 'v:val !~ "'. p .'"')
    endfor

    if len(l:all_file_list) == 0
        let l:msg =  'It is not finish to build cscope reference,'
            \ .  ' because no fidning any c or cpp file in ' . l:include_path_list
        call s:echo_waring(l:msg)
        return
    endif

    " write to file
    call writefile(l:all_file_list, g:CsMgmtRefHome.l:ref_full_name.'.files')

    " real build for cscope
    call s:cm_db_cs_build(l:ref_full_name)

    " real build for ctags
	if g:CsMgmtCtags == 1
		call s:cm_db_ctags_build(l:ref_full_name)
	endif

    " add a Attach word on the end of line
    call s:cm_get_write_mode()
    call setline(a:pos,
        \ s:cm_show_item_construct(l:ref_level, l:parent, l:ref_name))
    call s:cm_get_readonly_mode()
endf

func! CsMgmtRebuild(line, pos)
    if s:cm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    let l:ref_level = s:cm_which_level_is_it(a:line)
    let l:parent_list = s:cm_get_parent_list_from_buf(l:ref_level, a:line, a:pos)
    let l:ref_name = s:get_ref_item_name(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ? 
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:ref_full_name = (l:parent == '') ? 
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    if !filereadable(g:CsMgmtRefHome.l:ref_full_name.'.out')
        let l:msg =  l:ref_name.' not existed on '.g:CsMgmtRefHome.
                    \ ' you have to build it at first.'
        call s:echo_waring(l:msg)
        return
    endif

    " file create
    call writefile(l:all_file_list, g:CsMgmtRefHome.l:ref_full_name.'.files')

    let l:path_list = s:cm_get_path_list_from_config(l:parent_list, l:ref_name)

    " if type(l:path_list) == 1
        " let l:path_list = [l:path_list]
    " endif

    echohl TabLineFill
        \ | echo l:ref_name.' collecting.... '
        \ | echohl None

    let l:include_path_list = []
    let l:knock_out_path_list = []
    for p in (type(l:path_list) == 1 ? [l:path_list] : l:path_list)
        if p[0] == '-'
            call add(l:knock_out_path_list, p[1:])
        else
            call add(l:include_path_list, p)
        endif
    endfor

    for p in l:include_path_list
        call s:cm_path_walk(p, l:all_file_list)
    endfor

    for p in l:knock_out_path_list
        call filter(l:all_file_list, 'v:val !~ "'. p .'"')
    endfor

    if len(l:all_file_list) == 0
        let l:msg =  'It is not finish to build cscope reference,'
            \ .  ' because no fidning any c or cpp file in ' . l:path_list
        call s:echo_waring(l:msg)
        return
    endif

    " write to file
    call writefile(l:all_file_list, g:CsMgmtRefHome.l:ref_full_name.'.files')

    " real build for cscope
    call s:cm_db_cs_build(l:ref_full_name)

    " real build for ctags
	if g:CsMgmtCtags == 1
		call s:cm_db_ctags_build(l:ref_full_name)
	endif

    " add a Attach word on the end of line
    call s:cm_get_write_mode()
    call setline(a:pos,
        \ s:cm_show_item_construct(l:ref_level, l:parent, l:ref_name))
    call s:cm_get_readonly_mode()

    if g:CsMgmtReAttach == 1 && index(s:ref_attach_list, l:ref_full_name) != -1
        call CsMgmtDetach(a:line, a:pos)
        call CsMgmtAttach(a:line[0:-len(" Attach")-1], a:pos)
    endif
endf

func! s:cm_json_dip(indent_level, value)
    for item in items(a:value)
        let l:il = a:indent_level
        let l:key = item[0]
        unlet! l:value
        let l:value = item[1]
        let l:vt = type(l:value)

        if l:vt == 1
            call add(s:json2file_list, 
                        \   repeat(s:cm_indent_token, l:il) . 
                        \   "'" . l:key . "'" . 
                        \   " : " . "'" . l:value . "', " )

        elseif l:vt == 3
            call add(s:json2file_list, 
                    \ repeat(s:cm_indent_token, l:il) . 
                    \ "'" . l:key . "'" . " : " . "[")

            let l:il += 1
            for i in l:value
                call add(s:json2file_list, 
                        \ repeat(s:cm_indent_token, l:il) . 
                        \ "'" . i . "', ")
            endfor
            let l:il -= 1
            call add(s:json2file_list, repeat(s:cm_indent_token, l:il) . "], ")

        elseif l:vt == 4
            call add(s:json2file_list, 
                    \ repeat(s:cm_indent_token, l:il) . 
                    \ "'" . l:key . "'" . " : " . "{")

            let l:il += 1
            call s:cm_json_dip(l:il, l:value) 
            let l:il -= 1
            call add(s:json2file_list, repeat(s:cm_indent_token, l:il) . "}, ")
        endif
    endfor 
endf

func! s:cm_json2file()
    let s:json2file_list = []
    let l:indent_level = 0
    let l:json = s:cm_get_db()

    call add(s:json2file_list, '{') 
    let l:indent_level += 1
    call s:cm_json_dip(l:indent_level, l:json) 
    call add(s:json2file_list, '}') 
    call writefile(s:json2file_list, g:CsMgmtDbFile)
endf

func! s:cm_buf_color()
    hi cm_ref_grp_name ctermfg=cyan guifg=cyan
    call matchadd('cm_ref_grp_name', '^\s\{}\([0-9a-zA-Z\-._~]*\):')

    hi cm_ref_name ctermfg=yellow guifg=yellow
    call matchadd('cm_ref_name', '^\s\{}[OX]\s\(.*\)$')

    hi cm_timestamp ctermfg=darkgreen guifg=darkgreen
    call matchadd('cm_timestamp', '\d\{4}\.\d\{2}\.\d\{2}\s\d\{2}\:\d\{2}')

    hi cm_ref_attach ctermfg=darkblue guifg=darkblue
    call matchadd('cm_ref_attach', '\ Attach$')

    hi cm_ref_item_status_exist ctermfg=blue guifg=blue
    call matchadd('cm_ref_item_status_exist', '^\s\{}' . s:ref_exist_token, 99)

    hi cm_ref_item_status_nonexist ctermfg=red guifg=red
    call matchadd('cm_ref_item_status_nonexist', '^\s\{}' . s:ref_nonexist_token, 99)
endf

func! s:cm_buf_refresh(line)
    if exists('g:cm_view') && buflisted(g:cm_view)
        " if it isn't on cm_view, closing buf then reopen.
        if g:cm_view != bufnr('%')
            call s:cm_buf_show(s:cm_buf_view(s:cm_get_db()))
            wincmd l
        else
            call s:cm_get_write_mode()

            " delete all line in buffer
            let l:header_size = len(s:header) + 2
            exec "silent" . l:header_size. ",$d"

            " update buffer
            for i in s:cm_buf_view(s:cm_get_db())
                if s:cm_which_level_is_it(i) == 0
                    if line('$') != len(s:header) + 1
                        call append(line('$'), '')
                    endif
                endif
                call append(line('$'), i)
            endfor 

            call s:cm_get_readonly_mode()
        endif

        if a:line
            exec ':' . a:line
        endif
    endif
endf

let s:header = ['" +-------------- Key Map ---------------+', 
              \ '" | *Uppercase letter for group action.  |',
              \ '" | Press a or A: to aetach              |',
              \ '" | Press d or B: to detach              |',
              \ '" | Press b or D: to build db            |',
              \ '" | Press r or R: to rebuild db          |',
              \ '" |--------------------------------------|',
              \ '" | Press dd: delete a entry from menu   |',
              \ '" | Press oo: open all file at one time  |',
              \ '" +--------------------------------------+']

func! s:cm_buf_show(content)
    if exists('g:cm_view') && bufloaded(g:cm_view)
        exec g:cm_view.'bd!'
    endif

    let l:pwd = getcwd()
    exec 'silent pedit ' . tempname()

    wincmd P | wincmd H

    let g:cm_view = bufnr('%')
    " TODO: refactory
    " call cm_buf_refresh(a:content)
    call append(0, s:header)

    for i in a:content
        if s:cm_which_level_is_it(i) == 0
            if line('$') != len(s:header) + 1
                call append(line('$'), '')
            endif
            " call s:dprint(i)
        endif
        call append(line('$'), i)
    endfor 
   " call append(len(l:header)+1, a:content)

    setl buftype=nofile
    setl noswapfile

    setl cursorline
    setl nonu ro noma ignorecase

    exec 'vertical resize 44'

    setl ft=vim
    " setl syntax=vim

    call s:cm_buf_color()

    nnoremap <silent> <buffer> q :silent bd!<CR>
    nnoremap <silent> <buffer> a :call CsMgmtAttach(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> d :call CsMgmtDetach(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> b :call CsMgmtBuild(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> r :call CsMgmtRebuild(printf("%s", getline('.')), line('.'))<CR>

    nnoremap <silent> <buffer> A :call CsMgmtAttachByGroup(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> D :call CsMgmtDetachByGroup(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> B :call CsMgmtBuildByGroup(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> R :call CsMgmtRebuildByGroup(printf("%s", getline('.')), line('.'))<CR>

    " for edit
    " deleting a db entry, but don't delete real file.
    nnoremap <silent> <buffer> dd :call CsMgmtDelete(printf("%s", getline('.')), line('.'))<CR>
    " TODO: a function for cleaning all real file

    " open all file at one time
    nnoremap <silent> <buffer> oo :call CsMgmtOpenAllFile(printf("%s", getline('.')), line('.'))<CR>

    exec ':'.(len(s:header) + 2)
    redraw!

    " Its woring directory will be changed to tmpename directory, rolling back
    exec 'cd ' . l:pwd
endf

let s:CsMgmtDb = s:cm_get_db_from_file()
let s:json2file_list = []

command! -nargs=* -complete=dir Csmgmtadd call CsMgmtAdd(<f-args>)
command! CsMgmt call CsMgmt()
map <Leader>cs :call CsMgmt()<CR>

