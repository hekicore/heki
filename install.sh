#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
bold='\033[1m'
plain='\033[0m'

cur_dir=$(pwd)
SERVICE_MANAGER=""
SYSTEMD_SERVICE_DIR="/etc/systemd/system"
OPENRC_SERVICE_FILE="/etc/init.d/heki"
OPENRC_LOG_DIR="/var/log/heki"
OPENRC_PIDFILE="/run/heki.pid"
OPENRC_RUNLEVEL="default"

print_banner() {
    local title="$1"
    echo ""
    echo -e "${cyan}${bold}========================================${plain}"
    printf "${cyan}${bold}  %s${plain}\n" "${title}"
    echo -e "${cyan}${bold}========================================${plain}"
}

print_subsection() {
    local title="$1"
    echo ""
    echo -e "${cyan}----------------------------------------${plain}"
    printf "${cyan}  %s${plain}\n" "${title}"
    echo -e "${cyan}----------------------------------------${plain}"
}

print_compact_section() {
    local title="$1"
    echo ""
    echo -e "${cyan}========== ${title} ==========${plain}"
}

print_post_install_guide() {
    print_subsection "安装完成后的快速指引"

    print_compact_section "快速开始"
    echo "  heki                 打开交互式管理菜单"
    echo "  heki setup           重新进入配置引导"
    echo "  heki status          查看运行状态"
    echo "  heki log             查看日志"
    echo "  heki restart         重启服务"

    print_compact_section "节点与实例"
    echo "  heki node list       查看当前节点"
    echo "  heki node add <ID>   添加节点"
    echo "  heki instance list   查看实例列表"
    echo "  heki instance add <N> type=xboard server_type=vless panel_url=https://a.com panel_key=xxx node_id=1 heki_key=AAAA"
    echo "  heki instance setup <N> [k=v ...]   覆盖已有实例配置"

    print_compact_section "维护命令"
    echo "  heki update          更新到最新正式版"
    echo "  heki update beta     更新到最新测试版"
    echo "  heki version         查看版本"
    echo "  heki uninstall       卸载"

    print_compact_section "配置示例"
    echo "  heki config type=sspanel-uim server_type=v2ray panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=xboard server_type=vless panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=ppanel server_type=trojan panel_url=https://xxx panel_key=xxx node_id=1"

    print_compact_section "参数范围"
    echo "  面板类型: sspanel-uim, metron, xboard, v2board, xiaov2board, ppanel"
    echo "  协议类型: v2ray(vmess), vless, ss, ssr, trojan, hysteria, tuic, anytls, naive, mieru"

    print_compact_section "更多帮助"
    echo "  heki help            查看完整命令说明"
}

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif [[ -f /etc/alpine-release ]]; then
    release="alpine"
elif [[ -f /etc/os-release ]] && grep -Eq '^ID="?alpine"?$' /etc/os-release; then
    release="alpine"
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
elif cat /proc/version | grep -Eqi "alpine"; then
    release="alpine"
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

if [ "$(getconf LONG_BIT 2>/dev/null)" != '64' ] ; then
    echo "本软件不支持 32 位系统(x86)，请使用 64 位系统(x86_64)，如果检测有误，请联系作者"
    exit 2
fi

# ============ 配置区 ============
GITHUB_REPO="hekicore/heki"
MGMT_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/master/heki.sh"
# ================================

require_secure_url() {
    local url="$1"
    case "${url}" in
        https://*)
            return 0
            ;;
        *)
            echo -e "${red}拒绝使用非 HTTPS 下载地址: ${url}${plain}"
            return 1
            ;;
    esac
}

download_file() {
    local url="$1"
    local out_file="$2"

    require_secure_url "${url}" || return 1

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${out_file}" "${url}"
        return $?
    fi
    wget -O "${out_file}" "${url}"
}

normalize_version_output() {
    local raw="$1"
    raw="${raw#Heki }"
    raw="${raw#heki }"
    raw="${raw#v}"
    echo "${raw}"
}

verify_release_tarball() {
    local tarball="$1"
    local listing

    if ! tar -tzf "${tarball}" >/dev/null 2>&1; then
        echo -e "${red}下载的发布包不是有效的 tar.gz: ${tarball}${plain}"
        return 1
    fi

    listing=$(tar -tzf "${tarball}")
    for required in "heki/heki" "heki/heki.service" "heki/heki@.service" "heki/heki.conf"; do
        if ! echo "${listing}" | grep -qx "${required}"; then
            echo -e "${red}发布包缺少必要文件 ${required}: ${tarball}${plain}"
            return 1
        fi
    done
}

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

