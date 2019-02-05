function cache_mirror_data() {
    pkgcache=$(jq -r '.cachedir' ${config})
    rm -rf ${pkgcache}

    sync=$(jq -r .sync.enabled ${repo})
    if [ "${sync}" = "false" ]; then
        return 0
    fi

    mkdir -p ${pkgcache}/mirrors

    nmirrors=$(jq -r '.mirrors | length' ${config})
    for ((i=0; i < ${nmirrors}; i++)); do
        if [ $(jq -r ".mirrors[${i}].enabled" ${config}) = "false" ]; then
            continue
        fi

        name=$(jq -r ".mirrors[${i}].name" ${config})
        reponame=$(jq -r ".name" ${repo})
        mkdir ${pkgcache}/mirrors/${name}

        mirrorconf="${pkgcache}/mirrors/${name}/config"
        jq -r ".mirrors[${i}]" ${config} > ${mirrorconf}

        syncuser=$(jq -r .user ${mirrorconf})
        synchost=$(jq -r .hostname ${mirrorconf})
        basedir=$(jq -r .basedir ${mirrorconf})

        symlink=$(ssh ${syncuser}@${synchost} readlink ${basedir}/${reponame})
        if [ ${#symlink} -eq 0 ]; then
            echo "[-] Could not connect to mirror ${name}. Disabling mirror."
            rm -rf ${pkgcache}/mirrors/${name}
            continue
        fi
        bump=$((${symlink##*sync} % 2 + 1))
        newsymlink="${basedir}/${reponame}-sync${bump}"
        ln -s ${newsymlink} ${pkgcache}/mirrors/${name}/syncdir
    done
}

function clean_mirrors() {
    cachedir=$(jq -r .cachedir ${config})
    for mirror in $(find ${cachedir}/mirrors -type d); do
        if [ ! -f ${mirror}/config ]; then
            continue
        fi

        syncuser=$(jq -r .user ${mirror}/config)
        synchost=$(jq -r .hostname ${mirror}/config)
        syncdir=$(readlink ${mirror}/syncdir)

        ssh ${syncuser}@${synchost} "rm -rf ${syncdir}/*"
        res=${?}
        if [ ${res} -gt 0 ]; then
            return ${res}
        fi

        ssh ${syncuser}@${synchost} "mkdir ${syncdir}/All ${syncdir}/Latest"
        res=${?}
        if [ ${res} -gt 0 ]; then
            return ${res}
        fi
    done

    return 0
}

function sync_repo_metadata() {
    cachedir=$(jq -r .cachedir ${config})
    datadir=$(jq -r .datadir ${config})
    reponame=$(jq -r .name ${repo})

    datadir="${datadir}/${reponame}-local/"

    for mirror in $(find ${cachedir}/mirrors -type d); do
        if [ ! -f ${mirror}/config ]; then
            continue
        fi

        syncdir=$(readlink ${mirror}/syncdir)
        syncuser=$(jq -r .user ${mirror}/config)
        synchost=$(jq -r .hostname ${mirror}/config)

        for ((i=0; i < 5; i++)); do
            scp ${datadir}/Latest/* ${syncuser}@${synchost}:${syncdir}/Latest/
            res=${?}
            if [ ${res} -gt 0 ]; then
                echo "[METADATA:Latest]" >> ${mirror}/syncfailed
                sleep 10
                continue
            fi

            scp ${datadir}/*.txz ${syncuser}@${synchost}:${syncdir}/
            res=${?}
            if [ ${res} -gt 0 ]; then
                echo "[METADATA:Metadata]" >> ${mirror}/syncfailed
                sleep 10
                continue
            fi

            break
        done

        if [ -f ${mirror}/syncfailed ]; then
            echo "[-] Some metadata failed to sync. Please check ${mirror}/syncfailed" >&2
        fi
    done

    return 0
}

function promote_mirrors() {
    cachedir=$(jq -r .cachedir ${config})
    datadir=$(jq -r .datadir ${config})
    reponame=$(jq -r .name ${repo})

    for mirror in $(find ${cachedir}/mirrors -type d); do
        if [ ! -f ${mirror}/config ]; then
            continue
        fi

        name=$(jq -r '.name' ${mirror}/config)

        if [ -f ${mirror}/syncfailed ]; then
            # 5 sync errors in a row means that artifact failed to sync entirely.
            # Less than 5 errors means the artifact did succeed in syncing.
            if sort ${mirror}/syncfailed | uniq -c | awk '{print $1;}' | grep -q 5; then
                echo "[-] Mirror ${name} failed to sync. Not promoting mirror." >&2
                continue
            fi
        fi

        syncdir=$(readlink ${mirror}/syncdir)
        basedir=$(jq -r .basedir ${mirror}/config)
        syncuser=$(jq -r .user ${mirror}/config)
        synchost=$(jq -r .hostname ${mirror}/config)

        ssh ${syncuser}@${synchost} \
            "rm ${basedir}/${reponame} && ln -s ${syncdir} ${basedir}/${reponame}"
    done
}

# This function is called from pkgbuild.zsh, which gets called via a
# Poudriere hook.
function sync_package() {
    pkgname="${1}"

    cachedir=$(jq -r .cachedir /tmp/pkgconfig.conf)
    datadir=$(jq -r .datadir /tmp/pkgconfig.conf)
    reponame=$(jq -r .name /tmp/pkgrepo.conf)

    datadir="${datadir}/${reponame}-local/.building/All"
    localpkg="${datadir}/${pkgname}.txz"
    localhash=$(sha256 -q ${localpkg} 2> /dev/null)
    if [ -z "${localhash}" ]; then
        echo "${pkgname}" >> ${mirror}/syncfailed
    fi

    for mirror in $(find ${cachedir}/mirrors -type d); do
        if [ ! -f ${mirror}/config ]; then
            continue
        fi

        syncdir=$(readlink ${mirror}/syncdir)
        syncuser=$(jq -r .user ${mirror}/config)
        synchost=$(jq -r .hostname ${mirror}/config)

        for ((i=0; i < 5; i++)); do
            scp ${localpkg} ${syncuser}@${synchost}:${syncdir}/All/

            remotehash=$(ssh ${syncuser}@${synchost} sha256 -q ${syncdir}/All/${pkgname}.txz 2> /dev/null)
            if [ "${localhash}" = "${remotehash}" ]; then
                break
            fi

            echo "${pkgname}" >> ${mirror}/syncfailed
            sleep 10
        done

        if [ -f ${mirror}/syncfailed ]; then
            echo "[-] Some packages failed to sync. Please check ${mirror}/syncfailed" >&2
        fi
    done

    return 0
}
