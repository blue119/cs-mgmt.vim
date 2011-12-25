" cs-db-mgmt.vim:   Vim plugin providing cscope's database management
" Author:           Yao-Po Wang
" HomePage:         https://bitbucket.org/blue119/cs-db-mgmt.vim
" Version:          0.01
" Note:
"       the db name -> {parent prj_name}_\*_{db_name}.out
"       simple item -> \ {O|X}\ {db_name}\ {timestamp}\ [Attach]
"       it is a prj -> \ {prj_name}
"                      \ \ \ \ \ {O|X}\ {db_name}\ {timestamp}\ [Attach]
"
"      :CsDbMgmtAdd ('file' | 'url' | 'apt') {file path}
"      it is going to take source code from file, web url, or dpkg, and put it
"      to your g:CsDbMgmtDb/.source. it will add this source item to json file
"      as well.
"
"      taking from apt, it will get source from apt mirrot server and do
"      dpkg-source. it would provide a buffer to show mult-candidate when the
"      package term is not precision.
"
"      take from file procedure: Now it only support tarball file
"          1. checking file readable
"          2. copy to g:CsDbMgmtDb/.source, and then unpack it
"          3. add this item to json struct, and then write to file
"          4. udpate the buffer of the cs-db-mgmt
"          

if exists('g:loaded_cs_db_mgmt') || &cp
  finish
endif
let g:loaded_cs_db_mgmt = 1

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
if !exists('g:CsDbMgmtDb')
    let g:CsDbMgmtDb = $HOME.'/.cs-db-mgmt/'
" else
    " let g:CsDbMgmtDb = finddir(g:CsDbMgmtDb)
endif

" where are your config file
" by default, it will be put on $HOME/.cs-db-mgmt.json
if !exists('g:CsDbMgmtConfigFile')
    let g:CsDbMgmtConfigFile = $HOME.'/.cs-db-mgmt.json'
endif

" with CsDbMgmtAdd, that all source will be put into the folder.
if !exists('g:CsDbMgmtSrcDepot')
    let g:CsDbMgmtSrcDepot = g:CsDbMgmtDb . '.source_depot/'
endif

func! s:cdm_get_src_from_file(path)
    if !filereadable(a:path)
        echo a:path . ' is not readable.'
        return
    endif

    let l:decomp_cmd = ''
    let l:tmpfolder = ''
    " to check compressed type
    if a:path[-len(".tar.gz"):] == ".tar.gz"
        let l:filename = split(a:path, '\/')[-1][:-len(".tar.gz")-1]
        let l:tmpfolder = g:CsDbMgmtSrcDepot . l:filename . '.tmp'
        let l:decomp_cmd = 'tar zxvf ' . a:path . ' -C ' . l:tmpfolder 
    elseif a:path[-len(".tar.bz2"):] == ".tar.bz2"
        let l:filename = split(a:path, '\/')[-1][:-len(".tar.bz2")-1] 
        let l:tmpfolder = g:CsDbMgmtSrcDepot . l:filename . '.tmp'
        let l:decomp_cmd = 'tar jxvf ' . a:path . ' -C ' . l:tmpfolder
    else
        echo 'the type of file do not support.'
        return
    endif

    if isdirectory(l:tmpfolder)
        echo l:tmpfolder . ' folder conflict!! you have to remove it before.'
        return
    else
        " 1. create a tmp folder on g:CsDbMgmtSrcDepot that name is its file name.
        if mkdir(l:tmpfolder) != 1
            return
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
        let l:finalfolder = g:CsDbMgmtSrcDepot . l:first_folder
        if isdirectory(l:finalfolder)
            call system('rm -rf ' . l:tmpfolder)
            echo l:finalfolder . ' folder conflict!! you have to remove it before.'
            return
        else
            call system( 
                    \ printf('mv %s/%s %s', l:tmpfolder, l:first_folder, l:finalfolder))
            call system('rm -rf ' . l:tmpfolder)
        endif
    else
        let l:finalfolder = g:CsDbMgmtSrcDepot . l:filename
        " call s:dprint(printf('mv %s %s', l:tmpfolder, l:finalfolder))
        call system(printf('mv %s %s', l:tmpfolder, l:finalfolder))
    endif

    return l:finalfolder
