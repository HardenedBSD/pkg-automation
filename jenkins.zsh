#!/usr/local/bin/zsh

config=""
repo=""

function get_topdir() {
    self=${1}
    echo $(realpath $(dirname ${self}))
}

function main() {
    TOPDIR=$(get_topdir ${1})
    shift

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
                    exit 1
                fi
                if ! sync_repo_metadata; then
                    echo "[-] Could not sync repo metadata." >&2
                    exit 1
                fi
                promote_mirrors
                exit 0
                ;;
        esac
    done

    if [ -z ${config} ]; then
        echo "[-] Please specify a config with the -c option." >&2
        exit 1
    fi

    if [ -z ${repo} ]; then
        echo "[-] Please specify a repo with the -r option." >&2
        exit 1
    fi

    if [ ! -f ${config} ]; then
        echo "[-] Config ${config} not found." >&2
        exit 1
    fi

    if [ ! -f ${repo} ]; then
        echo "[-] Repo ${repo} not found." >&2
        exit 1
    fi

    if ! cache_mirror_data; then
        echo "[-] Could not cache mirror data." >&2
        exit 1
    fi
    if ! clean_mirrors; then
        echo "[-] Could not clean the mirrors." >&2
        exit 1
    fi
    if ! update_base_source; then
        echo "[-] Could not update the base source code." >&2
        exit 1
    fi
    if ! update_ports; then
        echo "[-] Could not update the ports tree." >&2
        exit 1
    fi
    if ! build_world; then
        echo "[-] Could not build world." >&2
        exit 1
    fi
    if ! rebuild_jail; then
        echo "[-] Could not rebuild the jail." >&2
        exit 1
    fi
    if ! build_packages; then
        echo "[-] Could not build packages." >&2
        exit 1
    fi
    if ! sign_packages; then
        echo "[-] Could not sign packages." >&2
        exit 1
    fi
    sync_repo_metadata
    promote_mirrors
}

main ${0} $*
exit ${?}
