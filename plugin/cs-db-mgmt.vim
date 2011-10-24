" cs-db-mgmt.vim:   Vim plugin providing cscope's database management
" Author:           Yao-Po Wang
" HomePage:         https://bitbucket.org/blue119/cs-db-mgmt.vim
" Version:          0.01

com! CsDbMgmt call CsDbMgmt()
map <Leader>cs :call CsDbMgmt()<CR>

" debug mode on/off
" let s:CsDbMgmtDebug = 0
let s:CsDbMgmtDebug = 1
func! s:CsDbMgmtDecho(...)
    if s:CsDbMgmtDebug
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

" {prj_name:
"   [[DB_name, db_status, lastest_update_time, [file list,]], ], }
let s:CsDbMgmtDbStatus = {}

func! CsDbMgmt() abort
    call s:CsDbMgmtShow(s:CsDbMgmtGet())
    " call s:CsDbMgmtGet()
endf

func! s:CsDbMgmtItemConstruct(item_list)
    let l:db_list = []
    let l:db_status = 0
    let l:db_ftime = 0

    call add(l:db_list, a:item_list[0])

    " db's status check
    if filereadable(g:CsDbMgmtDb.a:item_list[0].'.out')
        let l:db_status = 1
        let l:db_ftime = getftime(g:CsDbMgmtDb.a:item_list[0].'.out')
    endif

    call add(l:db_list, l:db_status)
    call add(l:db_list, l:db_ftime)
    call add(l:db_list, a:item_list[1])
    return l:db_list
endf

func! s:CsDbMgmtGet()
    let s:CsDbMgmtDbStatus = {}

    if !filereadable(g:CsDbMgmtConfigFile)
        echo "you need have a config file befor"
        return
    endif

    if !isdirectory(g:CsDbMgmtDb)
        echo g:CsDbMgmtDb." must be a directory."
        return
    endif

    let l:config_json = eval(join(readfile(g:CsDbMgmtConfigFile)))
    " return

    for item in items(l:config_json)
        " grouping process
        if type(item[1][0]) == 4
            let l:prj_name = item[0]
            let l:db_list = []
            for i in range(0, len(item[1]) - 1)
                call add(l:db_list, s:CsDbMgmtItemConstruct([item[1][i]['db_name'], item[1][i]['source_list']]))
            endfor
            let s:CsDbMgmtDbStatus[item[0]] = l:db_list
        else
            let s:CsDbMgmtDbStatus[item[0]] = [s:CsDbMgmtItemConstruct(item)]
        endif
    endfor

    " call s:CsDbMgmtDecho(g:CsDbMgmtDbStatus)
    return s:CsDbMgmtDbStatus
endf

func! s:CsDbMgmtGetExistPrjNameFromLine(line)
    if s:DbExist.'|' == a:line[:len(s:DbExist)]
        return split(a:line, '|')[1]
    endif
    call s:CsDbMgmtDecho(s:DbExist.'|')
    return -1
endf

func! s:CsDbMgmtGetNonExistPrjNameFromLine(line)
    if s:DbNonExist.'|' == a:line[:len(s:DbNonExist)]
        return split(a:line, '|')[1]
    endif
    call s:CsDbMgmtDecho(s:DbNonExist.'|')
    return -1
endf

func! CsDbMgmtAttach(db)
    let l:prj_name = s:CsDbMgmtGetExistPrjNameFromLine(a:db)
    call s:CsDbMgmtDecho(l:prj_name)
    if l:prj_name == -1
        return
    endif

    call s:CsDbMgmtDecho("cs add ".g:CsDbMgmtDb.l:prj_name.'.out')
    exec "cs add ".g:CsDbMgmtDb.l:prj_name.'.out'
endf

func! CsDbMgmtDetach(db)
    let l:prj_name = s:CsDbMgmtGetExistPrjNameFromLine(a:db)
    call s:CsDbMgmtDecho(l:prj_name)
    if l:prj_name == -1
        return
    endif

    call s:CsDbMgmtDecho("cs add ".g:CsDbMgmtDb.l:prj_name.'.out')
    exec "cs kill ".g:CsDbMgmtDb.l:prj_name.'.out'
endf

func! MyWalk(path, all_file)
    let l:file_list = split(globpath(a:path, '*'), '\n')
    for file in l:file_list
        if isdirectory(file)
            call MyWalk(file, a:all_file)
        else
            if match(file, '\.[chsS]$') >= 0
                call add(a:all_file, file)
            endif
        endif
    endfor
endf

func! s:CsDbMgmtDbBuild(db_name)
    let l:cmd_string = printf('cd %s && cscope -b -q -k -i%s.files -f%s.out', 
            \ g:CsDbMgmtDb, a:db_name, a:db_name)
    call s:CsDbMgmtDecho(l:cmd_string)
    let l:ret = system(l:cmd_string)
    call s:CsDbMgmtDecho(l:ret)