endf

func! s:cdm_get_src_from_dir(path)
    if !isdirectory(a:path)
        echo a:path . ' is not a directory.'
        return
    endif

    return a:path
endf


" Examples
" :CsDbMgmtAdd file /home/blue119/iLab/gspca-ps3eyeMT-0.5.tar.gz
" :CsDbMgmtAdd dir /home/blue119/iLab/vte/lilyterm-0.9.8
func! CsDbMgmtAdd(...) abort
    " a:000[0]: protocol
    " a:000[1]: file path
    " a:000[2]: dbname <- it is not necessary.
    " a:000[3]: project path <- it is not necessary.
    if len(a:000) > 4 || len(a:000) < 2
        echo ":CsDbMgmtAdd {prot type} {src path} [{dbname}]"
        echo ":CsDbMgmtAdd {prot type} {src path} {dbname} [project path]"
        return
    endif

    if !isdirectory(g:CsDbMgmtSrcDepot)
        call mkdir(g:CsDbMgmtSrcDepot)
    endif

    let l:prot_type = ['file', 'dir']
    " TODO: ['url', 'apt']
    " let l:prot_type = ['file', 'dir', 'url', 'apt']
    let l:type = a:000[0]
    let l:path = a:000[1]
    let l:dbname = ''
    let l:prj_parent = []
    let l:prj_new = []
    if len(a:000) > 2
        let l:dbname = a:000[2]

        " check reserved words in filename
        if len(s:cdm_filename_resv_words(l:dbname))
            call s:echo_waring("Don't contain reserved words in dbname.")
            return
        endif

        if len(a:000) == 4
            " to verify the name conflict of the project path in CsDbMgmtDbStatus
            " l:prj_new will save its struct of dict for later
            " l:prj_parent will save its parent path
            "
            " to check reserved words in prj_new excepting '/' word, and
            " reduce the repeating '/' to onece.
            let l:prj_new = []
            for i in split(a:000[3], "/")
                if len(i)
                    if len(s:cdm_filename_resv_words(i))
                        call s:echo_waring("Don't contain reserved words in group name.")
                        return
                    endif
                    call add(l:prj_new, i)
                endif
            endfor

            let l:db = copy(s:CsDbMgmtDbStatus)
            while len(l:prj_new)
                let k = l:prj_new[0]
                if has_key(l:db, k)
                    if type(l:db[k]) != 4
                        call s:echo_waring("name conflict.")
                        return
                    endif
                    call add(l:prj_parent, k)
                    call remove(l:prj_new, 0)
                    let l:db = l:db[k]
                else
                    break
                endif
            endwhile
        endif "if len(a:000) == 4

        if !len(l:prj_new)
            "check key whenter existed in json befor
            let l:db = s:CsDbMgmtDbStatus
            " roll into its parent
            for k in l:prj_parent
                let l:db = l:db[k]
            endfor

            if has_key(l:db, l:dbname)
                echo l:dbname . " has existed in " . join(l:prj_parent, "/") . "."
                return
            endif
        endif " if len(l:prj_new)
    endif

    let l:type_func = ''
    for t in l:prot_type
        if l:type == t
            let l:type_func = 's:cdm_get_src_from_' . l:type
        endif
    endfor

    if l:type_func == ''
        echo 'Not support '. l:type .' protocol type'
        return
    endif

    if l:path[0] == '~'
        let l:path = $HOME . l:path[1:]
    elseif l:path[0] == '.'
        let l:path = $PWD . l:path[1:]
    elseif l:path[0:3] == '$PWD'
        let l:path = $PWD . l:path[4:]
    endif

    let l:source_path = eval(l:type_func . '("' . l:path . '")')

    if l:source_path == ''
        return
    endif

    if l:dbname == ''
        let l:dbname = split(l:source_path, '/')[-1]
    endif

    " echo l:dbname
    " echo l:source_path
    " echo l:prj_parent
    " echo l:prj_new

    " craete add_dict
    let l:add_dict = {}
    if len(l:prj_new) != 0
        let l:prj_new = reverse(l:prj_new)
        let l:add_dict[l:prj_new[0]] = {l:dbname : [l:source_path]}
        call remove(l:prj_new, 0)

        while len(l:prj_new)
            let l:add_dict = {l:prj_new[0]:copy(l:add_dict)}
            call remove(l:prj_new, 0)
        endwhile
    endif

    " find adding entrance
    let l:db = s:CsDbMgmtDbStatus
    while len(l:prj_parent)
        let l:db = l:db[l:prj_parent[0]]
        call remove(l:prj_parent, 0)
    endwhile

    if len(l:add_dict)
        let l:db[keys(l:add_dict)[0]] = values(l:add_dict)[0]
    els
        let l:db[l:dbname] = [l:source_path]
    endif

    call s:cdm_json2file()
    call s:cdm_buf_refresh(line("."))
