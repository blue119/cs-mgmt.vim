" cs-mgmt.vim:   Vim plugin providing cscope's database management
" Author:           Yao-Po Wang
" HomePage:         https://bitbucket.org/blue119/cs-mgmt.vim
" Version:          0.5
" Note:
"       the name of reference file : {parent name}*_{reference_name}.out
"       all cscope's cross-reference file is place in g:CsMgmtDbHome that
"       default setting is $HOME/.cs-mgmt/
"
"       simple item -> {O|X}\ {db_name}\ {timestamp}\ [Attach]
"       have group  -> {foo}:
"                          {bar}:
"                              {O|X}\ {db_name}\ {timestamp}\ [Attach]
"
" Usage:
"      :Csmgmtadd {'file' | 'url'} {file path} [{alias} [{group}]]
"      after adding a item of reference, it will be added to json file as well.
"      the file is indecated g:CsMgmtDbFile.
"      if it is comeing from from file, web url, or dpkg, these files will be
"      put into your g:CsMgmtDbHome/.source.
"
"      taking from apt, it will get source from apt mirror server and do
"      dpkg-source. it would provide a buffer to show multi-candidate when the
"      package term is not precision.
"
"      take from file procedure: Now it only support tarball file
"          1. checking file readable
"          2. copy to g:CsMgmtDbHome/.source, and then unpack it
"          3. add this item to json struct, and then write to file
"          4. udpate the buffer of the cs-mgmt
"

if exists('g:loaded_cs_mgmt') || &cp
  finish
endif
let g:loaded_cs_mgmt = 1