detect_service_manager() {
    if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        SERVICE_MANAGER="systemd"
        return 0
    fi
    if command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
        SERVICE_MANAGER="openrc"
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
        return 0
    fi
    if [[ "${release}" == "alpine" ]]; then
        echo -e "${red}未检测到 OpenRC，请确认系统已安装并初始化 openrc${plain}"
    else
        echo -e "${red}未检测到可用的服务管理器（systemd / OpenRC）${plain}"
    fi
    return 1
}

openrc_service_is_enabled() {
    local service_name="${1:-heki}"
    command rc-update show "${OPENRC_RUNLEVEL}" 2>/dev/null | awk '{print $1}' | grep -qx "${service_name}"
}

systemctl() {
    if [[ "${SERVICE_MANAGER}" != "openrc" ]]; then
        command systemctl "$@"
        return $?
    fi

    local action="$1"
    shift || true

    case "${action}" in
        daemon-reload)
            return 0
            ;;
        start|stop|restart)
            command rc-service "${1:-heki}" "${action}" >/dev/null 2>&1
            return $?
            ;;
        enable)
            local service_name="${1:-heki}"
            if openrc_service_is_enabled "${service_name}"; then
                return 0
            fi
            command rc-update add "${service_name}" "${OPENRC_RUNLEVEL}" >/dev/null 2>&1
            return $?
            ;;
        disable)
            local service_name="${1:-heki}"
            if ! openrc_service_is_enabled "${service_name}"; then
                return 0
            fi
            command rc-update del "${service_name}" "${OPENRC_RUNLEVEL}" >/dev/null 2>&1
            return $?
            ;;
        is-active)
            if [[ "${1:-}" == "--quiet" ]]; then
                shift
            fi
            command rc-service "${1:-heki}" status >/dev/null 2>&1
            return $?
            ;;
        *)
            echo -e "${red}OpenRC 兼容层暂不支持 systemctl ${action}${plain}" >&2
            return 1
            ;;
    esac
}

service_unit_installed() {
    if [[ "${SERVICE_MANAGER}" == "openrc" ]]; then
        [[ -x "${OPENRC_SERVICE_FILE}" ]]
    else
        [[ -f "${SYSTEMD_SERVICE_DIR}/heki.service" ]]
    fi
}

write_openrc_service_file() {
    local target="$1"
    cat > "${target}" <<EOF
#!/sbin/openrc-run

name="Heki"
description="Heki Service"

command="/usr/local/heki/heki"
command_args="-c /etc/heki/heki.conf"
pidfile="${OPENRC_PIDFILE}"
log_file="${OPENRC_LOG_DIR}/heki.log"
err_file="${OPENRC_LOG_DIR}/heki.err"
required_files="/etc/heki/heki.conf"

depend() {
    need net
    use dns logger
}

start_pre() {
    checkpath --directory --mode 0755 /run
    checkpath --directory --mode 0755 "${OPENRC_LOG_DIR}"
    checkpath --file --mode 0644 "${log_file}"
    checkpath --file --mode 0644 "${err_file}"
}

start() {
    start_pre || return $?
    ebegin "Starting \${RC_SVCNAME}"
    start-stop-daemon --start \
        --background \
        --make-pidfile \
        --pidfile "${OPENRC_PIDFILE}" \
        --stdout "${log_file}" \
        --stderr "${err_file}" \
        --exec "${command}" -- \${command_args}
    eend \$?
}

stop() {
    ebegin "Stopping \${RC_SVCNAME}"
    start-stop-daemon --stop --retry TERM/30/KILL/5 --pidfile "${OPENRC_PIDFILE}"
    local rc=\$?
    rm -f "${OPENRC_PIDFILE}"
    eend \${rc}
}
EOF
    chmod 755 "${target}"
}