endf

func! CsDbMgmt() abort
    call s:cdm_init_check()
    " call s:cdm_get_json()
    " call s:cdm_buf_show(s:cdm_buf_view(s:cdm_get_json()))
    call s:cdm_buf_show(s:cdm_buf_view(s:CsDbMgmtDbStatus))
endf

func! s:cdm_buf_view(json)
    let l:view_data = []
    for k in keys(a:json)

        " if it is simple prj, just show it
        if type(a:json[k]) == 1
            call add(l:view_data, s:cdm_show_item_construct(0, '', k))

        elseif type(a:json[k]) == 3
            call add(l:view_data, s:cdm_show_item_construct(0, '', k))

        " it is a project config
        elseif type(a:json[k]) == 4
            let l:deep_collect = []
            call add(l:view_data, printf('%s:', k))
            call s:cdm_deep_prj_collect(0, l:deep_collect, a:json[k], k)
            for d in l:deep_collect
                call add(l:view_data, d)
            endfor
        endif
    endfor

    return l:view_data
endf

func! s:cdm_deep_prj_collect(indent_level, collect_list, config, parent)
    let l:indent_level = a:indent_level + 1

    for k in keys(a:config)
        if type(a:config[k]) == 3
            call add(a:collect_list, 
                    \ s:cdm_show_item_construct(l:indent_level, a:parent, k))
        elseif type(a:config[k]) == 4
            call add(a:collect_list, printf('%s:', s:cdm_str_add_indent(l:indent_level, k)))
            call s:cdm_deep_prj_collect(l:indent_level, a:collect_list, 
                        \ a:config[k], printf('%s_%s', a:parent, k))
        endif
    endfor
endf

func! s:cdm_str_add_indent(indent_level, str)
    return repeat(s:cdm_indent_token, a:indent_level).a:str
endf

let s:db_exist_token = 'O'
let s:db_nonexist_token = 'X'
let s:cdm_indent_token = '    '
if !exists('s:db_attach_list')
    let s:db_attach_list = []
endif

" let s:db_item_re = '\(^\s*\)'
                " \ .'\(['.db_exist_token.db_nonexist_token.']\)\s'
                " \ .'\(\w*\)\s'
                " \ .'\(\d\{8}T\d\{6}Z\)\s\{}'
                " \ .'\(Attach\)\{}'

let s:db_prj_re = '\(^\s\{}\)'
                \ .'\(.*\):'

let s:db_nonexist_re = '^\(\s\{}\)'
                \ .'\([OX]\)\s'
                \ .'\([0-9a-zA-Z\-._~]\{}\)\s\{}'

let s:db_exist_re = '^\(\s\{}\)'
                \ .'\([OX]\)\s'
                \ .'\([0-9a-zA-Z\-._~]\{}\)\s\{}'
                \ .'\(\d\{4}\.\d\{2}\.\d\{2}\s\d\{2}\:\d\{2}\)'
                \ .'\(Attach\)\{}'


