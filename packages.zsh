function install_symlinks() {
    rm -f /tmp/pkgconfig.conf
    rm -f /tmp/pkgrepo.conf
    rm -f /tmp/pkgscripts

    ln -s $(realpath ${config}) /tmp/pkgconfig.conf
    ln -s $(realpath ${repo}) /tmp/pkgrepo.conf
    ln -s ${TOPDIR} /tmp/pkgscripts
}

function update_ports() {
    (
        ports=$(jq -r '.ports' ${config})
        if [ "${ports}" = "null" ]; then
            ports="local"
        fi
        portsdir=$(poudriere ports -ql | grep ${ports} | awk '{print $3;}')
        cd ${portsdir}
        git pull
        exit ${?}
    )

    return ${?}
}

function build_packages() {
    name=$(jq -r '.name' ${repo})
    ports=$(jq -r '.ports' ${config})
    njobs=$(jq -r '.jobs' ${config})
    starttime=$(date '+%s')

    if [ "${ports}" = "null" ]; then
        ports="local"
    fi

    if [ "${njobs}" = "null" ]; then
        njobs=""
    else
        njobs="-J ${njobs}"
    fi

    install_symlinks

    poudriere bulk \
        -j ${name} \
        -p ${ports} \
        ${njobs} \
        -ca

    endtime=$(date '+%s')
    deltatime=$((${endtime} - ${starttime}))
    if [ ${deltatime} -lt 86400 ]; then
        return 1
    fi

    return 0
}

function sign_packages() {
    name=$(jq -r '.name' ${repo})
    datadir=$(jq -r '.datadir' ${config})
    signcmd=$(jq -r '.signcmd' ${config})

    (
        cd ${datadir}/${name}-local/Latest
        sha256 -q pkg.txz | /src/scripts/pkgsign.sh > pkg.txz.sig

        cd ..
        pkg repo . signing_command: /src/scripts/pkgsign.sh
        exit ${?}
    )

    return ${?}
}

function syncable() {
    val=$(jq -r '.sync.enabled' /tmp/pkgrepo.conf)
    if [ "${val}" = "true" ]; then
        return 0
    fi

    return 1
}
