#!/bin/bash

DB_ROOT="${HOME}/.cscope_db/"

SRC_ARRAY=( \
    "/usr/include/ usr_include" \
    "/home/blue119/iLab/vte/sakura/ sakura" \
    )

for SRC in "${SRC_ARRAY[@]}"
do
    if [ ! -d ${DB_ROOT} ]; then
        echo "mkdir -p ${DB_ROOT}"
        mkdir -p ${DB_ROOT}
    fi

    src=`echo ${SRC} | sed 's/\s.*//'`
    alias_n=`echo ${SRC} | sed 's/\S*\s*//'`

    # src_re=`echo ${src} | sed 's/\//,/g'`
    src_re=${alias_n}
    # echo "${src} : ${alias_n}"

    cd ${DB_ROOT}
    if [ -f "${DB_ROOT}${src_re}.out" ]; then
        # prompt_msg="Update"
    # else
        # prompt_msg="Build"
        rm -rf ${DB_ROOT}${src_re}.*
        echo "Delete rm -rf "${DB_ROOT}${src_re}.*""
    fi

    find ${src} -type f -name '*.[chsS]' > ${src_re}.files
    cscope -b -q -k -i${src_re}.files -f${src_re}.out > /dev/null 2>&1
    echo "Build ${src_re} finish."
done