" Reserved characters and words
func! s:cdm_filename_resv_words(str)
    let l:resv_words_re = '[\/\\\?\%\*\:\|\"\>\<]'
    return matchstr(a:str, l:resv_words_re)
endf

func! s:cdm_str_strip(str)
    let l:str_strip_re = '^\s\{}\(.*\)\s\{}$'
    let l:l = matchstr(a:str, l:str_strip_re)
    return substitute(l:l, l:str_strip_re, '\1', '')
endf

func! s:cdm_get_rep(line)
    let l:str = s:cdm_str_strip(a:line)

    if l:str[-1:] == ':'
        return s:db_prj_re
    elseif l:str[0:len(s:db_exist_token)-1] == s:db_exist_token
        return s:db_exist_re
    elseif l:str[0:len(s:db_nonexist_token)-1] == s:db_nonexist_token
        return s:db_nonexist_re
    endif
endf

func! s:get_db_item_indent(line)
    let l:rep = s:cdm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\1', '')
endf

func! s:get_db_item_status(line)
    let l:rep = s:cdm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\2', '')
endf

func! s:get_db_item_name(line)
    let l:rep = s:cdm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\3', '')
endf

func! s:get_db_item_timestamp(line)
    let l:rep = s:cdm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\4', '')
endf

func! s:get_db_item_attach(line)
    let l:rep = s:cdm_get_rep(a:line)
    " call s:dprint(l:rep)
    let l:l = matchstr(a:line, l:rep)
    return substitute(l:l, l:rep, '\5', '')
endf

func! s:cdm_which_level_is_it(line)
    return (len(s:get_db_item_indent(a:line))/len(s:cdm_indent_token))
endf

func! s:cdm_show_item_construct(indent_level, parent, dbname)
    " return string format 'l:db_status_token l:db_name l:db_ftime l:db_attach'
    let l:db_full_name = (a:parent == '') ? 
                \   (a:dbname):
                \   (a:parent.'_'.a:dbname)
    let l:db_status_token = s:db_nonexist_token
    let l:db_attach = ''
    let l:db_indent = repeat(s:cdm_indent_token, a:indent_level)

    " to check the status of db reference file
    " call s:dprint(g:CsDbMgmtDb.l:db_full_name.'.out')
    if filereadable(g:CsDbMgmtDb.l:db_full_name.'.out')
        let l:db_status_token = s:db_exist_token
        let l:db_ftime = strftime("%Y.%m.%d %H:%M", 
                    \ getftime(g:CsDbMgmtDb.l:db_full_name.'.out'))

        if index(s:db_attach_list, l:db_full_name) != -1
            let l:db_attach = ' Attach'
        endif
    endif

    if l:db_status_token == s:db_exist_token
        return printf("%s%s %s %s%s", 
                    \ l:db_indent, l:db_status_token, 
                    \ a:dbname, l:db_ftime, l:db_attach)
    else
        return printf("%s%s %s", l:db_indent, l:db_status_token, a:dbname)
    endif
endf

func! s:cdm_init_check()
    if !filereadable(g:CsDbMgmtConfigFile)
        echo "you need have a config file befor"
        return
    endif

    if !isdirectory(g:CsDbMgmtDb)
        echo g:CsDbMgmtDb." must be a directory."
        return
    endif
endf

func! s:cdm_get_json()
    if !filereadable(g:CsDbMgmtConfigFile)
        call writefile(["{'usr_include' : ['/usr/include/', ],}"], g:CsDbMgmtConfigFile )
    endif

    return eval(join(readfile(g:CsDbMgmtConfigFile)))
endf

" look down and only included more level than it until it run into a blank line
func! s:cdm_get_children_pos_list_from_buf(level, line, pos)
    let l:pos = a:pos
    let l:level = a:level
    let l:children_pos_list = []

    while 1
        let l:pos += 1
        if s:cdm_which_level_is_it(getline(l:pos)) > (l:level) 
                \ && s:cdm_is_it_a_unexpect_line(getline(l:pos)) == 0
            call insert(l:children_pos_list, l:pos, 0)
        endif

        if s:cdm_is_it_a_blank_line(getline(l:pos)) == 1
            break
        endif
    endwhile

    return l:children_pos_list