" Utils {{{
" Debug Function"{{{
" Debug print "{{{
func! s:decho(...)
    if g:CsMgmtDebugEnable
        call Decho(string(a:000[0]))
    endif
endf

func! s:dfunc(...)
    if g:CsMgmtDebugEnable
        call Dfunc(string(a:000[0]))
    endif
endf

func! s:dret(...)
    if g:CsMgmtDebugEnable
        call Dret(string(a:000[0]))
    endif
endf

func! s:cm_echo(msg)
    echo a:msg
endf

func! s:cm_echoerr(msg)
    echoerr a:msg
endf


func! s:cm_echohl0(msg)
    echomsg a:msg
endf

func! s:cm_echohl1(msg)
    echohl WarningMsg
        \ | echo a:msg
        \ | echohl None
endf

func! s:cm_echohl2(msg)
    echohl TabLine
        \ | echo a:msg
        \ | echohl None
endf

func! s:cm_echohl3(msg)
    echohl TabLineFill
        \ | echo a:msg
        \ | echohl None
endf

func! s:cm_echohl4(msg)
    echohl Title
        \ | echo a:msg
        \ | echohl None
endf
" }}} Debug print

" debug mode on/off {{{
if !exists('g:CsMgmtDebugEnable')
    let g:CsMgmtDebugEnable = 0
else
    if !exists('g:dechomode')
        call s:cm_echohl0( 'cs-mgmt: need the Decho plugin as enableing g:CsMgmtDebugEnable.' )
        finish
    endif
    let g:decho_bufenter = 1
    let g:decho_bufname = "cs-mgmt-debug"
endif

" }}} debug mode on/off
" }}} Debug Function
" }}} Utils

" the cm_engins's structure
" {'cscope': {
"               'cmd': 'cscope',
"               'langs': {'c': [all extension], },
"            },
" }
let s:cm_engines = {}
func! s:cm_engine_register(engine, cmd)
    call s:dfunc("cm_engine_register")
    call s:decho(printf("args: (%s, %s)", a:engine, a:cmd))
    let s:cm_engines[a:engine] = {'cmd': a:cmd}
    call s:decho(s:cm_engines)
    call s:dret("cm_engine_register")
endfunc

func! s:cm_engines_attach_set(engine, attach)
    call s:dfunc("cm_engines_attach_set")
    call s:decho(printf("args: (%s, %s)", a:engine, a:attach))
    let s:cm_engines[a:engine]['attach'] = function(a:attach)
    call s:decho(s:cm_engines[a:engine])
    call s:dret("cm_engines_attach_set")
endfunc

func! s:cm_engines_detach_set(engine, detach)
    call s:dfunc("cm_engines_detach_set")
    call s:decho(printf("args: (%s, %s)", a:engine, a:detach))
    let s:cm_engines[a:engine]['detach'] = function(a:detach)
    call s:decho(s:cm_engines[a:engine])
    call s:dret("cm_engines_detach_set")
endfunc

func! s:cm_engines_db_build_set(engine, db_build)
    call s:dfunc("cm_engines_db_build_set")
    call s:decho(printf("args: (%s, %s)", a:engine, a:db_build))
    let s:cm_engines[a:engine]['db_build'] = function(a:db_build)
    call s:decho(s:cm_engines[a:engine])
    call s:dret("cm_engines_db_build_set")
endfunc

func! s:cm_engines_db_rm_set(engine, db_rm)
    call s:dfunc("cm_engines_db_rm_set")
    call s:decho(printf("args: (%s, %s)", a:engine, a:db_rm))
    let s:cm_engines[a:engine]['db_rm'] = function(a:db_rm)
    call s:decho(s:cm_engines[a:engine])
    call s:dret("cm_engines_db_rm_set")
endfunc

func! s:cm_engines_db_exist_set(engine, db)
    call s:dfunc("cm_engines_db_exist_set")
    call s:decho(printf("args: (%s, %s)", a:engine, a:db))
    let s:cm_engines[a:engine]['db_exist_chk'] = function(a:db)
    call s:decho(s:cm_engines[a:engine])
    call s:dret("cm_engines_db_exist_set")
endfunc

" the lang's structure
" {
"   'C': [all extension of C with expr],
"   'C++': [*.c++, *.cc, *.cp, *.cpp, *.cxx, *.hh, *.hp, *.hpp, *.hxx, ],
" }
func! s:cm_engines_langs_set(engine, langs)
    call s:dfunc("cm_engines_langs_set")
    call s:decho(printf("args: (%s, %s)", a:engine, string(a:langs)))
    let s:cm_engines[a:engine]['langs'] = a:langs
    call s:decho(s:cm_engines[a:engine])
    call s:dret("cm_engines_langs_set")
endfunc

" a set of callback
func! s:cm_engine_attach(db)
    call s:dfunc("cm_engine_attach")
    call s:decho(printf("args: (%s)", string(a:db)))
    for engine in keys(s:cm_engines)
        call s:cm_engines[engine].attach(a:db)
    endfor
    call s:dret("cm_engine_attach")
endf

func! s:cm_engine_detach(db)
    call s:dfunc("cm_engine_detach")
    call s:decho(printf("args: (%s)", string(a:db)))
    for engine in keys(s:cm_engines)
        call s:cm_engines[engine].detach(a:db)
    endfor
    call s:dret("cm_engine_detach")
endf

func! s:cm_engine_db_build(db)
    call s:dfunc("cm_engine_db_build")
    call s:decho(printf("args: (%s)", string(a:db)))
    for engine in keys(s:cm_engines)
        call s:cm_engines[engine].db_build(a:db)
    endfor
    call s:dret("cm_engine_db_build")
endf

func! s:cm_engine_db_rm(db)
    call s:dfunc("cm_engine_db_rm")
    call s:decho(printf("args: (%s)", string(a:db)))
    for engine in keys(s:cm_engines)
        call s:cm_engines[engine].db_rm(a:db)
    endfor
    call s:dret("cm_engine_db_rm")
endf

" return engine name
func! s:cm_engine_db_exist_chk(db)
    call s:dfunc("cm_engine_db_exist_chk")
    call s:decho(printf("args: (%s)", string(a:db)))
    let l:ret = []
    for engine in keys(s:cm_engines)
        if s:cm_engines[engine].db_exist_chk(a:db)
            call add(l:ret, engine)
        endif
    endfor
    call s:dret("cm_engine_db_exist_chk")
    return l:ret
endf
"}}}

" where are your database
if !exists('g:CsMgmtDbHome')
    let g:CsMgmtDbHome = $HOME.'/.cs-mgmt/'
endif

" where are your config file
" by default, it will be put on $HOME/.cs-mgmt.json
if !exists('g:CsMgmtDbFile')
    let g:CsMgmtDbFile = g:CsMgmtDbHome.'/.cs-mgmt.json'
endif

" with CsMgmtAdd, that all source will be put into the folder.
if !exists('g:CsMgmtSrcDepot')
    let g:CsMgmtSrcDepot = g:CsMgmtDbHome . '.source_depot/'
endif

" re-attach the refernece file after rebuild
if !exists('g:CsMgmtReAttach')
    let g:CsMgmtReAttach = 0
endif

" Enable cscope engine. basically, it default to enable.
if !exists('g:CsMgmtCscopeEnable')
    let g:CsMgmtCscopeEnable = 1
endif

" Enable cscope engine. basically, it default to disable.
if !exists('g:CsMgmtCtagsEnable')
    let g:CsMgmtCtagsEnable = 0
endif

" Program Language Extension Support List. basically, it default to support c
" , cpp, and asm extension.
if !exists('g:CsMgmtLangsExtSupport')
    let g:CsMgmtLangsExtSupport = []
    let g:CsMgmtLangsExtSupport += ['c', 'h']
    let g:CsMgmtLangsExtSupport += ['s', 'S', 'asm']
    let g:CsMgmtLangsExtSupport += ['c++', 'cc', 'cp', 'cpp', 'cxx', 'h', 'h++', 'hh', 'hp', 'hpp', 'hxx', 'C', 'H']
endif

" Cscoope's Function"{{{
if g:CsMgmtCscopeEnable == 1
    func! s:cm_cscope_attach(db) dict
        if has('nvim-9')
            exec printf("Cs db add %s.out", a:db)
        else
            exec printf("cs add %s.out", a:db)
        endif
    endf

    func! s:cm_cscope_detach(db) dict
        if has('nvim-9')
            exec printf("Cs db rm %s.out", a:db)
        else
            exec printf("cs kill %s.out", a:db)
        endif
    endf

    func! s:cm_cscope_db_build(ref_name) dict
        let l:cmd_string = printf('cd %s && cscope -b -q -k -i%s.files -f%s.out',
                \ g:CsMgmtDbHome, a:ref_name, a:ref_name)

        call s:cm_echohl2( a:ref_name.' building for cscope .... ' )
        call system(l:cmd_string)
        call s:cm_echohl4( a:ref_name.' built success.' )
    endf

    func! s:cm_cscope_db_rm(db) dict
        let l:suffixs = ['.files', '.out', '.out.in', '.out.po']

        for suffix in l:suffixs
            call delete(a:db . suffix)
        endfor
    endf

    func! s:cm_cscope_db_exist_chk(db) dict
        return filereadable(a:db . '.out')
    endf

    func! s:cm_cscope_engine_init()
        call s:dfunc("cm_cscope_engine_init")
        if executable('cscope')
            let cscope_cmd = 'cscope'
            call s:cm_engine_register('cscope', 'cscope')
            call s:cm_engines_attach_set('cscope', 's:cm_cscope_attach')
            call s:cm_engines_detach_set('cscope', 's:cm_cscope_detach')
            call s:cm_engines_db_build_set('cscope', 's:cm_cscope_db_build')
            call s:cm_engines_db_rm_set('cscope', 's:cm_cscope_db_rm')
            call s:cm_engines_db_exist_set('cscope', 's:cm_cscope_db_exist_chk')

            " refer to ctags
            let l:langs = {}
            let l:langs['C'] = ['*.c']
            let l:langs['C++'] = ['*.c++', '*.cc', '*.cp', '*.cpp', '*.cxx', '*.h', '*.h++', '*.hh', '*.hp', '*.hpp', '*.hxx', '*.C', '*.H']
            call s:cm_engines_langs_set('cscope', l:langs)
        else
            call s:cm_echohl0('cs-mgmt: cscope command not found in PATH.')
            call s:cm_echohl0('cs-mgmt: you can disable cscope engine by "let g:CsMgmtCscopeEnable = 0".')
            finish
        endif
        call s:dret("cm_cscope_engine_init")
    endf

    call s:cm_cscope_engine_init()
endif " if g:CsMgmtCscopeEnable == 1
" }}}

" Ctags's Function"{{{
if g:CsMgmtCtagsEnable == 1
    func! s:cm_ctags_attach(db) dict
        let l:tag = a:db . ".tags"
        if &tags == ""
            exec printf("set tags=%s", l:new_tags)
        else
            exec printf("set tags=%s,%s", &tags, l:tag)
        endif
    endf

    func! s:cm_ctags_detach(db) dict
        let l:tag = a:db . ".tags"
        let l:new_tags = ""
        for t in split(&tags, ",")
            if t != l:tag
                if l:new_tags == ""
                    let l:new_tags = t
                else
                    let l:new_tags = l:new_tags . ',' . t
                endif
            endif
        endfor
        exec printf("set tags=%s", l:new_tags)
    endf

    func! s:cm_ctags_db_build(ref_name) dict
        let l:cmd_string = printf('cd %s && ctags -L %s.files -f %s.tags',
                \ g:CsMgmtDbHome, a:ref_name, a:ref_name)

        call s:cm_echohl2( a:ref_name.' building for ctags .... ' )
        call system(l:cmd_string)
        call s:cm_echohl4( a:ref_name.' built success.' )
    endf

    func! s:cm_ctags_db_rm(db) dict
        call delete(a:db . '.tags')
    endf

    func! s:cm_ctags_db_exist_chk(db) dict
        return filereadable(a:db . '.tags')
    endf

    func! s:cm_ctags_engine_init()
        call s:dfunc("cm_ctags_engine_init")
        if executable('ctags')
            let ctags_cmd = 'ctags'
            call s:cm_engine_register('ctags', 'ctags')
            call s:cm_engines_attach_set('ctags', 's:cm_ctags_attach')
            call s:cm_engines_detach_set('ctags', 's:cm_ctags_detach')
            call s:cm_engines_db_build_set('ctags', 's:cm_ctags_db_build')
            call s:cm_engines_db_rm_set('ctags', 's:cm_ctags_db_rm')
            call s:cm_engines_db_exist_set('ctags', 's:cm_ctags_db_exist_chk')

            let l:langs = {}
            let l:langs_map = split(system('ctags --list-maps'), '\n')
            for lang in l:langs_map
                let l:l = split(lang)
                let l:langs[l:l[0]] = l:l[1:]
            endfor
            call s:cm_engines_langs_set('ctags', l:langs)

        else
            call s:cm_echohl0('cs-mgmt: ctags command not found in PATH.')
            call s:cm_echohl0('cs-mgmt: Please disable the g:CsmgmtCtagsEnable variable.')
            let g:CsMgmtCtagsEnable = 0
        endif
        call s:dret("cm_ctags_engine_init")
    endf

    call s:cm_ctags_engine_init()
endif " if g:CsMgmtCtagsEnable == 1
"}}}

" core utils"{{{
func! s:cm_get_src_from_file(path)
    if !filereadable(a:path)
        call s:cm_echohl1( a:path . ' is not readable.' )
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
        call s:cm_echo( 'the type of file do not support.' )
        return -1
    endif

    if isdirectory(l:tmpfolder)
        call s:cm_echo( l:tmpfolder . ' folder conflict!! you have to remove it before.' )
        return -1
    else
        " 1. create a tmp folder on g:CsMgmtSrcDepot that name is its file name.
        if mkdir(l:tmpfolder) != 1
            call s:cm_echohl1( 'Can not create the tmpfolder ' . l:tmpfolder )
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
            call s:cm_echohl1( l:finalfolder
                    \ . ' folder conflict!! you have to remove it before.' )
            return -1
        else
            call system(
                \ printf('mv %s/%s %s', l:tmpfolder, l:first_folder, l:finalfolder))
            call system('rm -rf ' . l:tmpfolder)
        endif
    else
        let l:finalfolder = g:CsMgmtSrcDepot . l:filename
        " call s:decho(printf('mv %s %s', l:tmpfolder, l:finalfolder))
        call system(printf('mv %s %s', l:tmpfolder, l:finalfolder))
    endif

    return l:finalfolder
endf

func! s:cm_get_src_from_dir(path)
    if !isdirectory(a:path)
        call s:cm_echohl1( a:path . ' is not a directory.' )
        return
    endif

    return a:path
endf

" to verify the name conflict of grouping path in CsMgmtDb
" return [g_parent, g_name]
func! s:cm_grp_chk_n_split(group)
    " to check reserved words in g_name excepting '/' word, and
    " reduce the repeating '/' to onece.
    let l:g_name = []
    let l:g_parent = []
    for i in split(a:group, "/")
        if len(i)
            if len(s:cm_filename_resv_words(i))
                call s:cm_echohl1("Don't contain reserved words in group name.")
                return
            endif
            call add(l:g_name, i)
        endif
    endfor

    let l:db = copy(s:cm_db_get())
    while len(l:g_name)
        let k = l:g_name[0]
        if has_key(l:db, k)
            if type(l:db[k]) != 4
                call s:cm_echohl1("name conflict.")
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

" grp walk and append to collect_list
func! s:cm_grp_walk(indent_level, collect_list, config, parent)
    let l:indent_level = a:indent_level + 1

    for k in keys(a:config)
        if type(a:config[k]) == 3
            call add(a:collect_list,
                    \ s:cm_show_item_construct(l:indent_level, a:parent, k))
        elseif type(a:config[k]) == 4
            call add(a:collect_list, printf('%s:', s:cm_str_add_indent(l:indent_level, k)))
            call s:cm_grp_walk(l:indent_level, a:collect_list,
                        \ a:config[k], printf('%s_%s', a:parent, k))
        endif
    endfor
endf

func! s:cm_str_add_indent(indent_level, str)
    return repeat(s:cm_indent_token, a:indent_level).a:str
endf
"}}}







let s:cm_db_exist_token = 'O'
let s:cm_db_nonexist_token = 'X'
let s:cm_indent_token = '    '

if !exists('s:cm_db_attached_list')
    let s:cm_db_attached_list = []
endif

let s:cm_grp_re = '\(^\s\{}\)'
                \ .'\(.*\):'

let s:cm_db_exist_re = '^\(\s\{}\)'
                \ .'\([OX]\)\s'
                \ .'\([0-9a-zA-Z\-._~+]\{}\)\s\{}'
                \ .'\(\d\{2}/\d\{2}/\d\{2}\s\d\{2}\:\d\{2}\)'
                \ .'\(Attach\)\{}'

let s:cm_db_nonexist_re = '^\(\s\{}\)'
                \ .'\([OX]\)\s'
                \ .'\([0-9a-zA-Z\-._~+]\{}\)\s\{}'


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

" recognize item and return corresponding re
func! s:cm_re_get(line)
    let l:str = s:cm_str_strip(a:line)

    if l:str[-1:] == ':'
        return s:cm_grp_re
    elseif l:str[0:len(s:cm_db_exist_token)-1] == s:cm_db_exist_token
        return s:cm_db_exist_re
    elseif l:str[0:len(s:cm_db_nonexist_token)-1] == s:cm_db_nonexist_token
        return s:cm_db_nonexist_re
    endif
endf

func! s:cm_item_indent_get(line)
    let l:re = s:cm_re_get(a:line)
    let l:l = matchstr(a:line, l:re)
    return substitute(l:l, l:re, '\1', '')
endf

func! s:cm_item_status_get(line)
    let l:re = s:cm_re_get(a:line)
    let l:l = matchstr(a:line, l:re)
    return substitute(l:l, l:re, '\2', '')
endf

func! s:cm_item_name_get(line)
    let l:re = s:cm_re_get(a:line)
    let l:l = matchstr(a:line, l:re)
    return substitute(l:l, l:re, '\3', '')
endf

func! s:cm_item_timestamp_get(line)
    let l:re = s:cm_re_get(a:line)
    let l:l = matchstr(a:line, l:re)
    return substitute(l:l, l:re, '\4', '')
endf

func! s:cm_item_attach_get(line)
    let l:re = s:cm_re_get(a:line)
    let l:l = matchstr(a:line, l:re)
    return substitute(l:l, l:re, '\5', '')
endf

func! s:cm_item_level_get(line)
    return (len(s:cm_item_indent_get(a:line))/len(s:cm_indent_token))
endf

" return string format 'l:ref_status_token l:db_name l:ref_ftime l:db_attach'
func! s:cm_show_item_construct(indent_level, parent, ref_name)
    let l:ref_full_name = (a:parent == '') ?
                \   (a:ref_name):
                \   (a:parent.'_'.a:ref_name)
    let l:ref_status_token = s:cm_db_nonexist_token
    let l:ref_attach = ''
    let l:ref_indent = repeat(s:cm_indent_token, a:indent_level)

    " to check the status of the reference file
    " call s:decho(g:CsMgmtDbHome.l:ref_full_name.'.out')
    if filereadable(g:CsMgmtDbHome.l:ref_full_name.'.out')
        let l:ref_status_token = s:cm_db_exist_token
        let l:ref_ftime = strftime("%D %H:%M",
                    \ getftime(g:CsMgmtDbHome.l:ref_full_name.'.out'))

        if index(s:cm_db_attached_list, l:ref_full_name) != -1
            let l:ref_attach = ' Attach'
        endif
    endif

    if l:ref_status_token == s:cm_db_exist_token
        return printf("%s%s %s %s%s",
                    \ l:ref_indent, l:ref_status_token,
                    \ a:ref_name, l:ref_ftime, l:ref_attach)
    else
        return printf("%s%s %s", l:ref_indent, l:ref_status_token, a:ref_name)
    endif
endf

" look down and only included more level than it until it run into a blank line
func! s:cm_children_pos_list_on_buf_get(level, line, pos)
    let l:pos = a:pos
    let l:level = a:level
    let l:children_pos_list = []

    while 1
        let l:pos += 1
        if s:cm_item_level_get(getline(l:pos)) > (l:level)
                \ && s:cm_is_not_item_line(getline(l:pos)) == 0
            call insert(l:children_pos_list, l:pos, 0)
        endif

        if s:cm_is_blank_line(getline(l:pos)) == 1
            break
        endif
    endwhile

    return l:children_pos_list
endf

func! s:cm_parent_list_on_buf_get(level, line, pos)
    let l:pos = a:pos
    let l:level = a:level
    let l:parent_list = []

    if l:level == 0
        return l:parent_list
    endif

    while 1
        let l:pos -= 1
        if s:cm_item_level_get(getline(l:pos)) == (l:level - 1)
            call insert(l:parent_list, s:cm_str_strip(getline(l:pos))[:-2], 0)
            let l:level -= 1

            if s:cm_item_level_get(getline(l:pos)) == 0
                break
            endif
        endif

        if l:pos == 0
            "feel more safe
            call s:cm_echoerr( 'program error' )
            exit
        endif
    endwhile

    return l:parent_list
endf

func! s:cm_is_comment_line(line)
    if a:line[0] == '"'
        return 1
    else
        return 0
    endif
endf

func! s:cm_is_grp_line(line)
    if a:line[-1:] == ':'
        return 1
    else
        return 0
    endif
endf

func! s:cm_is_blank_line(line)
    if a:line == ''
        return 1
    else
        return 0
    endif
endf

func! s:cm_is_not_item_line(line)
    if   s:cm_is_blank_line(a:line)
    \ || s:cm_is_grp_line(a:line)
    \ || s:cm_is_comment_line(a:line)
        return 1
    else
        return 0
    endif
endf

func! s:cm_is_item_n_grp(line)
    if   s:cm_is_blank_line(a:line)
    \ || s:cm_is_comment_line(a:line)
        return 0
    else
        return 1
    endif
endf

func! s:cm_buf_write_mode_set()
    setl buftype=
    setl modifiable
endf

func! s:cm_buf_readonly_mode_set()
    setl nomodifiable
    setl buftype=nofile
endf

" check the g:CsMgmtDbHome exist or not. new one folder, if not existing.
func! s:cm_db_home_chk_n_new()
    if !isdirectory(g:CsMgmtDbHome)
        if filereadable(g:CsMgmtDbHome)
            call s:cm_echohl1( g:CsMgmtDbHome . " must be a directory." )
            return -1
        endif

        if mkdir(g:CsMgmtDbHome) != 1
            call s:cm_echohl1( 'Can not create ' . g:CsMgmtDbHome)
            return -1
        endif
    endif
endf

func! s:cm_db_chk()
    if !filereadable(g:CsMgmtDbFile)
        call s:cm_echohl1( "you need have a config file befor" )
        return -1
    endif

    if s:cm_db_home_chk_n_new() == -1
        return -1
    endif
endf

func! s:cm_db_get_from_file()
    if !filereadable(g:CsMgmtDbFile)
		if s:cm_db_home_chk_n_new() == -1
			return -1
		endif

        " default config
        call writefile(["{'usr_include' : ['/usr/include/', ],}"], g:CsMgmtDbFile )
    endif

    return eval(join(readfile(g:CsMgmtDbFile)))
endf

func! s:cm_db_get()
    if !exists('s:CsMgmtDb') || &cp
        let s:CsMgmtDb = s:cm_db_get_from_file()
    endif

    return s:CsMgmtDb
endf

func! s:cm_db_rm(line, pos)
    if s:cm_is_not_item_line(a:line) == 1
        " echo 'it is a unexpect line'
        return
    endif

    " if it has attached
    call CsMgmtDetach(a:line, a:pos)

    " look for key of deletion
    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)
    let l:ref_name = s:cm_item_name_get(a:line)
    let l:parent_key = s:cm_db_get()

    if len(l:parent_list)
        for p in l:parent_list
            let l:parent_key = l:parent_key[p]
        endfor
    endif

    call s:cm_engine_db_rm(g:CsMgmtDbHome . l:ref_name)

    " delete
    unlet l:parent_key[l:ref_name]
endf

func! s:cm_db_grp_rm(line, pos)
    " find childrens
    let l:level = s:cm_item_level_get(a:line)
    let l:ref_name = s:cm_str_strip(getline(a:pos))[:-2]
    let l:pos = a:pos

    while 1
        let l:pos += 1
        if s:cm_item_level_get(getline(l:pos)) <= l:level
            break
        endif

        let l:line = getline(l:pos)
        if s:cm_is_not_item_line(l:line) == 0
            " echo l:line
            call s:cm_db_rm(l:line, l:pos)
        endif
    endwhile

    let l:parent_list = s:cm_parent_list_on_buf_get(l:level, a:line, a:pos)
    let l:parent_key = s:cm_db_get()

    if len(l:parent_list)
        for p in l:parent_list
            let l:parent_key = l:parent_key[p]
        endfor
    endif

    " delete
    unlet l:parent_key[l:ref_name]
endf

func! s:cm_path_walk(path, all_file_list)
    call s:dfunc("cm_path_walk")
    call s:decho(a:path)

    let l:file_list = split(globpath(a:path, '*'), '\n')
    for file in l:file_list
        if isdirectory(file)
            call s:cm_path_walk(file, a:all_file_list)
        else
            let l:regexp = ""
            call s:decho(g:CsMgmtLangsExtSupport)
            for l:ext in g:CsMgmtLangsExtSupport
                let l:regexp = l:regexp . printf('\.%s$\|', l:ext)
            endfor
            let l:regexp = l:regexp[:-3] " remove last '\|'
            call s:decho(l:regexp)

            if match(file, l:regexp) >= 0
                call add(a:all_file_list, file)
            endif
        endif
    endfor
    call s:dret("cm_path_walk")
endf

func! s:cm_path_list_on_conf_get(parent_list, ref_name)
    let l:config = s:cm_db_get()

    if len(a:parent_list) > 0
        for p in a:parent_list
            let l:config = config[p]
        endfor
    endif

    return l:config[a:ref_name]
endf

" the token is used to compose a reverseable string from list
let s:rvs_able_token = "!@!"
func! s:cm_list_to_rvs_able_str(plist)
    if len(a:plist) == 0 | return "" | endif
    return join(a:plist, s:rvs_able_token)
endf

func! s:cm_rvs_able_to_list(str)
    return split(a:str, s:rvs_able_token)
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
                        \   " : " . "'" . l:value . "'," )

        elseif l:vt == 3
            call add(s:json2file_list,
                    \ repeat(s:cm_indent_token, l:il) .
                    \ "'" . l:key . "'" . " : " . "[")

            let l:il += 1
            for i in l:value
                call add(s:json2file_list,
                        \ repeat(s:cm_indent_token, l:il) .
                        \ "'" . i . "',")
            endfor
            let l:il -= 1
            call add(s:json2file_list, repeat(s:cm_indent_token, l:il) . "],")

        elseif l:vt == 4
            call add(s:json2file_list,
                    \ repeat(s:cm_indent_token, l:il) .
                    \ "'" . l:key . "'" . " : " . "{")

            let l:il += 1
            call s:cm_json_dip(l:il, l:value)
            let l:il -= 1
            call add(s:json2file_list, repeat(s:cm_indent_token, l:il) . "},")
        endif
    endfor
endf

func! s:cm_json_to_file()
    let s:json2file_list = []
    let l:indent_level = 0
    let l:json = s:cm_db_get()

    let l:indent_level += 1
    call add(s:json2file_list, '{')
    call s:cm_json_dip(l:indent_level, l:json)
    call add(s:json2file_list, '}')
    call writefile(s:json2file_list, g:CsMgmtDbFile)
endf





func! CsMgmtAttach(line, pos)
    call s:dfunc("CsMgmtAttach")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_is_grp_line(a:line) == 1
        call s:decho("a grp line.")
        call s:CsMgmtAttachGrp(a:line, a:pos)
        call s:dret("CsMgmtAttach")
        return
    endif

    if s:cm_is_not_item_line(a:line) == 1
        " echo 'it is a unexpect line'
        call s:decho("a unexpect line.")
        call s:dret("CsMgmtAttach")
        return
    endif

    if s:cm_str_strip(a:line)[0] == s:cm_db_nonexist_token
        call s:cm_echohl1(s:cm_item_name_get(a:line) . " has not built.")
        return
    endif

    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)
    let l:ref_name = s:cm_item_name_get(a:line)

    let l:ref_full_name = (len(l:parent_list) == 0) ?
                \   (l:ref_name):
                \   (join(l:parent_list, '_').'_'.l:ref_name)

    if index(s:cm_db_attached_list, l:ref_full_name) != -1
        " call s:cm_echohl1("Don\'t Attach Twice")
        return
    endif

    " add to attach list
    call add(s:cm_db_attached_list, l:ref_full_name)

    " add a Attach word on the end of line
    call s:cm_buf_write_mode_set()
    call setline(a:pos, a:line." Attach")
    call s:cm_buf_readonly_mode_set()

    call s:cm_engine_attach(g:CsMgmtDbHome . l:ref_full_name)

    call s:dret("CsMgmtAttach")
endf

func! s:CsMgmtAttachGrp(line, pos)
    call s:dfunc("CsMgmtAttachGrp")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_is_grp_line(a:line) == 0
        " echo 'it is a unexpect line'
        call s:decho("is not grp line")
        call s:dret("CsMgmtAttachGrp")
        return
    endif

    let l:level = s:cm_item_level_get(a:line)
    let l:childre_pos_list = s:cm_children_pos_list_on_buf_get(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtAttach(getline(p), p)
    endfor
    call s:dret("CsMgmtAttachGrp")
endf

func! CsMgmtDetach(line, pos)
    call s:dfunc("CsMgmtDetach")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_is_grp_line(a:line) == 1
        call s:CsMgmtDetachGrp(a:line, a:pos)
        call s:dret("CsMgmtDetach")
        return
    endif

    if s:cm_is_not_item_line(a:line) == 1
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtDetach")
        return
    endif

    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)
    let l:ref_name = s:cm_item_name_get(a:line)

    let l:ref_full_name = (len(l:parent_list) == 0) ?
                \   (l:ref_name):
                \   (join(l:parent_list, '_').'_'.l:ref_name)

    if index(s:cm_db_attached_list, l:ref_full_name) == -1
        " call s:cm_echohl1("Need Attach Befor")
        return
    endif

    " remove from attach list
    call filter(s:cm_db_attached_list, 'v:val !~ "'.l:ref_full_name.'"')

    " add a Attach word on the end of line
    call s:cm_buf_write_mode_set()
    call setline(a:pos, a:line[0:-len(" Attach")-1])
    call s:cm_buf_readonly_mode_set()

    call s:cm_engine_detach(g:CsMgmtDbHome . l:ref_full_name)

    call s:dret("CsMgmtDetach")
endf

func! s:CsMgmtDetachGrp(line, pos)
    call s:dfunc("CsMgmtDetachGrp")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_is_grp_line(a:line) == 0
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtDetachGrp")
        return
    endif

    let l:level = s:cm_item_level_get(a:line)
    let l:childre_pos_list = s:cm_children_pos_list_on_buf_get(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtDetach(getline(p), p)
    endfor
    call s:dret("CsMgmtDetachGrp")
endf

func! CsMgmtBuild(line, pos)
    call s:dfunc("CsMgmtBuild")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_is_grp_line(a:line) == 1
        call s:decho("Build By Group: ".a:line)
        call s:CsMgmtBuildGrp(a:line, a:pos)
        call s:dret("CsMgmtBuild")
        return
    endif

    if s:cm_is_not_item_line(a:line) == 1
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtBuild")
        return
    endif

    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)
    let l:ref_name = s:cm_item_name_get(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ?
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:ref_full_name = (l:parent == '') ?
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    if filereadable(g:CsMgmtDbHome.l:ref_full_name.'.out')
        let l:msg = "it has existed on " . g:CsMgmtDbHome
                    \ . ' you can try to rebuild it.'
        call s:cm_echohl1(l:msg)
        return
    endif

    " file create
    call writefile(l:all_file_list, g:CsMgmtDbHome.l:ref_full_name.'.files')

    let l:path_list = s:cm_path_list_on_conf_get(l:parent_list, l:ref_name)

    " if type(l:path_list) == 1
        " let l:path_list = [l:path_list]
    " endif

    call s:cm_echohl3( l:ref_name.' collecting.... ' )

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
            \ .  ' because no fidning any c or cpp file in ' . string(l:path_list)
        call s:cm_echohl1(l:msg)
        return
    endif

    " write to file
    call writefile(l:all_file_list, g:CsMgmtDbHome.l:ref_full_name.'.files')

    " XXX: don't need g:CsMgmtDbHome
    call s:cm_engine_db_build(l:ref_full_name)

    " add a Attach word on the end of line
    call s:cm_buf_write_mode_set()
    call setline(a:pos,
        \ s:cm_show_item_construct(l:ref_level, l:parent, l:ref_name))
    call s:cm_buf_readonly_mode_set()
    call s:dret("CsMgmtBuild")
endf

func! s:CsMgmtBuildGrp(line, pos)
    call s:dfunc("CsMgmtBuildGrp")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_is_grp_line(a:line) == 0
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtBuildGrp")
        return
    endif

    let l:level = s:cm_item_level_get(a:line)
    let l:childre_pos_list = s:cm_children_pos_list_on_buf_get(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtBuild(getline(p), p)
    endfor
    call s:dret("CsMgmtBuildGrp")
endf

func! CsMgmtRebuild(line, pos)
    call s:dfunc("CsMgmtRebuild")
    call s:decho(printf("args: (%s, %s)", string(a:line), string(a:pos)))

    if s:cm_is_grp_line(a:line) == 1
        call s:CsMgmtRebuildGrp(a:line, a:pos)
        call s:dret("CsMgmtReBuild")
        return
    endif

    if s:cm_is_not_item_line(a:line) == 1
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtReBuild")
        return
    endif

    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)
    let l:ref_name = s:cm_item_name_get(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ?
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:ref_full_name = (l:parent == '') ?
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    if !filereadable(g:CsMgmtDbHome.l:ref_full_name.'.out')
        let l:msg =  l:ref_name.' not existed on '.g:CsMgmtDbHome.
                    \ ' you have to build it at first.'
        call s:cm_echohl1(l:msg)
        return
    endif

    " file create
    call writefile(l:all_file_list, g:CsMgmtDbHome.l:ref_full_name.'.files')

    let l:path_list = s:cm_path_list_on_conf_get(l:parent_list, l:ref_name)
    call s:decho("path_list: " . string(l:path_list))

    " if type(l:path_list) == 1
        " let l:path_list = [l:path_list]
    " endif

    call s:cm_echohl3( l:ref_name.' collecting.... ' )

    let l:include_path_list = []
    let l:knock_out_path_list = []
    for p in (type(l:path_list) == 1 ? [l:path_list] : l:path_list)
        if p[0] == '-'
            call add(l:knock_out_path_list, p[1:])
        else
            call add(l:include_path_list, p)
        endif
    endfor
    call s:decho("include_path_list: " . string(l:include_path_list))
    call s:decho("knock_out_path_list: " . string(l:knock_out_path_list))

    for p in l:include_path_list
        call s:cm_path_walk(p, l:all_file_list)
    endfor

    for p in l:knock_out_path_list
        call filter(l:all_file_list, 'v:val !~ "'. p .'"')
    endfor

    if len(l:all_file_list) == 0
        let l:msg =  'It is not finish to build cscope reference,'
            \ .  ' because no fidning any c or cpp file in ' . string(l:path_list)
        call s:cm_echohl1(l:msg)
        return
    endif

    " write to file
    call writefile(l:all_file_list, g:CsMgmtDbHome.l:ref_full_name.'.files')

    call s:cm_engine_db_build(l:ref_full_name)

    " add a Attach word on the end of line
    call s:cm_buf_write_mode_set()
    call setline(a:pos,
        \ s:cm_show_item_construct(l:ref_level, l:parent, l:ref_name))
    call s:cm_buf_readonly_mode_set()

    if g:CsMgmtReAttach == 1 && index(s:cm_db_attached_list, l:ref_full_name) != -1
        call CsMgmtDetach(a:line, a:pos)
        call CsMgmtAttach(a:line[0:-len(" Attach")-1], a:pos)
    endif
    call s:dret("CsMgmtRebuild")
endf

func! s:CsMgmtRebuildGrp(line, pos)
    call s:dfunc("CsMgmtRebuildGrp")
    call s:decho(printf("args: (%s, %s)", string(a:line), string(a:pos)))

    if s:cm_is_grp_line(a:line) == 0
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtRebuildGrp")
        return
    endif

    let l:level = s:cm_item_level_get(a:line)
    let l:childre_pos_list = s:cm_children_pos_list_on_buf_get(l:level, a:line, a:pos)
    for p in l:childre_pos_list
        call CsMgmtRebuild(getline(p), p)
    endfor
    call s:dret("CsMgmtRebuildGrp")
endf

let s:cm_edit_prev_bufnr = 0
func! CsMgmtEdit(line, pos)
    call s:dfunc("CsMgmtEdit")
    call s:decho(printf("args: (%s, %s)", string(a:line), string(a:pos)))

    if s:cm_is_item_n_grp(a:line) == 0
        call s:decho(a:line)
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtEdit")
        return
    endif

    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)

    if s:cm_is_grp_line(a:line) == 1
        let l:ref_name = s:cm_str_strip(a:line)[:-2]
    else
        let l:ref_name = s:cm_item_name_get(a:line)
    endif
    let l:parent = (len(l:parent_list) == 0) ?
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:parent_rvs = s:cm_list_to_rvs_able_str(l:parent_list)

    let l:ref_full_name = (l:parent == '') ?
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    call s:decho("ref_level: " . l:ref_level)
    call s:decho("ref_name: " . l:ref_name)
    call s:decho("ref_full_name: " . l:ref_full_name)
    call s:decho("parent_list: " . string(l:parent_list))
    call s:decho("parent: " . l:parent)
    call s:decho("parent_rvs: " . l:parent_rvs)

    let l:db= s:cm_db_get()
    let l:item = {}
    " no parent, if it is stay in top level
    if l:ref_level
        for i in l:parent_list
            let l:db= l:db[i]
        endfor
    endif

    let l:item[l:ref_name] = l:db[l:ref_name]
    call s:decho(l:item)

    let l:tmp = l:parent_list
    let l:edit_bufn = s:cm_list_to_rvs_able_str(insert(l:tmp, tempname(), 0)) . '.cs-mgmt-edit'
    call s:decho("edit_bufn: " .  l:edit_bufn)

    wincmd l

    let s:cm_edit_prev_bufnr = bufnr('%')
    " call s:decho("cm_edit_prev_bufnr: " . s:cm_edit_prev_bufnr)

    exec 'silent edit ' . l:edit_bufn

    setl ft=json
    setl noswapfile

    let s:json2file_list = []

    call add(s:json2file_list, '{')
    call s:cm_json_dip(1, l:item)
    call add(s:json2file_list, '}')

    for i in s:json2file_list
        call append(line('$')-1, i)
    endfor

    call s:dret("CsMgmtEdit")
endf

func! CsMgmtDelete(line, pos)
    call s:dfunc("CsMgmtDelete")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_is_not_item_line(a:line) == 1
        if s:cm_is_grp_line(a:line) == 1
            " delete a group
            call s:cm_db_grp_rm(a:line, a:pos)
            call s:cm_json_to_file()
            call s:cm_mgmt_buf_refresh(line("."))
        endif
    else
        call s:cm_db_rm(a:line, a:pos)
        call s:cm_json_to_file()
        call s:cm_mgmt_buf_refresh(line("."))
    endif
    call s:dret("CsMgmtDelete")
endf

func! CsMgmtQuit(line, pos)
    call s:dfunc("CsMgmtQuit")
    call s:decho(printf("args: (%s, %d)", a:line, a:pos))

    if s:cm_futher_info_buf_on
        wincmd j | wincmd q | wincmd h
    endif

    exec 'silent bd!'
    call s:dret("CsMgmtQuit")
endf

let s:cm_futher_info_buf_on=0
func! CsMgmtFurtherInfo(line, pos)
    call s:dfunc(printf("CsMgmtFurtherInfo(%s, %d) enter",
                \ a:line, a:pos))
    if s:cm_is_not_item_line(a:line) == 1
        " echo 'it is a unexpect line'
        call s:decho("a unexpect line.")
        call s:dret("CsMgmtFurtherInfo")
        return
    endif

    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)
    let l:ref_name = s:cm_item_name_get(a:line)
    let l:parent = (len(l:parent_list) == 0) ?
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:parent_rvs = s:cm_list_to_rvs_able_str(l:parent_list)
    let l:ref_full_name = (l:parent == '') ?
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    let l:item = s:cm_db_get()
    for p in l:parent_list | let l:item = l:item[p] | endfor

    let l:abs_path = g:CsMgmtDbHome . l:ref_full_name . ".files"
    let l:full_ftime = strftime("%F %T",
                    \ getftime(g:CsMgmtDbHome.l:ref_full_name.'.out'))

    call s:decho("ref_level: " . l:ref_level)
    call s:decho("ref_name: " . l:ref_name)
    call s:decho("ref_full_name: " . l:ref_full_name)
    call s:decho("parent_list: " . string(l:parent_list))
    call s:decho("parent: " . l:parent)

    if s:cm_futher_info_buf_on == 1
        " closing further infor window
        wincmd j | wincmd q | wincmd h
        let s:cm_futher_info_buf_on = 0
    endif

    wincmd s | wincmd r

    let s:cm_futher_info_buf_on=1
    exec 'silent edit ' . tempname()
    setl ft=vim
    setl buftype=nofile
    setl noswapfile

    call append(line('$')-1, "Last Update: " . l:full_ftime)

    let l:db_exist = s:cm_engine_db_exist_chk(g:CsMgmtDbHome . l:ref_full_name)
    call append(line('$')-1, "DB Exist: " . string(l:db_exist))

    " Including
    " call s:cm_echohl0('Determining Include Language......')
    call append(line('$')-1, (""))
    call append(line('$')-1, ("Include Language:"))
    let files_n = system('cat '.l:abs_path.' | wc -l')[:-2] " also remove \n

    let l:ret = split(system('cloc --progress-rate=0 --skip-uniqueness --csv --list-file='.l:abs_path), '\n')
    let l:ignored = matchlist(l:ret[2], '\ *\(\d\+\)\ files ignored.')[1]
    let l:files_n -= l:ignored

    let l:counted = 0
    for i in l:ret[5:]
        let l:split = matchlist(i, '\(\d\+\),\(.*\),\(\d\+\),\(\d\+\),\(\d\+\)')
        if len(ret)
            let l:rate = eval(l:split[1].'/'.l:files_n.'.0') * 100
            call append(line('$')-1, printf('    %s: %.2f%%', l:split[2], l:rate))
            let l:counted += l:split[1]
        endif
    endfor
    if l:files_n - l:counted
        call append(line('$')-1, printf('    Other: %.2f%%', eval(printf('((%d-%d.0)/%d)*100', l:files_n, l:counted, l:files_n))))
    endif
    " Including


    " exclude rate
    " TODO: more reference folder in l:item[l:ref_name]
    " call s:cm_echohl1('Determining Exclude Language......')
    call append(line('$')-1, (""))
    call append(line('$')-1, ("Exclude Language:"))
    let l:ret = split(system( printf('%s',  'cloc --progress-rate=0 --skip-uniqueness --csv --exclude-list-file='.l:abs_path.' '.l:item[l:ref_name][0])) , '\n')

    let l:files_n = matchlist(l:ret[0], '\ *\(\d\+\)\ text files.')[1]
    let l:ignored = matchlist(l:ret[2], '\ *\(\d\+\)\ files ignored.')[1]
    let l:files_n -= l:ignored

    let l:counted = 0
    for i in l:ret[5:]
        let l:split = matchlist(i, '\(\d\+\),\(.*\),\(\d\+\),\(\d\+\),\(\d\+\)')
        if len(ret)
            let l:rate = eval(l:split[1].'/'.l:files_n.'.0') * 100
            call append(line('$')-1, printf('    %s: %.2f%%', l:split[2], l:rate))
            let l:counted += l:split[1]
        endif
    endfor
    if (l:files_n - l:counted) > 0
        call append(line('$')-1, printf('    Other: %.2f%%', (l:files_n-l:counted)/l:files_n))
    endif
    " exclude rate
    "
    exec 'resize 10'
    exec ':1'

    call s:dret("CsMgmtFurtherInfo")
endf


func! CsMgmtOpenAllFile(line, pos)
    call s:dfunc("CsMgmtOpenAllFile")
    call s:decho(printf("args: %s, %s", a:line, a:pos))

    if s:cm_is_not_item_line(a:line) == 1
        " echo 'it is a unexpect line'
        call s:dret("CsMgmtOpenAllFile")
        return
    endif

    if s:cm_str_strip(a:line)[0] == s:cm_db_nonexist_token
        call s:cm_echohl1("You have not built its cross-reference.")
        call s:dret("CsMgmtOpenAllFile")
        return
    endif

    " look for key of its full name.
    let l:ref_level = s:cm_item_level_get(a:line)
    let l:parent_list = s:cm_parent_list_on_buf_get(l:ref_level, a:line, a:pos)
    let l:ref_name = s:cm_item_name_get(a:line)
    let l:all_file_list = []
    let l:parent = (len(l:parent_list) == 0) ?
                \   (''):
                \   (join(l:parent_list, '_'))

    let l:ref_full_name = (l:parent == '') ?
                \   (l:ref_name):
                \   (l:parent.'_'.l:ref_name)

    let l:abs_path = g:CsMgmtDbHome . l:ref_full_name . ".files"
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

    call s:dret(printf("CsMgmtOpenAllFile"))
endf

func! CsMgmtAdd(...) abort
    " a:000[0]: protocol
    " a:000[1]: file path
    " a:000[2]: ref_name <- it is not necessary.
    " a:000[3]: group <- it is not necessary.
    if len(a:000) > 4 || len(a:000) < 2
        call s:cm_echo( ":Csmgmtadd <[dir|file]> <src path> [[<alias>] <group>]" )
        call s:cm_echo( "  example:" )
        call s:cm_echo( "    :Csmgmtadd dir /foo/bar" )
        call s:cm_echo( "    :Csmgmtadd dir /foo/bar foobar" )
        call s:cm_echo( "    :Csmgmtadd dir /foo/bar foobar foo/bar" )
        call s:cm_echo( "    :Csmgmtadd file /foo/bar.tar.gz" )
        call s:cm_echo( "    :Csmgmtadd file /foo/bar.tar.gz foobar" )
        call s:cm_echo( "    :Csmgmtadd file /foo/bar.tar.gz foobar foo/bar" )
        call s:cm_echo( " " )
        return
    endif

    if !exists('g:cm_view')
        if s:cm_db_chk() == -1
            return
        endif
    endif

    if !isdirectory(g:CsMgmtSrcDepot)
        call mkdir(g:CsMgmtSrcDepot)
    endif

    " TODO: json - add lot of entry at one time.
    let l:prot_type = ['file', 'dir']
    let l:argc = len(a:000)
    let l:type = a:000[0]
    let l:path = a:000[1]
    let l:ref_name = ''
    let l:grp_parent = []
    let l:grp_new = []
    let l:cwd = getcwd()

    if l:argc > 2
        let l:ref_name = a:000[2]

        " check reserved words in filename
        if len(s:cm_filename_resv_words(l:ref_name))
            call s:cm_echohl1("Don't contain reserved words in ref_name.")
            return
        endif

        if l:argc == 4
            let l:grouping = s:cm_grp_chk_n_split(a:000[3])
            " if correct, it should return length 2.
            if len(l:grouping) == 1
                return
            endif

            let l:grp_new = l:grouping[0]
            let l:grp_parent = l:grouping[1]
        endif

        if !len(l:grp_new)
            "check key whenter existed in json befor
            let l:db = s:cm_db_get()

            " roll into its parent
            for k in l:grp_parent
                let l:db = l:db[k]
            endfor

            if has_key(l:db, l:ref_name)
                call s:cm_echohl1( l:ref_name . " has existed in "
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
        call s:cm_echohl1( 'Not support '. l:type .' protocol type' )
        return
    endif

    " symbol replacement
    if l:path[0] == '~'
        let l:path = $HOME . l:path[1:]
    elseif l:path[0:2] == '../' " ../foo/bar
        let l:path = l:cwd . '/' . l:path
    elseif l:path[0:1] == './' " ./foo/bar
        let l:path = l:cwd . l:path[1:]
    elseif l:path[0:3] == '$PWD' " $PWD/foo/bar
        let l:path = l:cwd . l:path[4:]
    elseif l:path[0] == '/' " /foo/bar
        let l:path = l:path
    else
        let l:path = l:cwd . '/' . l:path " foor/bar
    endif

    let l:path = simplify(l:path)

    let l:source_path = eval(l:type_func . '("' . l:path . '")')

    if l:source_path == ''
        call s:cm_echoerr( 'program error ??' )
        call s:cm_echoerr( 'type_func: ' . l:type_funca )
        call s:cm_echoerr( 'path: ' . l:path )
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
    let l:db = s:cm_db_get()
    while len(l:grp_parent)
        let l:db = l:db[l:grp_parent[0]]
        call remove(l:grp_parent, 0)
    endwhile

    if len(l:add_dict)
        let l:db[keys(l:add_dict)[0]] = values(l:add_dict)[0]
    els
        let l:db[l:ref_name] = [l:source_path]
    endif

    call s:cm_json_to_file()
    call s:cm_mgmt_buf_refresh(line("."))
endf

func! CsMgmt() abort
    if s:cm_db_chk() == -1
        return
    endif

    call s:cm_mgmt_buf_show(s:cm_mgmt_buf_view(s:cm_db_get()))
endf

func! s:cm_mgmt_buf_theme()
    hi cm_ref_grp_name ctermfg=cyan guifg=cyan
    call matchadd('cm_ref_grp_name', '^\s\{}\([0-9a-zA-Z\-._~]*\):')

    hi cm_ref_name ctermfg=yellow guifg=yellow
    call matchadd('cm_ref_name', '^\s\{}[OX]\s\(.*\)$')

    hi cm_timestamp ctermfg=darkgreen guifg=darkgreen
    call matchadd('cm_timestamp', '\d\{2}/\d\{2}/\d\{2}\s\d\{2}\:\d\{2}')

    hi cm_ref_attach ctermfg=darkblue guifg=darkblue
    call matchadd('cm_ref_attach', '\ Attach$')

    hi cm_ref_item_status_exist ctermfg=blue guifg=blue
    call matchadd('cm_ref_item_status_exist', '^\s\{}' . s:cm_db_exist_token, 99)

    hi cm_ref_item_status_nonexist ctermfg=red guifg=red
    call matchadd('cm_ref_item_status_nonexist', '^\s\{}' . s:cm_db_nonexist_token, 99)
endf

func! s:cm_mgmt_buf_view(json)
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
            call s:cm_grp_walk(0, l:deep_collect, a:json[k], k)
            for d in l:deep_collect
                call add(l:view_data, d)
            endfor
        endif
    endfor

    return l:view_data
endf

func! s:cm_mgmt_buf_refresh(line)
    if exists('g:cm_view') && buflisted(g:cm_view)
        " if it isn't on cm_view, closing buf then reopen.
        if g:cm_view != bufnr('%')
            call s:cm_mgmt_buf_show(s:cm_mgmt_buf_view(s:cm_db_get()))
            wincmd l
        else
            call s:cm_buf_write_mode_set()

            " delete all line in buffer
            let l:header_size = len(s:cs_mgmt_buf_hdr) + 2
            exec "silent" . l:header_size. ",$d"

            " update buffer
            for i in s:cm_mgmt_buf_view(s:cm_db_get())
                if s:cm_item_level_get(i) == 0
                    if line('$') != len(s:cs_mgmt_buf_hdr) + 1
                        call append(line('$'), '')
                    endif
                endif
                call append(line('$'), i)
            endfor

            call s:cm_buf_readonly_mode_set()
        endif

        if a:line
            exec ':' . a:line
        endif
    endif
endf

let s:cs_mgmt_buf_hdr = ['" +-------------- Key Map ---------------+',
                       \ '" | Press a: to aetach                   |',
                       \ '" | Press d: to detach                   |',
                       \ '" | Press b: to build db                 |',
                       \ '" | Press r: to rebuild db               |',
                       \ '" | Press e: edit this configuration     |',
                       \ '" | Press i: display further infomation  |',
                       \ '" |--------------------------------------|',
                       \ '" | Press dd: delete a item from menu    |',
                       \ '" | Press q: quit                        |',
                       \ '" |--------------------------------------|',
                       \ '" | Press oo: open all files at one time |',
                       \ '" +--------------------------------------+']

func! s:cm_mgmt_buf_show(content)
    if exists('g:cm_view') && bufloaded(g:cm_view)
        exec g:cm_view.'bd!'
    endif

    let l:pwd = getcwd()
    exec 'silent pedit ' . tempname()

    wincmd P | wincmd H

    let g:cm_view = bufnr('%')
    " TODO: refactory
    " call cm_mgmt_buf_refresh(a:content)
    call append(0, s:cs_mgmt_buf_hdr)

    for i in a:content
        call s:decho(string(s:cm_item_level_get(i)).": ".i)
        if s:cm_item_level_get(i) == 0
            if line('$') != len(s:cs_mgmt_buf_hdr) + 1
                call append(line('$'), '')
            endif
            " call s:decho(i)
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

    call s:cm_mgmt_buf_theme()

    nnoremap <silent> <buffer> q :call CsMgmtQuit(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> a :call CsMgmtAttach(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> d :call CsMgmtDetach(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> b :call CsMgmtBuild(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> r :call CsMgmtRebuild(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> e :call CsMgmtEdit(printf("%s", getline('.')), line('.'))<CR>
    nnoremap <silent> <buffer> i :call CsMgmtFurtherInfo(printf("%s", getline('.')), line('.'))<CR>

    " for edit
    " deleting a db entry, but don't delete real file.
    nnoremap <silent> <buffer> dd :call CsMgmtDelete(printf("%s", getline('.')), line('.'))<CR>

    " open all file at one time
    nnoremap <silent> <buffer> oo :call CsMgmtOpenAllFile(printf("%s", getline('.')), line('.'))<CR>

    exec ':'.(len(s:cs_mgmt_buf_hdr) + 2)
    redraw!

    " Its working directory will be changed to tmpename directory, rolling back
    exec 'cd ' . l:pwd
endf

let s:CsMgmtDb = s:cm_db_get_from_file()
let s:json2file_list = []

augroup CsMgmtEditAutoCmd
    " update to .cs-mgmt.json
    " TODO: verify the exclude must be a sub-folder of including
    au BufWritePost *.cs-mgmt-edit
            \   let db = s:cm_db_get()
            \|  let item = db
            \|  let buf = eval(join(getline('^', '$')))
            \|  let plist = s:cm_rvs_able_to_list(bufname('%'))[1:]
            \|  if len(plist)
            \|      let plist[-1] = plist[-1][:-(len(".cs-mgmt-edit") + 1)]
            \|  endif
            \|  let s:json2file_list = []
            \|  let indent_level = 1
            \|  call s:decho("plist: " . string(plist))
            \|  call s:decho("buf: " . string(buf))
            \|  call s:decho("buf.keys: " . string(keys(buf)))
            \|  for p in plist | let item = item[p] | endfor
            \|  for k in keys(buf) | let item[k] = buf[k] |  endfor
            \|  call add(s:json2file_list, '{')
            \|  call s:cm_json_dip(indent_level, db)
            \|  call add(s:json2file_list, '}')
            \|  call s:decho(s:json2file_list)
            \|  call writefile(s:json2file_list, g:CsMgmtDbFile)
            \|  call s:cm_mgmt_buf_refresh(line("."))
augroup END

command! -nargs=* -complete=dir Csmgmtadd call CsMgmtAdd(<f-args>)
command! CsMgmt call CsMgmt()
map <Leader>cs :call CsMgmt()<CR>

