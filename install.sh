#!/bin/bash
if [ -z "${BASH_SOURCE}" ]; then
    thisDir=${PWD}
else
    rpath="$(readlink ${BASH_SOURCE})"
    if [ -z "$rpath" ]; then
        rpath=${BASH_SOURCE}
    fi
    thisDir="$(cd $(dirname $rpath) && pwd)"
fi

export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

user="${SUDO_USER:-$(whoami)}"
home="$(eval echo ~$user)"

# export TERM=xterm-256color

# Use colors, but only if connected to a terminal, and that terminal
# supports them.
if which tput >/dev/null 2>&1; then
  ncolors=$(tput colors 2>/dev/null)
fi
if [ -t 1 ] && [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]; then
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    CYAN="$(tput setaf 5)"
    BOLD="$(tput bold)"
    NORMAL="$(tput sgr0)"
else
    RED=""
    GREEN=""
    YELLOW=""
    CYAN=""
    BLUE=""
    BOLD=""
    NORMAL=""
fi

_onlyLinux(){
    if [ $(uname) != "Linux" ];then
        _err "Only on linux"
        exit 1
    fi
}

_err(){
    echo "$*" >&2
}

_command_exists(){
    command -v "$@" > /dev/null 2>&1
}

rootID=0

_runAsRoot(){
    cmd="${*}"
    bash_c='bash -c'
    if [ "${EUID}" -ne "${rootID}" ];then
        if _command_exists sudo; then
            bash_c='sudo -E bash -c'
        elif _command_exists su; then
            bash_c='su -c'
        else
            cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
            exit 1
        fi
    fi
    # only output stderr
    (set -x; $bash_c "${cmd}")
}

function _insert_path(){
    if [ -z "$1" ];then
        return
    fi
    echo -e ${PATH//:/"\n"} | grep -c "^$1$" >/dev/null 2>&1 || export PATH=$1:$PATH
}

_run(){
    # only output stderr
    cmd="$*"
    (set -x; bash -c "${cmd}")
}

function _root(){
    if [ ${EUID} -ne ${rootID} ];then
        echo "Need run as root!"
        echo "Requires root privileges."
        exit 1
    fi
}

ed=vi
if _command_exists vim; then
    ed=vim
fi
if _command_exists nvim; then
    ed=nvim
fi
# use ENV: editor to override
if [ -n "${editor}" ];then
    ed=${editor}
fi
###############################################################################
# write your code below (just define function[s])
# function with 'function' is hidden when run help, without 'function' is show
###############################################################################
function _need(){
    if ! command -v $1 >/dev/null 2>&1;then
        echo "Need cmd: $1"
        exit 1
    fi
}

serviceFile=/etc/systemd/system/clash-gateway.service
clashUser=clash

install(){
    cd ${thisDir}
    _need curl
    _need unzip
    _need iptables-save
    _need iptables-restore
    case $(uname) in
        Linux)
            # clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/clash-linux.tar.bzip
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/20201227/clash-linux-amd64-2020.12.27.gz
            ;;
        Darwin)
            # clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/clash-darwin.tar.bzip
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/20201227/clash-darwin-amd64-2020.12.27.gz
            ;;
    esac

    case $(uname -m) in
        aarch64)
            # 树莓派
            clashURL=https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/20201227/clash-linux-armv8-2020.12.27.gz
            ;;
    esac

    tarFile=${clashURL##*/}
    name=${tarFile%.gz}

    #download
    cd /tmp
    if [ ! -e $tarFile ];then
        curl -LO $clashURL || { echo "download $tarFile failed!"; exit 1; }
    fi

    #unzip
    gunzip $tarFile
    chmod +x $name
    mv $name ${thisDir}/bin/clash

    echo "add user ${clashUser}.."
    sudo useradd -U ${clashUser}
    #sudo passwd ${clashUser}
    echo "chown clash to ${clashUser}.."
    sudo chown ${clashUser}:${clashUser} ${thisDir}/bin/clash

    _genServiceFile
    _genServiceFile2

    cd ${thisDir}

    _run "mkdir -p ${thisDir}/etc"

    if [ ! -e Country.mmdb ];then
        curl -LO https://source711.oss-cn-shanghai.aliyuncs.com/clash-premium/Country.mmdb
    fi
    ln -sf ${thisDir}/Country.mmdb ${thisDir}/etc/Country.mmdb || { echo "link Country.mmdb failed"; exit 1; }

    export PATH="${thisDir}/bin:${PATH}"
    echo "Add ${thisDir}/bin to PATH manually."
    echo "Run systemctl enable --now clash-gateway to auto boot on start"
    echo "Run systemctl enable --now clash-gateway-rule to auto boot on start"
}

clashGateway=${thisDir}/bin/clash-gateway
clashBinary=${thisDir}/bin/clash

_genServiceFile(){

    cat<<EOF >/tmp/clash-gateway.service
[Unit]
Description=clash gateway service
#After=network.target

[Service]
Type=simple
ExecStartPre=${clashGateway} _start_pre
ExecStart=${clashBinary} -d . -f config.yaml
ExecStartPost=${clashGateway} _start_post

ExecStopPost=${clashGateway} _stop_post

User=${clashUser}
Group=${clashUser}

WorkingDirectory=${thisDir}/etc

Restart=always
# AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
# CapabilityBoundingSet=CAP_NET_BIND_SERVICE
#Environment=
[Install]
WantedBy=multi-user.target
EOF
    sudo mv /tmp/clash-gateway.service /etc/systemd/system
    sudo systemctl daemon-reload

    #_enableSudoUser
    _setCap
}

_genServiceFile2(){
    cat<<EOF > /tmp/clash-gateway-rule.service
[Unit]
Description=clash gateway rule
#After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${clashGateway} setRule

ExecStopPost=${clashGateway} clearRule

User=root

#Restart=always
# AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
# CapabilityBoundingSet=CAP_NET_BIND_SERVICE
#Environment=
[Install]
WantedBy=multi-user.target
EOF

    sudo mv /tmp/clash-gateway-rule.service /etc/systemd/system
    sudo systemctl daemon-reload

}

_setCap(){
    sudo setcap 'cap_net_admin,cap_net_bind_service=+ep' ${thisDir}/bin/clash
}

_enableSudoUser(){
    mkdir /etc/sudoers.d
    echo "${clashUser} ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers.d/nopass
}

###############################################################################
# write your code above
###############################################################################
function _help(){
    cd ${thisDir}
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