endf

func! s:cdm_get_parent_list_from_buf(level, line, pos)
    let l:pos = a:pos
    let l:level = a:level
    let l:parent_list = []

    if l:level == 0
        return ''
    endif

    while 1
        let l:pos -= 1
        if s:cdm_which_level_is_it(getline(l:pos)) == (l:level - 1)
            call insert(l:parent_list, s:cdm_str_strip(getline(l:pos))[:-2], 0)
            let l:level -= 1

            if s:cdm_which_level_is_it(getline(l:pos)) == 0
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

func! s:cdm_is_it_a_comment(line)
    if a:line[0] == '"' 
        return 1
    else
        return 0
    endif
endf

func! s:cdm_is_it_a_group_title(line)
    if a:line[-1:] == ':'
        return 1
    else
        return 0
    endif
endf

func! s:cdm_is_it_a_blank_line(line)
    if a:line == '' 
        return 1
    else
        return 0
    endif
endf

func! s:cdm_is_it_a_unexpect_line(line)
    if   s:cdm_is_it_a_blank_line(a:line)
    \ || s:cdm_is_it_a_group_title(a:line)
    \ || s:cdm_is_it_a_comment(a:line)
        return 1
    else
        return 0
    endif
endf

func! s:cdm_get_write_mode()
    setl buftype=
    setl modifiable
endf

func! s:cdm_get_readonly_mode()
    setl nomodifiable
    setl buftype=nofile
endf

func! CsDbMgmtAttachByGroup(line, pos)
    if s:cdm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cdm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cdm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsDbMgmtAttach(getline(p), p)
    endfor
endf

func! CsDbMgmtDetachByGroup(line, pos)
    if s:cdm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cdm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cdm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsDbMgmtDetach(getline(p), p)
    endfor
endf

func! CsDbMgmtBuildByGroup(line, pos)
    if s:cdm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cdm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cdm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsDbMgmtBuild(getline(p), p)
    endfor
endf

