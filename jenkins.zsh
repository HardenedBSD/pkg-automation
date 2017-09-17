#!/usr/local/bin/zsh

config=""
repo=""

function get_topdir() {
    self=${1}
    echo $(realpath $(dirname ${self}))
}

function main() {
    TOPDIR=$(get_topdir ${0})
    shift

    source ${TOPDIR}/base.zsh
    source ${TOPDIR}/packages.zsh
    source ${TOPDIR}/mirror.zsh

    while getopts 'c:r:' o; do
        case "${o}" in
            c)
                config="${OPTARG}"
                ;;
            r)
                repo="${OPTARG}"
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

    cache_mirror_data || exit 1
    clean_mirrors || exit 1
    update_base_source || exit 1
    update_ports || exit 1
    build_world || exit 1
    rebuild_jail || exit 1
    build_packages || exit 1
    sign_packages || exit 1
    sync_repo_metadata
    promote_mirrors
}

main ${0} $*
exit ${?}
