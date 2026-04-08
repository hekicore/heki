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

# 解析参数
INSTALL_BETA=false
INSTALL_VERSION=""
for arg in "$@"; do
    case "${arg}" in
        --beta|-beta|beta)
            INSTALL_BETA=true
            ;;
        *)
            # 非 beta 参数视为版本号
            if [ -z "${INSTALL_VERSION}" ] && echo "${arg}" | grep -qE '^[0-9]'; then
                INSTALL_VERSION="${arg}"
            fi
            ;;
    esac
done

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
        apt-get update -o Acquire::ForceIPv4=true
        apt-get install -o Acquire::ForceIPv4=true -y wget curl tar cron socat tzdata || {
            echo -e "${yellow}部分依赖安装失败，尝试跳过 socat（仅影响证书自动申请）${plain}"
            apt-get install -o Acquire::ForceIPv4=true -y wget curl tar cron tzdata
        }
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
    # acme.sh 用于自动申请 TLS 证书，非必须组件
    # 如果不需要自动证书申请（手动指定 cert_file/key_file），可跳过
    curl -s https://get.acme.sh | sh 2>/dev/null
    if [[ -f /root/.acme.sh/acme.sh ]]; then
        /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt 2>/dev/null
    else
        echo -e "${yellow}acme.sh 安装失败（网络问题），不影响 heki 运行，仅影响自动证书申请${plain}"
        echo -e "${yellow}如需自动证书，请稍后手动安装: curl https://get.acme.sh | sh${plain}"
    fi
}

install_mgmt_script() {
    local tmp_script
    tmp_script=$(mktemp)
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/contents/heki.sh"

    if ! curl -fsSL -H "Accept: application/vnd.github.v3.raw" -o "${tmp_script}" "${api_url}"; then
        if ! curl -fsSL -o "${tmp_script}" "${MGMT_SCRIPT_URL}"; then
            rm -f "${tmp_script}"
            echo -e "${red}下载 heki 管理脚本失败${plain}"
            exit 1
        fi
    fi

    if [[ ! -s "${tmp_script}" ]]; then
        rm -f "${tmp_script}"
        echo -e "${red}下载 heki 管理脚本失败：文件为空${plain}"
        exit 1
    fi

    if ! head -1 "${tmp_script}" | grep -q "^#!/bin/bash"; then
        rm -f "${tmp_script}"
        echo -e "${red}下载 heki 管理脚本失败：脚本头无效${plain}"
        exit 1
    fi

    if ! bash -n "${tmp_script}" 2>/tmp/heki-script-check.err; then
        echo -e "${red}下载 heki 管理脚本失败：语法校验未通过${plain}"
        cat /tmp/heki-script-check.err
        rm -f /tmp/heki-script-check.err "${tmp_script}"
        exit 1
    fi

    rm -f /tmp/heki-script-check.err
    install -m 755 "${tmp_script}" /usr/bin/heki
    rm -f "${tmp_script}"
}

download_release_tarball() {
    local version="$1"
    local out_file="$2"
    local candidates=()

    if [[ -z "${version}" || -z "${out_file}" ]]; then
        return 1
    fi

    candidates+=("https://github.com/${GITHUB_REPO}/releases/download/${version}/heki-linux-${arch}.tar.gz")
    if [[ ! "${version}" =~ ^v ]]; then
        candidates+=("https://github.com/${GITHUB_REPO}/releases/download/v${version}/heki-linux-${arch}.tar.gz")
    fi

    local url
    for url in "${candidates[@]}"; do
        echo -e "下载地址: ${url}"
        if wget -N --no-check-certificate -O "${out_file}" "${url}"; then
            return 0
        fi
    done

    return 1
}