func! CsDbMgmtRebuildByGroup(line, pos)
    if s:cdm_is_it_a_group_title(a:line) == 0
        " echo 'it is a unexpect line'
        return
    endif

    let l:level = s:cdm_which_level_is_it(a:line)
    let l:childre_pos_list = s:cdm_get_children_pos_list_from_buf(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsDbMgmtRebuild(getline(p), p)
    endfor
endf

func! CsDbMgmtAttach(line, pos)
    if s:cdm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    if s:cdm_str_strip(a:line)[0] == s:db_nonexist_token
        call s:echo_waring("Hasn't build") 
        return
    endif

    let l:db_level = s:cdm_which_level_is_it(a:line)
    let l:parent_list = s:cdm_get_parent_list_from_buf(l:db_level, a:line, a:pos)
    let l:dbname = s:get_db_item_name(a:line)

    let l:db_full_name = (len(l:parent_list) == 0) ? 
                \   (l:dbname):
                \   (join(l:parent_list, '_').'_'.l:dbname)

    if index(s:db_attach_list, l:db_full_name) != -1
        " call s:echo_waring("Don\'t Attach Twice") 
        return
    endif

    " add to attach list
    call add(s:db_attach_list, l:db_full_name)

    " add a Attach word on the end of line
    call s:cdm_get_write_mode()
    call setline(a:pos, a:line." Attach")
    call s:cdm_get_readonly_mode()
 
    exec "cs add ".g:CsDbMgmtDb.l:db_full_name.'.out'
endf

func! s:cdm_del_db(line, pos)
    if s:cdm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    " if it has attached
    call CsDbMgmtDetach(a:line, a:pos)

    " look for key of deletion
    let l:db_level = s:cdm_which_level_is_it(a:line)
    let l:parent_list = s:cdm_get_parent_list_from_buf(l:db_level, a:line, a:pos)
    let l:dbname = s:get_db_item_name(a:line)
    let l:parent_key = s:CsDbMgmtDbStatus
    for p in l:parent_list
        let l:parent_key = l:parent_key[p]
    endfor

    " delete
    unlet l:parent_key[l:dbname]
endf

func! s:cdm_del_db_by_group(line, pos)
    " find childrens
    let l:level = s:cdm_which_level_is_it(a:line)
    let l:dbname = s:cdm_str_strip(getline(a:pos))[:-2]
    let l:pos = a:pos

    while 1
        let l:pos += 1
        if s:cdm_which_level_is_it(getline(l:pos)) <= l:level
            break
        endif

        let l:line = getline(l:pos)
        if s:cdm_is_it_a_unexpect_line(l:line) == 0
            " echo l:line
            call s:cdm_del_db(l:line, l:pos)
        endif
    endwhile

    let l:parent_list = s:cdm_get_parent_list_from_buf(l:level, a:line, a:pos)
    if len(l:parent_list) == 0 
        unlet l:parent_list
        let l:parent_list = []
    endif

    let l:parent_key = s:CsDbMgmtDbStatus
    for p in l:parent_list
        let l:parent_key = l:parent_key[p]
    endfor

    " delete
    unlet l:parent_key[l:dbname]
endf

func! CsDbMgmtDelete(line, pos)
    if s:cdm_is_it_a_unexpect_line(a:line) == 1
        if s:cdm_is_it_a_group_title(a:line) == 1
            " delete a group
            call s:cdm_del_db_by_group(a:line, a:pos)
        else
            call s:cdm_del_db(a:line, a:pos)
        endif
        call s:cdm_json2file()
        call s:cdm_buf_refresh(line("."))
    endif
endf

func! CsDbMgmtDetach(line, pos)
    if s:cdm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    let l:db_level = s:cdm_which_level_is_it(a:line)
    let l:parent_list = s:cdm_get_parent_list_from_buf(l:db_level, a:line, a:pos)
    let l:dbname = s:get_db_item_name(a:line)

    let l:db_full_name = (len(l:parent_list) == 0) ? 
                \   (l:dbname):
                \   (join(l:parent_list, '_').'_'.l:dbname)

    if index(s:db_attach_list, l:db_full_name) == -1
        call s:echo_waring("Need Attach Befor") 
        return
    endif

    " remove from attach list
    call filter(s:db_attach_list, 'v:val !~ "'.l:db_full_name.'"')

    " add a Attach word on the end of line
    call s:cdm_get_write_mode()
    call setline(a:pos, a:line[0:-len(" Attach")-1])
    call s:cdm_get_readonly_mode()
 
    exec "cs kill ".g:CsDbMgmtDb.l:db_full_name.'.out'
endf

func! s:cdm_path_walk(path, all_file_list)
    let l:file_list = split(globpath(a:path, '*'), '\n')
    for file in l:file_list
        if isdirectory(file)
            call s:cdm_path_walk(file, a:all_file_list)
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

func! s:cdm_db_build(dbname)
    let l:cmd_string = printf('cd %s && cscope -b -q -k -i%s.files -f%s.out', 
            \ g:CsDbMgmtDb, a:dbname, a:dbname)

    echohl TabLine
        \ | echo a:dbname.' building.... '
        \ | echohl None
    call system(l:cmd_string)
    echohl Title
        \ | echo a:dbname.' built success.'
        \ | echohl None
endf

func! s:cdm_get_path_list_from_config(parent_list, dbname)
    let l:config = s:CsDbMgmtDbStatus

    if len(a:parent_list) > 0
        for p in a:parent_list
            let l:config = config[p]
        endfor
    endif

    return l:config[a:dbname]
endf

func! CsDbMgmtBuild(line, pos)
    if s:cdm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    let l:db_level = s:cdm_which_level_is_it(a:line)
    let l:parent_list = s:cdm_get_parent_list_from_buf(l:db_level, a:line, a:pos)
    let l:dbname = s:get_db_item_name(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ? 
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:db_full_name = (l:parent == '') ? 
                \   (l:dbname):
                \   (l:parent.'_'.l:dbname)

    if filereadable(g:CsDbMgmtDb.l:db_full_name.'.out')
        let l:msg = "it has existed on " . g:CsDbMgmtDb 
                    \ . ' you can try to rebuild it.'
        call s:echo_waring(l:msg)
        return
    endif

    call writefile(l:all_file_list, g:CsDbMgmtDb.l:db_full_name.'.files')

    let l:path_list = s:cdm_get_path_list_from_config(l:parent_list, l:dbname)

    " if type(l:path_list) == 1
        " let l:path_list = [l:path_list]
    " endif

    for p in (type(l:path_list) == 1 ? [l:path_list] : l:path_list)
        call s:cdm_path_walk(p, l:all_file_list)
    endfor

    if len(l:all_file_list) == 0
        let l:msg =  'It is not finish to build cscope database,'
            \ .  ' because no fidning any c or cpp file in ' . l:path_list
        call s:echo_waring(l:msg)
        return
    endif

    "write to file
    call writefile(l:all_file_list, g:CsDbMgmtDb.l:db_full_name.'.files')

    " real build
    call s:cdm_db_build(l:db_full_name)

    " add a Attach word on the end of line
    call s:cdm_get_write_mode()
    call setline(a:pos,
        \ s:cdm_show_item_construct(l:db_level, l:parent, l:dbname))
    call s:cdm_get_readonly_mode()
endf

func! CsDbMgmtRebuild(line, pos)
    if s:cdm_is_it_a_unexpect_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    let l:db_level = s:cdm_which_level_is_it(a:line)
    let l:parent_list = s:cdm_get_parent_list_from_buf(l:db_level, a:line, a:pos)
    let l:dbname = s:get_db_item_name(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ? 
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:db_full_name = (l:parent == '') ? 
                \   (l:dbname):
                \   (l:parent.'_'.l:dbname)

    if !filereadable(g:CsDbMgmtDb.l:db_full_name.'.out')
        let l:msg =  l:dbname.' not existed on '.g:CsDbMgmtDb.
                    \ ' you have to build it at first.'
        call s:echo_waring(l:msg)
        return
    endif

    " real build
    call s:cdm_db_build(l:db_full_name)

    " add a Attach word on the end of line
    call s:cdm_get_write_mode()
    call setline(a:pos,
        \ s:cdm_show_item_construct(l:db_level, l:parent, l:dbname))
    call s:cdm_get_readonly_mode()
endf

func! s:cdm_json_dip(indent_level, value)
    for item in items(a:value)
        let l:il = a:indent_level
        let l:key = item[0]
        unlet! l:value
        let l:value = item[1]
        let l:vt = type(l:value)

        if l:vt == 1
            call add(s:json2file_list, 
                        \   repeat(s:cdm_indent_token, l:il) . 
                        \   "'" . l:key . "'" . 
                        \   " : " . "'" . l:value . "', " )

        elseif l:vt == 3
            call add(s:json2file_list, 
                    \ repeat(s:cdm_indent_token, l:il) . 
                    \ "'" . l:key . "'" . " : " . "[")

            let l:il += 1
            for i in l:value
                call add(s:json2file_list, 
                        \ repeat(s:cdm_indent_token, l:il) . 
                        \ "'" . i . "', ")
            endfor
            let l:il -= 1
            call add(s:json2file_list, repeat(s:cdm_indent_token, l:il) . "], ")

        elseif l:vt == 4
            call add(s:json2file_list, 
                    \ repeat(s:cdm_indent_token, l:il) . 
                    \ "'" . l:key . "'" . " : " . "{")

            let l:il += 1
            call s:cdm_json_dip(l:il, l:value) 
            let l:il -= 1
            call add(s:json2file_list, repeat(s:cdm_indent_token, l:il) . "}, ")
        endif
    endfor 
endf

func! s:cdm_json2file()
    let s:json2file_list = []
    let l:indent_level = 0
    let l:json = s:CsDbMgmtDbStatus

    call add(s:json2file_list, '{') 
    let l:indent_level += 1
    call s:cdm_json_dip(l:indent_level, l:json) 
    call add(s:json2file_list, '}') 
    call writefile(s:json2file_list, g:CsDbMgmtConfigFile)
endf

func! s:cdm_buf_color()
    hi cdm_db_prj_name ctermfg=cyan guifg=cyan
    call matchadd('cdm_db_prj_name', '^\s\{}\w\+:')

    hi cdm_db_name ctermfg=yellow guifg=yellow
    call matchadd('cdm_db_name', '^\s\{}[OX]\s\(.*\)$')

    hi cdm_timestamp ctermfg=darkgreen guifg=darkgreen
    call matchadd('cdm_timestamp', '\d\{4}\.\d\{2}\.\d\{2}\s\d\{2}\:\d\{2}')

    hi cdm_db_attach ctermfg=darkblue guifg=darkblue
    call matchadd('cdm_db_attach', '\ Attach$')

    hi cdm_db_item_status_exist ctermfg=blue guifg=blue
    call matchadd('cdm_db_item_status_exist', '^\s\{}O', 99)

    hi cdm_db_item_status_nonexist ctermfg=red guifg=red
    call matchadd('cdm_db_item_status_nonexist', '^\s\{}X', 99)
endf

func! s:cdm_buf_refresh(line)
    if buflisted(g:cdm_view)
        " if it isn't on cdm_view, closing buf then reopen.
        if g:cdm_view != bufnr('%')
            call s:cdm_buf_show(s:cdm_buf_view(s:CsDbMgmtDbStatus))
            wincmd l
        else
            call s:cdm_get_write_mode()

            " delete all line in buffer
            let l:header_size = len(s:header) + 2
            exec l:header_size. ",$d"

            " update buffer
            for i in s:cdm_buf_view(s:CsDbMgmtDbStatus)
                if s:cdm_which_level_is_it(i) == 0
                    if line('$') != len(s:header) + 1
                        call append(line('$'), '')
                    endif
                endif
                call append(line('$'), i)
            endfor 

            call s:cdm_get_readonly_mode()
        endif

        if a:line
            exec ':' . a:line
        endif
    endif
endf

let s:header = ['" Press a to attach', 
                \ '" Press d to detach',
                \ '" Press b to build db',
                \ '" Press r to rebuild db']

func! s:cdm_buf_show(content)
    if exists('g:cdm_view') && bufloaded(g:cdm_view)
        exec g:cdm_view.'bd!'
    endif

    exec 'silent pedit '.tempname()

    wincmd P | wincmd H

    let g:cdm_view = bufnr('%')
    " TODO: refactory
    " call cdm_buf_refresh(a:content)
    call append(0, s:header)

    for i in a:content
        if s:cdm_which_level_is_it(i) == 0
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

    exec 'vertical resize 40'

    setl ft=vim
    " setl syntax=vim

    call s:cdm_buf_color()

    nnoremap <buffer> q :silent bd!<CR>
    nnoremap <buffer> a :call CsDbMgmtAttach(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <buffer> d :call CsDbMgmtDetach(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <buffer> b :call CsDbMgmtBuild(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <buffer> r :call CsDbMgmtRebuild(printf("%s", getline('.')), line('.'))<CR>

    nnoremap <buffer> A :call CsDbMgmtAttachByGroup(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <buffer> D :call CsDbMgmtDetachByGroup(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <buffer> B :call CsDbMgmtBuildByGroup(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <buffer> R :call CsDbMgmtRebuildByGroup(printf("%s", getline('.')), line('.'))<CR>

    " for edit
    " deleting a db entry, but don't delete real file.
    nnoremap <buffer> dd :call CsDbMgmtDelete(printf("%s", getline('.')), line('.'))<CR>

    exec ':'.(len(s:header) + 2)
    redraw!
endf

let s:CsDbMgmtDbStatus = s:cdm_get_json()
let s:json2file_list = []

command! -nargs=* CsDbMgmtAdd call CsDbMgmtAdd(<f-args>)
" command! CsDbMgmt2File call CsDbMgmt2File()
command! CsDbMgmt call CsDbMgmt()
map <Leader>cs :call CsDbMgmt()<CR>

