#!/bin/bash
if [ -z "${BASH_SOURCE}" ]; then
    this=${PWD}
else
    rpath="$(readlink ${BASH_SOURCE})"
    if [ -z "$rpath" ]; then
        rpath=${BASH_SOURCE}
    elif echo "$rpath" | grep -q '^/'; then
        # absolute path
        echo
    else
        # relative path
        rpath="$(dirname ${BASH_SOURCE})/$rpath"
    fi
    this="$(cd $(dirname $rpath) && pwd)"
fi

if [ -r ${SHELLRC_ROOT}/shellrc.d/shelllib ];then
    source ${SHELLRC_ROOT}/shellrc.d/shelllib
elif [ -r /tmp/shelllib ];then
    source /tmp/shelllib
else
    # download shelllib then source
    shelllibURL=https://gitee.com/sunliang711/init2/raw/master/shell/shellrc.d/shelllib
    (cd /tmp && curl -s -LO ${shelllibURL})
    if [ -r /tmp/shelllib ];then
        source /tmp/shelllib
    fi
fi


###############################################################################
# write your code below (just define function[s])
# function is hidden when begin with '_'
download(){
    local dest=${dest:-${PWD}}
    echo "download clash to ${dest}.."
    linkLinuxAmd64="https://release.dreamacro.workers.dev/latest/clash-linux-amd64-latest.gz"
    linkLinuxArm="https://release.dreamacro.workers.dev/latest/clash-linux-armv8-latest.gz"
    linkDarwin="https://release.dreamacro.workers.dev/latest/clash-darwin-amd64-latest.gz"
    local platform="$(uname)-$(uname -m)"
    case ${platform} in
        Linux-x86_64)
            link=${linkLinuxAmd64}
            ;;
        Linux-aarch64)
            link=${linkLinuxArm}
            ;;
        Darwin-x86_64)
            link=${linkLinuxDarwin}
            ;;
        *)
            ::
    esac

    gzFile=${link##*/}
    clashBin=${gzFile%.gz}
    (
        set -x
        cd /tmp && curl -LO ${link} || { echo "download clash failed!"; return 1; }
        gunzip ${gzFile} || { echo "unzip failed!"; return 1; }
        mv ${clashBin} ${dest}/clash
        chmod +x ${dest}/clash
    )

}

# write your code above
###############################################################################

em(){
    $ed $0
}

function _help(){
    cd "${this}"
    cat<<EOF2
Usage: $(basename $0) ${bold}CMD${reset}

${bold}CMD${reset}:
EOF2
    perl -lne 'print "\t$2" if /^\s*(function)?\s*(\S+)\s*\(\)\s*\{$/' $(basename ${BASH_SOURCE}) | perl -lne "print if /^\t[^_]/"
}

case "$1" in
     ""|-h|--help|help)
        _help
        ;;
    *)
        "$@"
esac
