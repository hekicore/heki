#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
cyan='\033[0;36m'
bold='\033[1m'
plain='\033[0m'

cur_dir=$(pwd)
SERVICE_MANAGER=""
SYSTEMD_SERVICE_DIR="${HEKI_SYSTEMD_SERVICE_DIR:-/etc/systemd/system}"
OPENRC_SERVICE_FILE="${HEKI_OPENRC_SERVICE_FILE:-/etc/init.d/heki}"
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
    echo "  heki help            查看完整命令帮助"
    echo "  heki setup           重新进入配置引导"
    echo "  heki status          查看运行状态"
    echo "  heki log             查看日志"
    echo "  heki restart         重启服务"

    print_compact_section "配置、节点与实例"
    echo "  heki config          查看配置"
    echo "  heki node list       查看当前节点"
    echo "  heki node add <ID>   添加节点"
    echo "  heki node del <ID>   删除节点"
    echo "  heki instance list   查看实例列表"
    echo "  heki instance add <N> type=xboard server_type=vless panel_url=https://a.com panel_key=xxx node_id=1 heki_key=AAAA"
    echo "  heki instance setup <N> [k=v ...]   覆盖已有实例配置"
    echo "  heki cert            证书管理"
    echo "  heki reality gen     生成 Reality 密钥对"

    print_compact_section "维护命令"
    echo "  heki update          更新到最新正式版"
    echo "  heki update beta     更新到最新测试版"
    echo "  heki version         查看版本"
    echo "  heki uninstall       卸载"

    print_compact_section "配置示例"
    echo "  heki config type=sspanel-uim server_type=v2ray panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=xboard server_type=vless panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=ppanel server_type=trojan panel_url=https://xxx panel_key=xxx node_id=1"
    echo "  heki config type=heki-v1 server_type=vless panel_url=https://api.example.com/heki panel_key=xxx node_id=1"

    print_compact_section "参数范围"
    echo "  面板类型: sspanel-uim, metron, xboard, v2board, xiaov2board, ppanel, heki-v1"
    echo "  协议类型: v2ray(vmess), vless, ss, ssr, trojan, hysteria, tuic, anytls, naive, mieru"

    print_compact_section "更多帮助"
    echo "  heki help            查看完整命令说明"
}

INSTALL_BETA=false
INSTALL_VERSION=""
release="${release:-debian}"
arch="${arch:-amd64}"

# 测试可 source 脚本并只加载函数；正常执行仍完整检查 root、OS、架构和参数。
if [[ "${HEKI_INSTALL_LIB_ONLY:-0}" != "1" ]]; then
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
fi