endf

func! CsDbMgmtBuild(db)
    let l:prj_name = s:CsDbMgmtGetNonExistPrjNameFromLine(a:db)
    let l:all_file = []

    if l:prj_name == -1
        echoe('Its db has existed.')
    endif
    call s:CsDbMgmtDecho(l:prj_name)
    call s:CsDbMgmtDecho(s:CsDbMgmtDbStatus)

    try
        let l:item = s:CsDbMgmtDbStatus[l:prj_name]
    catch
        " find its parent
        let l:dec_num = 1
        let l:line = getline(line("."))
        while !((s:DbExist.'|' != l:line[:len(s:DbExist)]) &&
            \ (s:DbNonExist.'|' != l:line[:len(s:DbNonExist)]))
            let l:line = getline(line(".") - l:dec_num)
            let l:dec_num += 1
        endwhile
        call s:CsDbMgmtDecho(l:dec_num)
        let l:item = s:CsDbMgmtDbStatus[l:line][l:dec_num - 2]
    endtry
    call s:CsDbMgmtDecho(l:item)
    while 1
        if len(l:item) == 1
            let l:item = l:item[0]
        else
            break
        endif
    endwhile
    let l:file_list = s:CsDbMgmtGetFileList(l:item)
    call s:CsDbMgmtDecho(l:file_list)
    for path in l:file_list
        call MyWalk(path, l:all_file)
    endfor
    let g:CsDbMgmtDb = $HOME.'/.cs-db-mgmt/'
    call writefile(l:all_file, g:CsDbMgmtDb.l:prj_name.'.files')
    call s:CsDbMgmtDbBuild(l:prj_name)
endf

func! CsDbMgmtRebuild(db)
    let l:prj_name = s:CsDbMgmtGetExistPrjNameFromLine(a:db)
    let l:all_file = []

    if l:prj_name == -1
        echoe('Its db has not existed.')
    endif
    call s:CsDbMgmtDbBuild(l:prj_name)
endf

func! s:CsDbMgmtGetFileListByDbName(DbName)
    return a:item[0]
endf

func! s:CsDbMgmtGetPrjName(item)
    return a:item[0]
endf

let s:DbExist = ' O'
let s:DbNonExist = ' X'
func! s:CsDbMgmtGetDbStatus(item)
    if a:item[1] == 0
        return s:DbNonExist
    else
        return s:DbExist
    endf

func! s:CsDbMgmtGetUpdateTime(item)
    " return strftime("%c", a:item[2])
    if a:item[2]
        " ISO 8601
        return strftime("%Y%m%dT%H%M%S", a:item[2])
    endif
    return ''
endf

func! s:CsDbMgmtGetFileList(item)
    return a:item[3]
endf

func! CsDbMgmtSprintf(item)
    " s:CsDbMgmtGetUpdateTime(a:item))
    return printf("%s|%s|%20s", 
    \    s:CsDbMgmtGetDbStatus(a:item), 
    \    s:CsDbMgmtGetPrjName(a:item), 
    \    s:CsDbMgmtGetUpdateTime(a:item))
endf

func! s:CsDbMgmtShow(content)

    exec 'silent pedit .cs-db-mgmt.tmp'

    wincmd P | wincmd H

    let g:cdm_view = bufnr('%')
    let l:header = ['" Press a to attach', 
                    \ '" Press d to detach',
                    \ '" Press b to build db',
                    \ '" Press r to rebuild db',
                    \ ]
    call append(0, l:header)
    
    let l:all_db = []
    for l:items in items(a:content)
        " prj_name
        call add(l:all_db, l:items[0])
        for l:item in l:items[1]
            " call s:CsDbMgmtDecho(l:item)
            let l:sprintf = CsDbMgmtSprintf(l:item)
            call add(l:all_db, l:sprintf)
        endfor
        " new line
        call add(l:all_db,'')
    endfor
    " call sort(l:all_db)

    call append(len(l:header)+1, l:all_db)

    setl buftype=nofile
    setl noswapfile

    setl cursorline
    setl nonu ro noma ignorecase

    setl ft=vim
    setl syntax=vim

    nnoremap <buffer> q :silent bd!<CR>
    nnoremap <buffer> a :call CsDbMgmtAttach(printf("%s", getline('.')))<CR>
    nnoremap <buffer> d :call CsDbMgmtDetach(printf("%s", getline('.')))<CR>
    nnoremap <buffer> b :call CsDbMgmtBuild(printf("%s", getline('.')))<CR>
    nnoremap <buffer> r :call CsDbMgmtRebuild(printf("%s", getline('.')))<CR>

    exec ':'.(len(l:header) + 1)
    redraw!
endf

