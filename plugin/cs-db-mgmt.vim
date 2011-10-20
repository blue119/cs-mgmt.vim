" cs-db-mgmt.vim:   Vim plugin providing cscope's database management
" Author:           Yao-Po Wang
" HomePage:         https://bitbucket.org/blue119/cs-db-mgmt.vim
" Version:          0.01

com! CsDbMgmt call CsDbMgmt()
map <Leader>cs :call CsDbMgmt()<CR>

if exists("g:CsDbMgmtPath")
    let g:CsDbMgmtPath = finddir(g:CsDbMgmtPath)
else
    let g:CsDbMgmtPath = $HOME."/.cscope_db/"
endif

func! CsDbMgmt() abort
    call CsDbShow(CsDbGet())
endf

func! CsDbGet()
    if !isdirectory(finddir(g:CsDbMgmtPath))
        echo "g:CsDbMgmtPath must be a directory."
        return
    endif
    let l:csdb = globpath(g:CsDbMgmtPath, "*.out")
    return l:csdb
endf

func! CsDbMgmtAttach(db)
    exec "cs add ".g:CsDbMgmtPath.a:db
endf

func! CsDbMgmtDetach(db)
    exec "cs kill ".g:CsDbMgmtPath.a:db
endf

func! CsDbShow(content)
  exec 'silent pedit csd.tmp'

  wincmd P | wincmd H

  let g:cdm_view = bufnr('%')
  let l:header = ['" Press a to attach', '" Press d to detach']
  call append(0, l:header)

  let l:all_db = []
  for l:str in split(a:content)
    call add(l:all_db, substitute(l:str, g:CsDbMgmtPath, "", ""))
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