install_heki() {
    cd /usr/local/
    if [[ -e /usr/local/heki/ ]]; then
        rm /usr/local/heki/ -rf
    fi

    if ${INSTALL_BETA}; then
        # 测试版: 从最新的 pre-release 下载
        echo -e "${yellow}安装 heki 测试版 (beta)${plain}"
        # 用 GitHub API 获取所有 release，找到第一个 prerelease 的 tag_name
        # API 返回按时间倒序，逐个 release 对象扫描，找到第一个 prerelease=true 的
        all_releases=$(curl -sL "https://api.github.com/repos/${GITHUB_REPO}/releases")
        beta_tag=""
        # 简单状态机：遇到 tag_name 记住，遇到 prerelease: true 就确认
        current_tag=""
        while IFS= read -r line; do
            if echo "${line}" | grep -q '"tag_name"'; then
                current_tag=$(echo "${line}" | sed 's/.*"tag_name": "//;s/".*//')
            fi
            if echo "${line}" | grep -q '"prerelease": true'; then
                if [[ -n "${current_tag}" ]]; then
                    beta_tag="${current_tag}"
                    break
                fi
            fi
            # 遇到下一个 release 对象的 tag_name 前，如果 prerelease 是 false 就重置
            if echo "${line}" | grep -q '"prerelease": false'; then
                current_tag=""
            fi
        done <<< "${all_releases}"
        if [[ -z "${beta_tag}" ]]; then
            echo -e "${red}未找到 beta 版本，请确认是否已发布测试版${plain}"
            exit 1
        fi
        echo -e "最新测试版: ${beta_tag}"
        if ! download_release_tarball "${beta_tag}" "/usr/local/heki.tar.gz"; then
            echo -e "${red}下载 heki ${beta_tag} 失败${plain}"
            exit 1
        fi
    elif [[ -n "${INSTALL_VERSION}" ]]; then
        last_version="${INSTALL_VERSION}"
        echo -e "开始安装 heki v${last_version}"
        if ! download_release_tarball "${last_version}" "/usr/local/heki.tar.gz"; then
            echo -e "${red}下载 heki v${last_version} 失败，请确保此版本存在${plain}"
            exit 1
        fi
    else
        echo -e "开始安装 heki 最新正式版"
        wget -N --no-check-certificate -O /usr/local/heki.tar.gz https://github.com/${GITHUB_REPO}/releases/latest/download/heki-linux-${arch}.tar.gz
        if [[ $? -ne 0 ]]; then
            echo -e "${red}下载 heki 失败，请确保你的服务器能够下载 Github 的文件${plain}"
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
    install_mgmt_script
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
    echo "  update             更新到最新正式版"
    echo "  update x.x.x      更新到指定版本"
    echo "  update beta        更新到最新测试版"
    echo "  install            重新安装"
    echo "  uninstall          卸载"
    echo "  setup              交互式配置引导"
    echo "  version            查看版本"
    echo ""
    echo "配置示例:"
    echo "  heki config type=sspanel-uim server_type=v2ray panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=xboard server_type=ss panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=v2board server_type=trojan panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=ppanel server_type=vless panel_url=https://xxx panel_key=xxx node_id=1"
    echo ""
    echo "面板类型: sspanel-uim, xboard, v2board, xiaov2board, ppanel"
    echo "后端类型(server_type 必填): v2ray(vmess), vless, ss, ssr, trojan, hysteria, tuic, anytls, naive, mieru"
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
install_heki

# 首次安装后自动运行配置引导
# 检查配置文件是否包含必要的配置项（panel_url）
if [[ -f /etc/heki/heki.conf ]] && grep -q "panel_url=https://your-panel.com" /etc/heki/heki.conf 2>/dev/null; then
    echo -e ""
    echo -e "${green}首次安装，启动配置引导...${plain}"
    echo -e "按 ${yellow}Ctrl+C${plain} 可跳过配置引导"
    sleep 2
    heki setup
elif [[ ! -f /etc/heki/heki.conf ]]; then
    echo -e ""
    echo -e "${green}首次安装，启动配置引导...${plain}"
    echo -e "按 ${yellow}Ctrl+C${plain} 可跳过配置引导"
    sleep 2
    heki setup
else
    echo -e ""
    echo -e "${green}安装完成！${plain}"
    echo -e "运行 ${green}heki setup${plain} 进行配置引导"
    echo -e "运行 ${green}heki${plain} 查看管理菜单"
fi
