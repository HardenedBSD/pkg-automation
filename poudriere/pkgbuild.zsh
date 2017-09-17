#!/usr/local/bin/zsh

function get_topdir() {
    self="/tmp/pkgconfig.conf"
    echo $(dirname $(realpath ${self}))
}

function main() {
    TOPDIR=$(get_topdir)
    shift

    buildstatus="${1}"
    port="${2}"
    pkgname="${3}"

    if [ "${buildstatus}" != "success" ]; then
        exit 0
    fi

    source ${TOPDIR}/../mirror.zsh
    source ${TOPDIR}/../packages.zsh
    syncable && sync_package "${pkgname}"
}

main ${0} $*
exit 0
