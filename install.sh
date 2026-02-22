#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="amd64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64"
else
    arch="amd64"
    echo -e "${red}检测架构失败，使用默认架构: ${arch}${plain}"
fi

echo "架构: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# ============ 配置区 ============
GITHUB_REPO="hekicore/heki"
MGMT_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/master/heki.sh"
# ================================

function is_cmd_exist() {
    local cmd="$1"
    if [ -z "$cmd" ]; then
        return 1
    fi

    which "$cmd" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        return 0
    fi

    return 2
}

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl tar crontabs socat tzdata -y
    else
        apt install wget curl tar cron socat tzdata -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/heki.service ]]; then
        return 2
    fi
    temp=$(systemctl status heki | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_acme() {
    curl https://get.acme.sh | sh
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
}

install_heki() {
    cd /usr/local/
    if [[ -e /usr/local/heki/ ]]; then
        rm /usr/local/heki/ -rf
    fi

    if  [ $# == 0 ] ;then
        echo -e "开始安装 heki 最新版"
        wget -N --no-check-certificate -O /usr/local/heki.tar.gz https://github.com/${GITHUB_REPO}/releases/latest/download/heki-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 heki 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/${GITHUB_REPO}/releases/download/${last_version}/heki-linux-${arch}.tar.gz"
        echo -e "开始安装 heki v$1"
        wget -N --no-check-certificate -O /usr/local/heki.tar.gz ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 heki v$1 失败，请确保此版本存在${plain}"
            exit 1
        fi
    fi

    tar zxvf heki.tar.gz
    rm heki.tar.gz -f
    cd heki
    chmod +x heki
    last_version="$(./heki -v)"
    mkdir /etc/heki/ -p
    rm /etc/systemd/system/heki.service -f
    rm /etc/systemd/system/heki@.service -f
    cp -f heki.service /etc/systemd/system/
    cp -f heki@.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl stop heki
    systemctl enable heki
    echo -e "${green}heki v${last_version}${plain} 安装完成，已设置开机自启"
    if [[ ! -f /etc/heki/heki.conf ]]; then
        cp heki.conf /etc/heki/
        echo -e ""
        echo -e "全新安装，请先配置必要的内容"
    else
        systemctl start heki
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}heki 重启成功${plain}"
        else
            echo -e "${red}heki 可能启动失败，请稍后使用 heki log 查看日志信息${plain}"
        fi
    fi

    if [[ ! -f /etc/heki/blockList ]]; then
        cp blockList /etc/heki/
    fi
    if [[ ! -f /etc/heki/whiteList ]]; then
        cp whiteList /etc/heki/
    fi
    if [[ ! -f /etc/heki/dns.yml ]]; then
        cp dns.yml /etc/heki/
    fi
    if [[ ! -f /etc/heki/routes.toml ]]; then
        cp routes.toml /etc/heki/
    fi
    curl -o /usr/bin/heki -sL -H "Accept: application/vnd.github.v3.raw" "https://api.github.com/repos/${GITHUB_REPO}/contents/heki.sh"
    chmod +x /usr/bin/heki
    echo -e ""
    echo "用法: heki [命令]"
    echo ""
    echo "命令:"
    echo "  start              启动 Heki"
    echo "  stop               停止 Heki"
    echo "  restart            重启 Heki"
    echo "  enable             设置开机自启"
    echo "  disable            取消开机自启"
    echo "  log                查看日志"
    echo "  status             查看状态"
    echo "  config             查看配置"
    echo "  config k=v k2=v2   快速修改配置项"
    echo "  node list          查看当前节点"
    echo "  node add <ID>      添加节点"
    echo "  node del <ID>      删除节点"
    echo "  modify             交互式修改配置"
    echo "  cert               证书管理"
    echo "  reality            Reality 密钥管理"
    echo "  reality gen        自动生成 x25519 密钥对"
    echo "  reality set        手动输入 Reality 私钥"
    echo "  x25519             生成 x25519 密钥对"
    echo "  update             更新到最新版"
    echo "  update x.x.x      更新到指定版本"
    echo "  install            重新安装"
    echo "  uninstall          卸载"
    echo "  setup              交互式配置引导"
    echo "  version            查看版本"
    echo ""
    echo "配置示例:"
    echo "  heki config type=sspanel-uim panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=xboard panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=v2board panel_url=https://xxx panel_key=xxx node_id=1 server_type=v2ray"
    echo ""
    echo "面板类型: sspanel-uim, xboard, v2board, xiaov2board"
    echo "后端类型: v2ray(vmess), vless, ss, ssr, trojan, hysteria, anytls"
    echo ""
    echo "不带参数运行将显示交互式管理菜单"
}

is_cmd_exist "systemctl"
if [[ $? != 0 ]]; then
    echo "systemctl 命令不存在，请使用较新版本的系统，例如 Ubuntu 18+、Debian 9+"
    exit 1
fi

echo -e "${green}开始安装${plain}"
install_base
install_acme
install_heki $1
