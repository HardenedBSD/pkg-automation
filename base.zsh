function update_base_source() {
    srcdir=$(jq -r '.source.path' ${repo})
    (
        cd ${srcdir}
        git pull
        exit ${?}
    )

    return ${?}
}

function build_world() {
    srcdir=$(jq -r '.source.path' ${repo})
    srcconf=$(jq -r '.source.conf' ${repo})
    makeconf=$(jq -r '.make_conf' ${repo})
    baseclean=$(jq -r '.build.clean' ${repo})

    if [ "${srcconf}" != "null" ]; then
        cp ${srcconf} /etc/src.conf
    elif [ -f /etc/src.conf ]; then
        rm -f /etc/src.conf
    fi

    if [ "${makeconf}" != "null" ]; then
        cp ${makeconf} /etc/make.conf
    elif [ -f /etc/make.conf ]; then
        rm -f /etc/make.conf
    fi

    if [ "${baseclean}" != "null" ]; then
        if [ "${baseclean}" = "false" ]; then
            baseclean="-DNO_CLEAN"
        else
            baseclean=""
        fi
    else
        baseclean=""
    fi

    (
        cd ${srcdir}
        make \
            -j$(sysctl -n hw.ncpu) \
            -s \
            ${baseclean} \
            buildworld
        exit ${?}
    )

    return ${?}
}

function rebuild_jail() {
    local res

    srcdir=$(jq -r '.source.path' ${repo})
    name=$(jq -r '.name' ${repo})
    repover=$(jq -r '.version' ${repo})
    srcconf=$(jq -r '.source.conf' ${repo})
    makeconf=$(jq -r '.make_conf' ${repo})
    ports=$(jq -r .'ports' ${config})

    src="src=${srcdir}"
    url=$(jq -r '.urlbase' ${config})
    if [ "${url}" != "null" ]; then
        url="${url}$(jq -r '.urlsubdir' ${repo})"
        src="url=${url}"
    fi

    if [ "${srcconf}" = "null" ]; then
        srcconf="/dev/null"
    fi

    if [ "${makeconf}" = "null" ]; then
        makeconf="/dev/null"
    fi

    if [ "${ports}" = "null" ]; then
        ports="local"
    fi

    if poudriere jail -l -n | grep -qFw ${name}; then
        yes | poudriere jail -j ${name} -d || return ${?}
    fi

    poudriere jail -c -j ${name} \
        -m ${src} \
        -p ${ports} \
        -v ${repover}

    return ${?}
}
