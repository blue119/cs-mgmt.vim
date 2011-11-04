" cs-db-mgmt.vim:   Vim plugin providing cscope's database management
" Author:           Yao-Po Wang
" HomePage:         https://bitbucket.org/blue119/cs-db-mgmt.vim
" Version:          0.01
" Note:
"       the db name -> {parent prj_name}_\*_{db_name}.out
"       simple item -> \ {O|X}\ {db_name}\ {timestamp}\ [Attach]
"       it is a prj -> \ {prj_name}
"                      \ \ \ \ \ {O|X}\ {db_name}\ {timestamp}\ [Attach]

com! CsDbMgmt call CsDbMgmt()
map <Leader>cs :call CsDbMgmt()<CR>

" debug mode on/off
let s:debug_enable = 1
func! s:dprint(...)
    if s:debug_enable
        call Decho(a:000)
    endif
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

let s:CsDbMgmtDbStatus = {}

func! CsDbMgmt() abort
    call s:cdm_init_check()
    " call s:cdm_get_json()
    call s:cdm_buf_show(s:cdm_buf_view(s:cdm_get_json()))
endf

func! s:cdm_buf_view(json)
    let l:view_data = []
    for k in keys(a:json)

        " if it is simple prj, just show it
        if type(a:json[k]) == 3
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
    return repeat(s:cdm_show_indent_token, a:indent_level).a:str
endf

let s:db_exist_token = 'O'
let s:db_nonexist_token = 'X'
let s:cdm_show_indent_token = '    '
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
    return (len(s:get_db_item_indent(a:line))/len(s:cdm_show_indent_token))
endf

func! s:cdm_show_item_construct(indent_level, parent, dbname)
    " return string format 'l:db_status_token l:db_name l:db_ftime l:db_attach'
    let l:db_full_name = (a:parent == '') ? 
                \   (a:dbname):
                \   (a:parent.'_'.a:dbname)
    let l:db_status_token = s:db_nonexist_token
    let l:db_attach = ''
    let l:db_indent = repeat(s:cdm_show_indent_token, a:indent_level)

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
    let s:cdm_db_status = {}
    let s:CsDbMgmtDbStatus = eval(join(readfile(g:CsDbMgmtConfigFile)))

    return s:CsDbMgmtDbStatus
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

func! s:cdm_is_it_a_unexpect_line(line)
    if a:line == '' || a:line[-1:] == ':' || a:line[0] == '"'
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

func! CsDbMgmtAttach(line, pos)
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

    if index(s:db_attach_list, l:db_full_name) != -1
        echohl WarningMsg 
            \ | echo "Don\'t Attach Twice"
            \ | echohl None
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
        echohl WarningMsg 
            \ | echo "Need Attach Befor"
            \ | echohl None
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
            if match(file, '\.[chsS]$') >= 0
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
        echohl WarningMsg 
            \ | echo 'you can build it again. it has existed on '.g:CsDbMgmtDb.
            \ '. you can try rebuild it.'
            \ | echohl None
        return
    endif

    call writefile(l:all_file_list, g:CsDbMgmtDb.l:db_full_name.'.files')

    let l:path_list = s:cdm_get_path_list_from_config(l:parent_list, l:dbname)

    for p in l:path_list
        call s:cdm_path_walk(p, l:all_file_list)
    endfor

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
        echohl WarningMsg 
            \ | echo l:dbname.' not existed on '.g:CsDbMgmtDb.
            \ ' you have to build it at first.'
            \ | echohl None
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

func! s:cdm_buf_show(content)

    exec 'silent pedit /tmp/.cs-db-mgmt.tmp'

    wincmd P | wincmd H

    let g:cdm_view = bufnr('%')
    let l:header = ['" Press a to attach', 
                  \ '" Press d to detach',
                  \ '" Press b to build db',
                  \ '" Press r to rebuild db']
    call append(0, l:header)

    for i in a:content
        if s:cdm_which_level_is_it(i) == 0
            if line('$') != len(l:header) + 1
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

    exec ':'.(len(l:header) + 2)
    redraw!
endf