install_runtime_service_files() {
    rm -f "${SYSTEMD_SERVICE_DIR}/heki.service" "${SYSTEMD_SERVICE_DIR}/heki@.service" "${OPENRC_SERVICE_FILE}"

    if [[ "${SERVICE_MANAGER}" == "openrc" ]]; then
        mkdir -p "$(dirname "${OPENRC_SERVICE_FILE}")"
        if [[ -f "heki.openrc" ]]; then
            install -m 755 "heki.openrc" "${OPENRC_SERVICE_FILE}"
        else
            write_openrc_service_file "${OPENRC_SERVICE_FILE}"
        fi
        return 0
    fi

    mkdir -p "${SYSTEMD_SERVICE_DIR}"
    cp -f heki.service "${SYSTEMD_SERVICE_DIR}/"
    cp -f heki@.service "${SYSTEMD_SERVICE_DIR}/"
}

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl tar crontabs socat tzdata -y
    elif [[ x"${release}" == x"alpine" ]]; then
        apk add --no-cache bash ca-certificates curl wget tar tzdata socat openssl openrc
        update-ca-certificates >/dev/null 2>&1 || true
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
    if ! service_unit_installed; then
        return 2
    fi
    if systemctl is-active --quiet heki 2>/dev/null; then
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

    require_secure_url "${api_url}" || exit 1
    require_secure_url "${MGMT_SCRIPT_URL}" || exit 1

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
        if download_file "${url}" "${out_file}" && verify_release_tarball "${out_file}"; then
            return 0
        fi
        rm -f "${out_file}"
    done

    return 1
}

install_heki() {
    cd /usr/local/
    if [[ -e /usr/local/heki/ ]]; then
        rm /usr/local/heki/ -rf
    fi

    print_subsection "下载并安装 Heki"
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
        if ! download_file "https://github.com/${GITHUB_REPO}/releases/latest/download/heki-linux-${arch}.tar.gz" "/usr/local/heki.tar.gz" || \
            ! verify_release_tarball "/usr/local/heki.tar.gz"; then
            echo -e "${red}下载 heki 失败，请确保你的服务器能够下载 Github 的文件${plain}"
            exit 1
        fi
    fi

    tar zxvf heki.tar.gz
    rm heki.tar.gz -f
    cd heki
    chmod +x heki
    last_version="$(normalize_version_output "$(./heki -v)")"
    mkdir /etc/heki/ -p
    install_runtime_service_files
    systemctl daemon-reload
    systemctl stop heki
    systemctl enable heki
    echo -e "${green}heki v${last_version}${plain} 安装完成，已设置开机自启 (${SERVICE_MANAGER})"
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
    print_post_install_guide
}

print_banner "Heki 安装脚本"
echo -e "  系统发行版: ${green}${release}${plain}"
echo -e "  CPU 架构:   ${green}${arch}${plain}"
if ${INSTALL_BETA}; then
    echo -e "  安装渠道:   ${yellow}beta${plain}"
elif [[ -n "${INSTALL_VERSION}" ]]; then
    echo -e "  安装版本:   ${green}${INSTALL_VERSION}${plain}"
else
    echo -e "  安装渠道:   ${green}latest${plain}"
fi

print_subsection "安装基础依赖"
install_base

if ! detect_service_manager; then
    exit 1
fi

print_subsection "检测服务管理器"
echo -e "  服务管理器: ${green}${SERVICE_MANAGER}${plain}"

print_subsection "安装可选组件"
echo -e "  acme.sh 用于自动申请 TLS 证书，不需要自动证书时可忽略"
install_acme
install_heki

# 首次安装后自动运行配置引导
# 检查配置文件是否包含必要的配置项（panel_url）
if [[ -f /etc/heki/heki.conf ]] && grep -q "panel_url=https://your-panel.com" /etc/heki/heki.conf 2>/dev/null; then
    print_banner "首次配置引导"
    echo -e "  检测到当前仍是示例配置，即将进入交互式配置"
    echo -e "  按 ${yellow}Ctrl+C${plain} 可跳过，稍后手动执行 ${green}heki setup${plain}"
    sleep 2
    heki setup
elif [[ ! -f /etc/heki/heki.conf ]]; then
    print_banner "首次配置引导"
    echo -e "  检测到当前还没有有效配置，即将进入交互式配置"
    echo -e "  按 ${yellow}Ctrl+C${plain} 可跳过，稍后手动执行 ${green}heki setup${plain}"
    sleep 2
    heki setup
else
    print_banner "安装完成"
    echo -e "  运行 ${green}heki setup${plain} 进行配置引导"
    echo -e "  运行 ${green}heki${plain} 查看管理菜单"
fi