# ============ 配置区 ============
GITHUB_REPO="hekicore/heki"
HEKI_RELEASE_BASE_URL="${HEKI_RELEASE_BASE_URL:-}"
HEKI_BINARY_TARBALL_PREFIX="${HEKI_BINARY_TARBALL_PREFIX:-heki-linux}"
HEKI_INSTALL_PINNED_VERSION="${HEKI_INSTALL_PINNED_VERSION:-}"
HEKI_MGMT_SCRIPT_URL="${HEKI_MGMT_SCRIPT_URL:-}"
MGMT_SCRIPT_URL="${HEKI_MGMT_SCRIPT_URL:-https://raw.githubusercontent.com/${GITHUB_REPO}/master/heki.sh}"
HEKI_INSTALL_DIR="${HEKI_INSTALL_DIR:-/usr/local/heki}"
HEKI_CONFIG_DIR="${HEKI_CONFIG_DIR:-/etc/heki}"
HEKI_MGMT_SCRIPT_PATH="${HEKI_MGMT_SCRIPT_PATH:-/usr/bin/heki}"
HEKI_INSTALL_HEALTH_DELAY="${HEKI_INSTALL_HEALTH_DELAY:-2}"
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
    local entry
    while IFS= read -r entry; do
        case "${entry}" in
            heki|heki/|heki/*) ;;
            *)
                echo -e "${red}发布包包含非法顶层路径: ${entry}${plain}"
                return 1
                ;;
        esac
        case "/${entry}/" in
            */../*|*/./*)
                echo -e "${red}发布包包含不安全路径: ${entry}${plain}"
                return 1
                ;;
        esac
    done <<< "${listing}"
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
    local source_dir="${1:-.}"
    rm -f "${SYSTEMD_SERVICE_DIR}/heki.service" "${SYSTEMD_SERVICE_DIR}/heki@.service" "${OPENRC_SERVICE_FILE}"

    if [[ "${SERVICE_MANAGER}" == "openrc" ]]; then
        mkdir -p "$(dirname "${OPENRC_SERVICE_FILE}")"
        if [[ -f "${source_dir}/heki.openrc" && ! -L "${source_dir}/heki.openrc" ]]; then
            install -m 755 "${source_dir}/heki.openrc" "${OPENRC_SERVICE_FILE}"
        else
            write_openrc_service_file "${OPENRC_SERVICE_FILE}"
        fi
        return 0
    fi

    mkdir -p "${SYSTEMD_SERVICE_DIR}"
    install -m 644 "${source_dir}/heki.service" "${SYSTEMD_SERVICE_DIR}/heki.service"
    install -m 644 "${source_dir}/heki@.service" "${SYSTEMD_SERVICE_DIR}/heki@.service"
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
    mkdir -p "$(dirname "${HEKI_MGMT_SCRIPT_PATH}")"
    install -m 755 "${tmp_script}" "${HEKI_MGMT_SCRIPT_PATH}"
    rm -f "${tmp_script}"
}

download_release_tarball() {
    local version="$1"
    local out_file="$2"
    local candidates=()

    if [[ -z "${version}" || -z "${out_file}" ]]; then
        return 1
    fi

    candidates+=("https://github.com/${GITHUB_REPO}/releases/download/${version}/${HEKI_BINARY_TARBALL_PREFIX}-${arch}.tar.gz")
    if [[ ! "${version}" =~ ^v ]]; then
        candidates+=("https://github.com/${GITHUB_REPO}/releases/download/v${version}/${HEKI_BINARY_TARBALL_PREFIX}-${arch}.tar.gz")
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

# 将当前新目录移开，再把旧目录放回原路径。所有 mv 都检查错误；
# 如果 mv 在实际移动后返回错误，则根据目录现状继续恢复，而不是假定没有移动。
restore_previous_install_dir() {
    local install_parent failed_dir
    if [[ -z "${HEKI_INSTALL_BACKUP_DIR}" || ! -d "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
        echo -e "${red}没有可恢复的旧版本目录备份${plain}"
        return 1
    fi
    install_parent="$(dirname "${HEKI_INSTALL_DIR}")"
    HEKI_INSTALL_FAILED_DIR=""

    if [[ -e "${HEKI_INSTALL_DIR}" || -L "${HEKI_INSTALL_DIR}" ]]; then
        failed_dir="$(mktemp -d "${install_parent}/.heki-failed.XXXXXX")" || return 1
        rmdir "${failed_dir}" || return 1
        if ! mv -- "${HEKI_INSTALL_DIR}" "${failed_dir}"; then
            if [[ -e "${HEKI_INSTALL_DIR}" || -L "${HEKI_INSTALL_DIR}" ]]; then
                echo -e "${red}新版本目录移出失败，旧版本备份仍位于 ${HEKI_INSTALL_BACKUP_DIR}${plain}"
                return 1
            fi
            # 当前目录已消失，说明 mv 可能移动后报错；保留现场并继续恢复旧版。
            [[ -d "${failed_dir}" ]] && HEKI_INSTALL_FAILED_DIR="${failed_dir}"
        else
            HEKI_INSTALL_FAILED_DIR="${failed_dir}"
        fi
    fi

    if ! mv -- "${HEKI_INSTALL_BACKUP_DIR}" "${HEKI_INSTALL_DIR}"; then
        if [[ ! -d "${HEKI_INSTALL_DIR}" || -e "${HEKI_INSTALL_BACKUP_DIR}" || -L "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
            echo -e "${red}旧版本目录恢复失败，备份仍位于 ${HEKI_INSTALL_BACKUP_DIR}${plain}"
            return 1
        fi
        echo -e "${yellow}旧版本目录已移动但 mv 返回错误，按目录现状继续恢复${plain}"
    fi
    if [[ ! -d "${HEKI_INSTALL_DIR}" ]]; then
        echo -e "${red}旧版本目录恢复后仍不存在，请人工检查${plain}"
        return 1
    fi
    HEKI_INSTALL_BACKUP_DIR=""
    return 0
}

activate_staged_release() {
    local staged_dir="$1"
    local install_parent
    install_parent="$(dirname "${HEKI_INSTALL_DIR}")"
    HEKI_INSTALL_BACKUP_DIR=""
    HEKI_INSTALL_FAILED_DIR=""
    HEKI_INSTALL_ACTIVATED=0

    if [[ ! -d "${staged_dir}" || -L "${staged_dir}" || ! -f "${staged_dir}/heki" || -L "${staged_dir}/heki" ]]; then
        echo -e "${red}暂存目录结构无效，拒绝切换: ${staged_dir}${plain}"
        return 1
    fi
    if [[ -e "${HEKI_INSTALL_DIR}" || -L "${HEKI_INSTALL_DIR}" ]]; then
        HEKI_INSTALL_BACKUP_DIR="$(mktemp -d "${install_parent}/.heki-backup.XXXXXX")" || return 1
        rmdir "${HEKI_INSTALL_BACKUP_DIR}" || return 1
        if ! mv -- "${HEKI_INSTALL_DIR}" "${HEKI_INSTALL_BACKUP_DIR}"; then
            echo -e "${red}无法备份旧版本，未执行安装切换${plain}"
            if [[ ! -e "${HEKI_INSTALL_DIR}" && ! -L "${HEKI_INSTALL_DIR}" && -d "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
                # 旧目录可能已经被移动；立即尝试放回去。
                if mv -- "${HEKI_INSTALL_BACKUP_DIR}" "${HEKI_INSTALL_DIR}"; then
                    HEKI_INSTALL_BACKUP_DIR=""
                elif [[ -d "${HEKI_INSTALL_DIR}" && ! -e "${HEKI_INSTALL_BACKUP_DIR}" && ! -L "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
                    echo -e "${yellow}旧版本目录已移动但恢复 mv 返回错误，按目录现状继续${plain}"
                    HEKI_INSTALL_BACKUP_DIR=""
                else
                    echo -e "${red}旧版本恢复失败，备份位于 ${HEKI_INSTALL_BACKUP_DIR}${plain}"
                fi
            elif [[ -e "${HEKI_INSTALL_DIR}" || -L "${HEKI_INSTALL_DIR}" ]]; then
                HEKI_INSTALL_BACKUP_DIR=""
            fi
            return 1
        fi
    fi
    if ! mv -- "${staged_dir}" "${HEKI_INSTALL_DIR}"; then
        echo -e "${red}新版本目录切换失败${plain}"
        if [[ -n "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
            restore_previous_install_dir || echo -e "${red}切换失败后的旧版本恢复未完成${plain}"
        elif [[ -e "${HEKI_INSTALL_DIR}" || -L "${HEKI_INSTALL_DIR}" ]]; then
            # 没有旧版时只清理本次新目录，绝不触碰其他路径。
            rm -rf -- "${HEKI_INSTALL_DIR}" || echo -e "${red}新目录清理失败: ${HEKI_INSTALL_DIR}${plain}"
        fi
        return 1
    fi
    HEKI_INSTALL_ACTIVATED=1
}

rollback_installed_release() {
    local service_file_installer="$1"
    local config_backup="${2:-}"
    local service_was_running="${3:-1}"
    local result=0 directory_restored=0
    if [[ -z "${HEKI_INSTALL_BACKUP_DIR}" || ! -d "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
        echo -e "${red}没有可恢复的旧版本备份${plain}"
        return 1
    fi

    echo -e "${yellow}新版本启用失败，正在恢复旧版本 ${HEKI_INSTALL_BACKUP_DIR}${plain}"
    systemctl stop heki >/dev/null 2>&1 || echo -e "${yellow}停止新版本服务失败，继续尝试目录恢复${plain}"
    if restore_previous_install_dir; then
        directory_restored=1
        HEKI_INSTALL_ACTIVATED=0
    else
        result=1
    fi
    # 即使目录恢复失败也尝试恢复配置；配置备份不能在此时被清理。
    if [[ -n "${config_backup}" && -f "${config_backup}" ]]; then
        if ! cp -p "${config_backup}" "${HEKI_CONFIG_DIR}/heki.conf"; then
            echo -e "${red}旧配置恢复失败，备份位于 ${config_backup}${plain}"
            result=1
        fi
    fi
    if [[ "${directory_restored}" == "1" ]]; then
        if ! "${service_file_installer}" "${HEKI_INSTALL_DIR}"; then
            echo -e "${red}旧服务文件恢复失败，请人工检查${plain}"
            result=1
        fi
        if ! systemctl daemon-reload; then
            echo -e "${red}旧服务文件重新加载失败${plain}"
            result=1
        fi
        if [[ "${service_was_running}" == "1" ]]; then
            if ! systemctl start heki; then
                echo -e "${red}旧版本已恢复，但服务启动失败，请人工检查${plain}"
                result=1
            fi
        fi
    fi
    if [[ "${result}" != "0" ]]; then
        return 1
    fi
    HEKI_INSTALL_ACTIVATED=0
    if [[ -n "${HEKI_INSTALL_FAILED_DIR}" ]]; then
        rm -rf -- "${HEKI_INSTALL_FAILED_DIR}"
        HEKI_INSTALL_FAILED_DIR=""
    fi
    echo -e "${green}已恢复旧版本: ${HEKI_INSTALL_DIR}${plain}"
}

# 安装任一步骤失败时统一回滚。回滚未完全成功则保留 work_dir，
# 其中的配置备份和错误现场不能被无条件 rm -rf 清理掉。
fail_install_and_rollback() {
    local service_file_installer="$1"
    local config_backup="$2"
    local work_dir="$3"
    local service_was_running="${4:-1}"
    if [[ -n "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
        if ! rollback_installed_release "${service_file_installer}" "${config_backup}" "${service_was_running}"; then
            echo -e "${red}自动回滚未完全成功，保留现场和配置备份: ${work_dir}${plain}"
            return 1
        fi
    else
        if [[ "${HEKI_INSTALL_ACTIVATED:-0}" == "1" ]]; then
            systemctl stop heki >/dev/null 2>&1 || true
            if ! rm -rf -- "${HEKI_INSTALL_DIR}"; then
                echo -e "${red}新安装目录清理失败，保留现场: ${HEKI_INSTALL_DIR}${plain}"
                return 1
            fi
            HEKI_INSTALL_ACTIVATED=0
        fi
        if [[ "${HEKI_INSTALL_CONFIG_CREATED:-0}" == "1" ]]; then
            rm -f -- "${HEKI_CONFIG_DIR}/heki.conf" || return 1
            HEKI_INSTALL_CONFIG_CREATED=0
        fi
    fi
    rm -rf -- "${work_dir}"
    return 1
}

install_heki() {
    local install_parent work_dir tarball unpack_dir staged_dir last_version raw_version beta_tag
    local all_releases current_tag had_config health_status service_was_running
    local config_backup runtime_file required_file
    install_parent="$(dirname "${HEKI_INSTALL_DIR}")"
    mkdir -p "${install_parent}" || return 1
    work_dir="$(mktemp -d "${install_parent}/.heki-install.XXXXXX")" || return 1
    tarball="${work_dir}/heki.tar.gz"
    unpack_dir="${work_dir}/unpacked"
    staged_dir="${unpack_dir}/heki"
    config_backup="${work_dir}/heki.conf.previous"
    HEKI_INSTALL_BACKUP_DIR=""
    HEKI_INSTALL_FAILED_DIR=""
    HEKI_INSTALL_ACTIVATED=0
    HEKI_INSTALL_CONFIG_CREATED=0
    had_config=0
    if [[ -f "${HEKI_CONFIG_DIR}/heki.conf" ]]; then
        had_config=1
    fi

    print_subsection "下载并安装 Heki"
    if ${INSTALL_BETA}; then
        # 测试版: 从最新的 pre-release 下载
        echo -e "${yellow}安装 heki 测试版 (beta)${plain}"
        if ! all_releases=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases"); then
            echo -e "${red}获取 heki 测试版列表失败${plain}"
            rm -rf -- "${work_dir}"
            return 1
        fi
        beta_tag=""
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
            if echo "${line}" | grep -q '"prerelease": false'; then
                current_tag=""
            fi
        done <<< "${all_releases}"
        if [[ -z "${beta_tag}" ]]; then
            echo -e "${red}未找到 beta 版本，请确认是否已发布测试版${plain}"
            rm -rf -- "${work_dir}"
            return 1
        fi
        echo -e "最新测试版: ${beta_tag}"
        if ! download_release_tarball "${beta_tag}" "${tarball}"; then
            echo -e "${red}下载 heki ${beta_tag} 失败，旧版本保持不变${plain}"
            rm -rf -- "${work_dir}"
            return 1
        fi
    elif [[ -n "${INSTALL_VERSION}" ]]; then
        last_version="${INSTALL_VERSION}"
        echo -e "开始安装 heki v${last_version}"
        if ! download_release_tarball "${last_version}" "${tarball}"; then
            echo -e "${red}下载 heki v${last_version} 失败，旧版本保持不变${plain}"
            rm -rf -- "${work_dir}"
            return 1
        fi
    else
        echo -e "开始安装 heki 最新正式版"
        if ! download_file "https://github.com/${GITHUB_REPO}/releases/latest/download/${HEKI_BINARY_TARBALL_PREFIX}-${arch}.tar.gz" "${tarball}" || \
            ! verify_release_tarball "${tarball}"; then
            echo -e "${red}下载 heki 失败，旧版本保持不变${plain}"
            rm -rf -- "${work_dir}"
            return 1
        fi
    fi

    mkdir -p "${unpack_dir}"
    if ! tar -xzf "${tarball}" -C "${unpack_dir}"; then
        echo -e "${red}发布包解包失败，旧版本保持不变${plain}"
        rm -rf -- "${work_dir}"
        return 1
    fi
    for required_file in heki heki.service heki@.service heki.conf; do
        if [[ ! -f "${staged_dir}/${required_file}" || -L "${staged_dir}/${required_file}" ]]; then
            echo -e "${red}发布包文件无效: ${required_file}${plain}"
            rm -rf -- "${work_dir}"
            return 1
        fi
    done
    chmod 755 "${staged_dir}/heki"
    if ! raw_version="$("${staged_dir}/heki" -v)"; then
        echo -e "${red}新版本二进制无法执行，旧版本保持不变${plain}"
        rm -rf -- "${work_dir}"
        return 1
    fi
    last_version="$(normalize_version_output "${raw_version}")"

    mkdir -p "${HEKI_CONFIG_DIR}"
    if [[ "${had_config}" == "1" ]] && ! cp -p "${HEKI_CONFIG_DIR}/heki.conf" "${config_backup}"; then
        echo -e "${red}无法备份现有配置，取消安装${plain}"
        rm -rf -- "${work_dir}"
        return 1
    fi

    service_was_running=0
    if check_status; then
        service_was_running=1
    fi
    # 停服切换到健康检查通过之间收到 INT/TERM 时，按当前状态回滚或恢复旧版服务。
    # work_dir 为空说明函数已返回（局部变量失效），不在切换窗口内，直接退出。
    trap '
        if [[ -z "${work_dir}" ]]; then
            exit 1
        fi
        if [[ -n "${HEKI_INSTALL_BACKUP_DIR}" || "${HEKI_INSTALL_ACTIVATED:-0}" == "1" ]]; then
            fail_install_and_rollback install_runtime_service_files "${config_backup}" "${work_dir}" "${service_was_running}" || true
        elif [[ "${service_was_running}" == "1" ]]; then
            systemctl start heki >/dev/null 2>&1 || true
        fi
        exit 1
    ' INT TERM
    if [[ "${service_was_running}" == "1" ]]; then
        if ! systemctl stop heki; then
            echo -e "${red}无法停止现有服务，取消切换${plain}"
            rm -rf -- "${work_dir}"
            return 1
        fi
    else
        systemctl stop heki >/dev/null 2>&1 || true
    fi

    if ! activate_staged_release "${staged_dir}"; then
        if [[ -n "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
            fail_install_and_rollback install_runtime_service_files "${config_backup}" "${work_dir}" "${service_was_running}" || return 1
        fi
        if [[ "${service_was_running}" == "1" && -d "${HEKI_INSTALL_DIR}" && -z "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
            if ! systemctl start heki; then
                echo -e "${red}切换失败后旧版本服务启动失败，保留现场: ${work_dir}${plain}"
                return 1
            fi
        fi
        rm -rf -- "${work_dir}"
        return 1
    fi
    if ! install_runtime_service_files "${HEKI_INSTALL_DIR}" || \
        ! systemctl daemon-reload || ! systemctl enable heki; then
        echo -e "${red}新服务文件安装或启用失败${plain}"
        fail_install_and_rollback install_runtime_service_files "${config_backup}" "${work_dir}" "${service_was_running}" || return 1
    fi

    if [[ "${had_config}" == "0" ]]; then
        # 从尝试写入开始就记录“本次新建”，失败时才能清理可能已部分写入的配置。
        HEKI_INSTALL_CONFIG_CREATED=1
        if ! install -m 600 "${HEKI_INSTALL_DIR}/heki.conf" "${HEKI_CONFIG_DIR}/heki.conf"; then
            echo -e "${red}默认配置写入失败${plain}"
            fail_install_and_rollback install_runtime_service_files "${config_backup}" "${work_dir}" "${service_was_running}" || return 1
        fi
        echo -e "\n全新安装，请先配置必要的内容"
    elif declare -F sync_offline_license_fields_from_bundle >/dev/null 2>&1; then
        if ! sync_offline_license_fields_from_bundle "${HEKI_INSTALL_DIR}/heki.conf" "${HEKI_CONFIG_DIR}/heki.conf"; then
            echo -e "${red}离线授权配置同步失败${plain}"
            fail_install_and_rollback install_runtime_service_files "${config_backup}" "${work_dir}" "${service_was_running}" || return 1
        fi
    fi

    for runtime_file in blockList whiteList dns.yml routes.toml; do
        if [[ -f "${HEKI_INSTALL_DIR}/${runtime_file}" && ! -e "${HEKI_CONFIG_DIR}/${runtime_file}" ]]; then
            if ! cp "${HEKI_INSTALL_DIR}/${runtime_file}" "${HEKI_CONFIG_DIR}/${runtime_file}"; then
                echo -e "${red}运行配置 ${runtime_file} 写入失败${plain}"
                fail_install_and_rollback install_runtime_service_files "${config_backup}" "${work_dir}" "${service_was_running}" || return 1
            fi
        fi
    done

    if [[ "${had_config}" == "1" || -n "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
        health_status=0
        if ! systemctl start heki; then
            health_status=1
        elif ! sleep "${HEKI_INSTALL_HEALTH_DELAY}"; then
            health_status=1
        else
            check_status
            health_status=$?
        fi
        if [[ "${health_status}" != "0" ]]; then
            echo -e "${red}新版本健康检查失败${plain}"
            fail_install_and_rollback install_runtime_service_files "${config_backup}" "${work_dir}" "${service_was_running}" || return 1
        fi
        echo -e "${green}heki 重启成功${plain}"
    fi

    if [[ -n "${HEKI_INSTALL_BACKUP_DIR}" ]]; then
        rm -rf -- "${HEKI_INSTALL_BACKUP_DIR}"
        HEKI_INSTALL_BACKUP_DIR=""
    fi
    if [[ -n "${HEKI_INSTALL_FAILED_DIR}" ]]; then
        rm -rf -- "${HEKI_INSTALL_FAILED_DIR}"
        HEKI_INSTALL_FAILED_DIR=""
    fi
    HEKI_INSTALL_ACTIVATED=0
    HEKI_INSTALL_CONFIG_CREATED=0
    trap - INT TERM
    rm -rf -- "${work_dir}"
    echo -e "${green}heki v${last_version}${plain} 安装完成，已设置开机自启 (${SERVICE_MANAGER})"
    install_mgmt_script
    print_post_install_guide
}

main() {
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
if ! install_heki; then
    echo -e "${red}Heki 安装或升级未完成${plain}"
    exit 1
fi

# 首次安装后自动运行配置引导
# 检查配置文件是否包含必要的配置项（panel_url）
if [[ -f "${HEKI_CONFIG_DIR}/heki.conf" ]] && grep -q "panel_url=https://your-panel.com" "${HEKI_CONFIG_DIR}/heki.conf" 2>/dev/null; then
    print_banner "首次配置引导"
    echo -e "  检测到当前仍是示例配置，即将进入交互式配置"
    echo -e "  按 ${yellow}Ctrl+C${plain} 可跳过，稍后手动执行 ${green}heki setup${plain}"
    sleep 2
    heki setup
elif [[ ! -f "${HEKI_CONFIG_DIR}/heki.conf" ]]; then
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
}

if [[ "${HEKI_INSTALL_LIB_ONLY:-0}" != "1" ]]; then
    main "$@"
fi
