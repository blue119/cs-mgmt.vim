" cs-db-mgmt.vim:   Vim plugin providing cscope's database management
" Author:           Yao-Po Wang
" HomePage:         https://bitbucket.org/blue119/cs-db-mgmt.vim
" Version:          0.01

com! CsDbMgmt call CsDbMgmt()
map <Leader>cs :call CsDbMgmt()<CR>

" debug mode on/off
let s:CsDbMgmtDebug = 0
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

" [[DB's project name, db's status, lastest update time, [file list,]], ]
let g:CsDbMgmtDbStatus = []

func! CsDbMgmt() abort
    call s:CsDbMgmtShow(s:CsDbMgmtGet())
    " call s:CsDbMgmtGet()
endf

func! s:CsDbMgmtGet()
    let g:CsDbMgmtDbStatus = []

    if !filereadable(g:CsDbMgmtConfigFile)
        echo "you need have a config file befor"
        return
    endif

    if !isdirectory(g:CsDbMgmtDb)
        echo g:CsDbMgmtDb." must be a directory."
        return
    endif

    let l:config_json = eval(join(readfile(g:CsDbMgmtConfigFile)))
    for item in items(config_json)
        let l:db_list = []
        let l:db_status = 0
        let l:db_ftime = 0
        call add(l:db_list, item[0])

        " db's status check
        if filereadable(g:CsDbMgmtDb.item[0].'.out')
            let l:db_status = 1
            let l:db_ftime = getftime(g:CsDbMgmtDb.item[0].'.out')
        endif

        call add(l:db_list, l:db_status)
        call add(l:db_list, l:db_ftime)
        call add(l:db_list, item[1])
        call add(g:CsDbMgmtDbStatus, l:db_list)
    endfor

    call s:CsDbMgmtDecho(g:CsDbMgmtDbStatus)
    return g:CsDbMgmtDbStatus
endf

func! s:CsDbMgmtStripPrjNameFromGetline(line)
    return split(a:line, '|')[1]
endf

func! CsDbMgmtAttach(db)
    let l:prj_name = s:CsDbMgmtStripPrjNameFromGetline(a:db)
    exec "cs add ".g:CsDbMgmtDb.l:prj_name.'.out'
endf

func! CsDbMgmtDetach(db)
    let l:prj_name = s:CsDbMgmtStripPrjNameFromGetline(a:db)
    exec "cs kill ".g:CsDbMgmtDb.l:prj_name.'.out'
endf

func! s:CsDbMgmtGetPrjName(item)
    return a:item[0]
endf

func! s:CsDbMgmtGetDbStatus(item)
    if a:item[1] == 0
        return "DB non-Exist"
    else
        return "    DB Exist"
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
    let l:header = ['" Press a to attach', '" Press d to detach']
    call append(0, l:header)

    
    let l:all_db = []
    for l:item in a:content
        let l:sprintf = CsDbMgmtSprintf(l:item)
        call add(l:all_db, l:sprintf)
    endfor
    call sort(l:all_db)

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

    exec ':'.(len(l:header) + 1)
    redraw!
endf

