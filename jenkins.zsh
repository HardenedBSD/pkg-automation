#!/usr/local/bin/zsh

config=""
repo=""

function get_topdir() {
    self=${1}
    echo $(realpath $(dirname ${self}))
}

function lockbuild() {
    touch /tmp/pkglock
}

function islocked() {
    if [ -e /tmp/pkglock ]; then
        return 0
    fi

    return 1
}

function xclean() {
    rm -f /tmp/pkglock
    exit ${1}
}

function main() {
    local buildsrc

    TOPDIR=$(get_topdir ${1})
    shift

    if islocked; then
        cat <<EOF >&2
[-] Build may already be running. If this is an error, please remove
/tmp/pkglock
EOF
        exit 1
    fi

    lockbuild

    source ${TOPDIR}/base.zsh
    source ${TOPDIR}/packages.zsh
    source ${TOPDIR}/mirror.zsh

    while getopts 'sc:r:' o; do
        case "${o}" in
            c)
                config="${OPTARG}"
                ;;
            r)
                repo="${OPTARG}"
                ;;
            s)
                if ! sign_packages; then
                    echo "[-] Signing packages failed." >&2
                    xclean 1
                fi
                if ! sync_repo_metadata; then
                    echo "[-] Could not sync repo metadata." >&2
                    xclean 1
                fi
                promote_mirrors
                xclean 0
                ;;
        esac
    done

    buildsrc=1

    if [ -z ${config} ]; then
        echo "[-] Please specify a config with the -c option." >&2
        xclean 1
    fi

    if [ -z ${repo} ]; then
        echo "[-] Please specify a repo with the -r option." >&2
        xclean 1
    fi

    if [ ! -f ${config} ]; then
        echo "[-] Config ${config} not found." >&2
        xclean 1
    fi

    if [ ! -f ${repo} ]; then
        echo "[-] Repo ${repo} not found." >&2
        xclean 1
    fi

    url=$(jq -r '.urlbase' ${config})
    if [ "${url}" != "null" ]; then
        url=$(jq -r '.urlsubdir' ${repo})
        if [ "${url}" != "null" ]; then
            buildsrc=0
        fi
    fi

    if ! cache_mirror_data; then
        echo "[-] Could not cache mirror data." >&2
        xclean 1
    fi
    if ! clean_mirrors; then
        echo "[-] Could not clean the mirrors." >&2
        xclean 1
    fi
    if [ ${buildsrc} -gt 0 ]; then
        if ! update_base_source; then
            echo "[-] Could not update the base source code." >&2
            xclean 1
        fi
    fi
    if ! update_ports; then
        echo "[-] Could not update the ports tree." >&2
        xclean 1
    fi
    if [ ${buildsrc} -gt 0 ]; then
        if ! build_world; then
            echo "[-] Could not build world." >&2
            xclean 1
        fi
    fi
    if ! rebuild_jail; then
        echo "[-] Could not rebuild the jail." >&2
        xclean 1
    fi
    if ! build_packages; then
        echo "[-] Could not build packages." >&2
        xclean 1
    fi
    if ! sign_packages; then
        echo "[-] Could not sign packages." >&2
        xclean 1
    fi
    sync_repo_metadata
    promote_mirrors
}

main ${0} $*
xclean ${?}
