#!/bin/bash

# Heki 管理脚本
# 安装后位于 /usr/bin/heki

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="/etc/heki"
BIN_PATH="/usr/local/heki/heki"
CONFIG_FILE="${INSTALL_DIR}/heki.conf"
SERVICE_NAME="heki"

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请使用 root 用户运行${NC}"
        exit 1
    fi
}

get_version() {
    if [ -f "${BIN_PATH}" ]; then
        "${BIN_PATH}" -v 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

# 将 openssl 的英文日期格式转为中文友好格式
# 输入: "May 12 05:29:47 2026 GMT"  输出: "2026-05-12 05:29:47"
format_cert_date() {
    local raw="$1"
    if [ -z "${raw}" ]; then
        echo "未知"
        return
    fi
    # 尝试用 date 命令转换
    local formatted
    formatted=$(date -d "${raw}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    if [ -n "${formatted}" ]; then
        echo "${formatted}"
    else
        # macOS 或 date 不支持 -d 的系统，直接输出原始值
        echo "${raw}"
    fi
}

# 计算证书剩余天数
cert_days_left() {
    local cert_file="$1"
    if [ ! -f "${cert_file}" ]; then
        return
    fi
    local expiry_epoch now_epoch
    expiry_epoch=$(date -d "$(openssl x509 -enddate -noout -in "${cert_file}" 2>/dev/null | sed 's/notAfter=//')" '+%s' 2>/dev/null)
    now_epoch=$(date '+%s' 2>/dev/null)
    if [ -n "${expiry_epoch}" ] && [ -n "${now_epoch}" ]; then
        echo $(( (expiry_epoch - now_epoch) / 86400 ))
    fi
}

get_status() {
    if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}未运行${NC}"
    fi
}

get_enabled() {
    if systemctl is-enabled --quiet ${SERVICE_NAME} 2>/dev/null; then
        echo -e "${GREEN}已启用${NC}"
    else
        echo -e "${YELLOW}未启用${NC}"
    fi
}

# 显示节点运行摘要（启动/重启后调用）
_show_node_summary() {
    NODES_DIR="${INSTALL_DIR}/nodes"
    [ -d "${NODES_DIR}" ] || return
    NODE_FILES=$(ls "${NODES_DIR}"/node_*.conf 2>/dev/null)
    [ -n "${NODE_FILES}" ] || return
    echo ""
    for nf in ${NODE_FILES}; do
        NID=$(grep "^node_id=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
        NTYPE=$(grep "^server_type=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
        NPORT=$(grep "^listen_port=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
        NPP=$(grep "^proxy_protocol=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
        DETAIL=""
        case "${NTYPE}" in
            ss)     DETAIL=$(grep "^ss_method=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2) ;;
            vmess)  DETAIL=$(grep "^vmess_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2) ;;
            anytls) DETAIL=$(grep "^anytls_sni=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2) ;;
            vless)  DETAIL=$(grep "^vless_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    VFLOW=$(grep "^vless_flow=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    [ -n "${VFLOW}" ] && DETAIL="${DETAIL},flow=${VFLOW}"
                    VREAL=$(grep "^vless_reality=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    [ "${VREAL}" = "true" ] && DETAIL="${DETAIL},reality"
                    ;;
            ssr)    DETAIL=$(grep "^ssr_protocol=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    OBFS=$(grep "^ssr_obfs=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    [ -n "${OBFS}" ] && DETAIL="${DETAIL},obfs=${OBFS}"
                    ;;
            trojan) DETAIL=$(grep "^trojan_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    [ -z "${DETAIL}" ] && DETAIL="tcp"
                    ;;
            hysteria) HOBFS=$(grep "^hysteria_obfs_type=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    HUP=$(grep "^hysteria_up_mbps=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    HDOWN=$(grep "^hysteria_down_mbps=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    DETAIL=""
                    [ -n "${HOBFS}" ] && [ "${HOBFS}" != "plain" ] && DETAIL="obfs=${HOBFS}"
                    [ -n "${HUP}" ] && DETAIL="${DETAIL:+${DETAIL},}up=${HUP}Mbps"
                    [ -n "${HDOWN}" ] && DETAIL="${DETAIL:+${DETAIL},}down=${HDOWN}Mbps"
                    ;;
            naive)  NTLS=$(grep "^naive_enable_tls=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    NSNI=$(grep "^naive_server_name=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    DETAIL=""
                    [ "${NTLS}" = "true" ] && DETAIL="tls"
                    [ -n "${NSNI}" ] && DETAIL="${DETAIL:+${DETAIL},}sni=${NSNI}"
                    ;;
            mieru)  MTRANS=$(grep "^mieru_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    MMUX=$(grep "^mieru_multiplexing=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    DETAIL="transport=${MTRANS}"
                    [ -n "${MMUX}" ] && DETAIL="${DETAIL},mux=${MMUX}"
                    ;;
        esac
        PP_STR=""
        [ "${NPP}" = "true" ] && PP_STR=" PP=ON"
        echo -e "  Node ${NID}: ${GREEN}${NTYPE}${NC} | port=${NPORT} | ${DETAIL}${PP_STR}"
    done
}

do_start() {
    check_root
    if [ ! -f "${BIN_PATH}" ]; then
        echo -e "${RED}heki-server 未安装，请先安装${NC}"
        exit 1
    fi
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在: ${CONFIG_FILE}${NC}"
        exit 1
    fi
    echo -e "${GREEN}启动 Heki...${NC}"
    systemctl start ${SERVICE_NAME}
    sleep 2
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "${GREEN}Heki 启动成功${NC}"
        _show_node_summary
    else
        echo -e "${RED}Heki 启动失败，请查看日志: heki log${NC}"
    fi
}

do_stop() {
    check_root
    echo -e "${YELLOW}停止 Heki...${NC}"
    systemctl stop ${SERVICE_NAME}
    echo -e "${GREEN}Heki 已停止${NC}"
}

do_restart() {
    check_root
    echo -e "${GREEN}重启 Heki...${NC}"
    systemctl restart ${SERVICE_NAME}
    sleep 2
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "${GREEN}Heki 重启成功${NC}"
        _show_node_summary
    else
        echo -e "${RED}Heki 重启失败，请查看日志: heki log${NC}"
    fi
}

do_enable() {
    check_root
    systemctl enable ${SERVICE_NAME}
    echo -e "${GREEN}已设置 Heki 开机自启${NC}"
}

do_disable() {
    check_root
    systemctl disable ${SERVICE_NAME}
    echo -e "${YELLOW}已取消 Heki 开机自启${NC}"
}

do_log() {
    # 检测是否多节点，提供按节点过滤日志的选项
    NODES_DIR="${INSTALL_DIR}/nodes"
    NODE_IDS=()
    if [ -d "${NODES_DIR}" ]; then
        for nf in "${NODES_DIR}"/node_*.conf; do
            [ -f "${nf}" ] || continue
            NID=$(grep "^node_id=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
            NTYPE=$(grep "^server_type=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
            [ -n "${NID}" ] && NODE_IDS+=("${NID}:${NTYPE}")
        done
    fi

    if [ ${#NODE_IDS[@]} -gt 1 ]; then
        echo ""
        echo -e "${CYAN}检测到多节点，选择查看方式:${NC}"
        echo -e "  ${GREEN}0.${NC} 全部日志"
        local idx=1
        for entry in "${NODE_IDS[@]}"; do
            local nid="${entry%%:*}"
            local ntype="${entry##*:}"
            echo -e "  ${GREEN}${idx}.${NC} Node ${nid} (${ntype})"
            idx=$((idx + 1))
        done
        echo ""
        read -p "选择 [0]: " LOG_CHOICE
        LOG_CHOICE=${LOG_CHOICE:-0}

        if [ "${LOG_CHOICE}" != "0" ] && [ "${LOG_CHOICE}" -ge 1 ] 2>/dev/null && [ "${LOG_CHOICE}" -le ${#NODE_IDS[@]} ]; then
            local selected="${NODE_IDS[$((LOG_CHOICE - 1))]}"
            local sel_nid="${selected%%:*}"
            local sel_type="${selected##*:}"
            echo -e "${CYAN}过滤 Node ${sel_nid} (${sel_type}) 的日志:${NC}"
            echo ""
            journalctl -u ${SERVICE_NAME} --no-pager -n 200 | grep -E "\[Node ${sel_nid}\]|AnyTLS|VMess|VLESS|SS " | grep -v "^\s*$" | tail -100
            echo ""
            echo -e "${YELLOW}以上为历史日志，按 Enter 进入实时模式 (Ctrl+C 退出)${NC}"
            read -r
            journalctl -u ${SERVICE_NAME} -f --no-pager | grep --line-buffered -E "\[Node ${sel_nid}\]"
        else
            journalctl -u ${SERVICE_NAME} -f --no-pager -n 100
        fi
    else
        journalctl -u ${SERVICE_NAME} -f --no-pager -n 100
    fi
}

do_status() {
    echo -e "${CYAN}Heki 状态信息${NC}"
    echo "----------------------------------------"
    echo -e "版本:     $(get_version)"
    echo -e "状态:     $(get_status)"
    echo -e "开机自启: $(get_enabled)"
    # 显示面板类型
    if [ -f "${CONFIG_FILE}" ]; then
        CUR_TYPE=$(grep "^type=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
        [ -z "${CUR_TYPE}" ] && CUR_TYPE="sspanel-uim(默认)"
        echo -e "面板类型: ${CUR_TYPE}"
    fi
    echo "配置文件: ${CONFIG_FILE}"
    echo "二进制:   ${BIN_PATH}"
    echo "----------------------------------------"

    if systemctl is-active --quiet ${SERVICE_NAME}; then
        PID=$(systemctl show -p MainPID --value ${SERVICE_NAME})
        if [ "${PID}" != "0" ] && [ -n "${PID}" ]; then
            MEM=$(ps -o rss= -p "${PID}" 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
            UPTIME=$(ps -o etime= -p "${PID}" 2>/dev/null | xargs)
            echo "PID:      ${PID}"
            echo "内存:     ${MEM}"
            echo "运行时间: ${UPTIME}"
            echo "----------------------------------------"
        fi

        # 显示节点运行配置（从自动生成的节点配置文件读取）
        NODES_DIR="${INSTALL_DIR}/nodes"
        if [ -d "${NODES_DIR}" ]; then
            NODE_FILES=$(ls "${NODES_DIR}"/node_*.conf 2>/dev/null)
            if [ -n "${NODE_FILES}" ]; then
                echo ""
                echo -e "${CYAN}节点运行信息:${NC}"
                echo "----------------------------------------"
                for nf in ${NODE_FILES}; do
                    NID=$(grep "^node_id=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    NTYPE=$(grep "^server_type=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    NPORT=$(grep "^listen_port=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    NPP=$(grep "^proxy_protocol=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                    NRATE=$(grep "^traffic_rate=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)

                    # 协议详情
                    DETAIL=""
                    case "${NTYPE}" in
                        ss)
                            METHOD=$(grep "^ss_method=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            IS2022=$(grep "^ss_is_2022=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL="method=${METHOD}"
                            [ "${IS2022}" = "true" ] && DETAIL="${DETAIL} (SS2022)"
                            ;;
                        vmess)
                            TRANS=$(grep "^vmess_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            TLS=$(grep "^vmess_enable_tls=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL="transport=${TRANS}"
                            [ "${TLS}" = "true" ] && DETAIL="${DETAIL}+tls"
                            ;;
                        anytls)
                            SNI=$(grep "^anytls_sni=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL="sni=${SNI}"
                            ;;
                        vless)
                            TRANS=$(grep "^vless_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            FLOW=$(grep "^vless_flow=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            TLS=$(grep "^vless_enable_tls=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            REAL=$(grep "^vless_reality=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL="transport=${TRANS}"
                            [ -n "${FLOW}" ] && DETAIL="${DETAIL}, flow=${FLOW}"
                            if [ "${REAL}" = "true" ]; then
                                DETAIL="${DETAIL}+reality"
                            elif [ "${TLS}" = "true" ]; then
                                DETAIL="${DETAIL}+tls"
                            fi
                            ;;
                        ssr)
                            METHOD=$(grep "^ssr_method=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            PROTO=$(grep "^ssr_protocol=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            OBFS=$(grep "^ssr_obfs=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL="method=${METHOD}, protocol=${PROTO}, obfs=${OBFS}"
                            ;;
                        trojan)
                            TRANS=$(grep "^trojan_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            TLS=$(grep "^trojan_enable_tls=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL="transport=${TRANS:-tcp}"
                            [ "${TLS}" = "true" ] && DETAIL="${DETAIL}+tls"
                            ;;
                        hysteria)
                            HOBFS=$(grep "^hysteria_obfs_type=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            HUP=$(grep "^hysteria_up_mbps=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            HDOWN=$(grep "^hysteria_down_mbps=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL=""
                            [ -n "${HOBFS}" ] && [ "${HOBFS}" != "plain" ] && DETAIL="obfs=${HOBFS}"
                            [ -n "${HUP}" ] && DETAIL="${DETAIL:+${DETAIL}, }up=${HUP}Mbps"
                            [ -n "${HDOWN}" ] && DETAIL="${DETAIL:+${DETAIL}, }down=${HDOWN}Mbps"
                            ;;
                        naive)
                            NTLS=$(grep "^naive_enable_tls=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            NSNI=$(grep "^naive_server_name=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL=""
                            [ "${NTLS}" = "true" ] && DETAIL="tls"
                            [ -n "${NSNI}" ] && DETAIL="${DETAIL:+${DETAIL}, }sni=${NSNI}"
                            ;;
                        mieru)
                            MTRANS=$(grep "^mieru_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            MMUX=$(grep "^mieru_multiplexing=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                            DETAIL="transport=${MTRANS}"
                            [ -n "${MMUX}" ] && DETAIL="${DETAIL}, mux=${MMUX}"
                            ;;
                    esac

                    PP_STR=""
                    [ "${NPP}" = "true" ] && PP_STR=" ${GREEN}PP=ON${NC}"

                    echo -e "  Node ${NID}: ${GREEN}${NTYPE}${NC} | port=${NPORT} | ${DETAIL} | rate=${NRATE}${PP_STR}"
                done
                echo "----------------------------------------"
                echo -e "  节点配置目录: ${CYAN}${NODES_DIR}/${NC}"
            fi
        fi
    fi
}

# 判断值是否为纯数字或布尔值（不需要引号）
is_plain_value() {
    local val="$1"
    case "${val}" in
        true|false|True|False|TRUE|FALSE) return 0 ;;
        *[!0-9]*) return 1 ;;
        '') return 1 ;;
        *) return 0 ;;
    esac
}

do_config() {
    if [ $# -eq 0 ]; then
        if [ -f "${CONFIG_FILE}" ]; then
            echo -e "${CYAN}当前配置文件内容 (${CONFIG_FILE}):${NC}"
            echo "----------------------------------------"
            cat "${CONFIG_FILE}"
        else
            echo -e "${RED}配置文件不存在: ${CONFIG_FILE}${NC}"
        fi
        return
    fi

    check_root

    for arg in "$@"; do
        KEY="${arg%%=*}"
        VALUE="${arg#*=}"

        if [ -z "${KEY}" ] || [ "${KEY}" = "${arg}" ]; then
            echo -e "${RED}无效参数: ${arg}，格式应为 key=value${NC}"
            continue
        fi

        if grep -q "^${KEY}=" "${CONFIG_FILE}" 2>/dev/null; then
            sed -i "s|^${KEY}=.*|${KEY}=${VALUE}|" "${CONFIG_FILE}"
            echo -e "${GREEN}已更新: ${KEY} = ${VALUE}${NC}"
        else
            echo "${KEY}=${VALUE}" >> "${CONFIG_FILE}"
            echo -e "${GREEN}已添加: ${KEY} = ${VALUE}${NC}"
        fi
    done
    echo ""
    echo -e "${YELLOW}配置已修改，如需生效请重启: heki restart${NC}"
}

do_update() {
    check_root

    local GITHUB_REPO="hekicore/heki"
    local INSTALL_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/install.sh"

    echo -e "${GREEN}正在检查更新...${NC}"

    local TMP_INSTALL=$(mktemp)
    if curl -sL -H "Accept: application/vnd.github.v3.raw" -o "${TMP_INSTALL}" "${INSTALL_URL}" && [ -s "${TMP_INSTALL}" ]; then
        if head -1 "${TMP_INSTALL}" | grep -q "^#!/bin/bash"; then
            echo -e "${GREEN}正在更新...${NC}"
            bash "${TMP_INSTALL}"
            rm -f "${TMP_INSTALL}"
            return
        fi
    fi
    rm -f "${TMP_INSTALL}"

    echo -e "${RED}更新失败，请手动运行:${NC}"
    echo -e "  bash <(curl -Ls ${INSTALL_URL})"
}

do_install() {
    check_root
    local GITHUB_REPO="hekicore/heki"
    local INSTALL_URL="https://api.github.com/repos/${GITHUB_REPO}/contents/install.sh"
    echo -e "${GREEN}正在重新安装...${NC}"
    bash <(curl -sL -H "Accept: application/vnd.github.v3.raw" "${INSTALL_URL}")
}

do_uninstall() {
    check_root
    echo -e "${RED}${BOLD}警告: 即将卸载 Heki!${NC}"
    read -p "确认卸载？(y/N): " confirm
    if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
        echo "取消卸载"
        return
    fi

    echo -e "${YELLOW}停止服务...${NC}"
    systemctl stop ${SERVICE_NAME} 2>/dev/null || true
    systemctl disable ${SERVICE_NAME} 2>/dev/null || true

    echo -e "${YELLOW}删除文件...${NC}"
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    rm -f "/etc/systemd/system/${SERVICE_NAME}@.service"
    systemctl daemon-reload
    rm -rf "/usr/local/heki/"
    rm -f "/usr/bin/heki"

    read -p "是否删除配置文件 ${INSTALL_DIR}？(y/N): " del_config
    if [ "${del_config}" = "y" ] || [ "${del_config}" = "Y" ]; then
        rm -rf "${INSTALL_DIR}"
        echo -e "${GREEN}配置文件已删除${NC}"
    else
        echo -e "${YELLOW}配置文件已保留${NC}"
    fi

    echo -e "${GREEN}Heki 已卸载${NC}"
}

do_setup() {
    check_root
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       Heki 配置引导                 ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "${GREEN}只需填写面板信息，其他全部自动从面板获取${NC}"
    echo -e "${YELLOW}注意: 这将覆盖现有配置文件!${NC}"
    echo ""

    read -p "确认重新配置？(y/N): " confirm
    if [ "${confirm}" != "y" ] && [ "${confirm}" != "Y" ]; then
        echo "取消配置"
        return
    fi

    echo ""
    echo -e "${CYAN}---- 面板对接配置 ----${NC}"
    echo ""

    # 面板类型选择
    echo -e "${CYAN}面板类型:${NC}"
    echo -e "  ${GREEN}1.${NC} sspanel-uim（默认）"
    echo -e "  ${GREEN}2.${NC} xboard"
    echo -e "  ${GREEN}3.${NC} v2board（原版）"
    echo -e "  ${GREEN}4.${NC} xiaov2board（wyx2685 分支）"
    echo ""
    read -p "选择面板类型 [1]: " S_PANEL_TYPE_CHOICE
    S_PANEL_TYPE_CHOICE=${S_PANEL_TYPE_CHOICE:-1}
    case ${S_PANEL_TYPE_CHOICE} in
        2) S_PANEL_TYPE="xboard" ;;
        3) S_PANEL_TYPE="v2board" ;;
        4) S_PANEL_TYPE="xiaov2board" ;;
        *) S_PANEL_TYPE="sspanel-uim" ;;
    esac
    echo ""

    while true; do
        read -p "面板地址 (如 https://example.com): " S_PANEL_URL
        if [ -n "${S_PANEL_URL}" ]; then break; fi
        echo -e "${RED}面板地址不能为空${NC}"
    done

    while true; do
        read -p "通信密钥: " S_PANEL_KEY
        if [ -n "${S_PANEL_KEY}" ]; then break; fi
        echo -e "${RED}通信密钥不能为空${NC}"
    done

    while true; do
        read -p "节点 ID (多个用逗号分隔，如 363,364):  " S_NODE_ID
        if [ -n "${S_NODE_ID}" ]; then
            # 验证格式：纯数字或逗号分隔的数字
            VALID=true
            IFS=',' read -ra IDS <<< "${S_NODE_ID}"
            for id in "${IDS[@]}"; do
                id=$(echo "${id}" | xargs)  # trim
                case "${id}" in
                    *[!0-9]*|'') VALID=false ;;
                esac
            done
            if [ "${VALID}" = true ]; then break; fi
            echo -e "${RED}节点 ID 格式错误，请输入数字或逗号分隔的数字（如 363 或 363,364）${NC}"
            continue
        fi
        echo -e "${RED}节点 ID 不能为空${NC}"
    done

    echo ""
    echo -e "${CYAN}---- 授权配置 ----${NC}"
    echo ""
    while true; do
        read -p "授权码 (heki_key): " S_LICENSE_KEY
        if [ -n "${S_LICENSE_KEY}" ]; then break; fi
        echo -e "${RED}授权码不能为空，请联系管理员获取${NC}"
    done

    # 统一写 node_id（程序自动识别单个或逗号分隔的多个）
    cat > "${CONFIG_FILE}" << CFGEOF
# Heki 配置文件
# 协议类型、监听端口、加密方式等全部从面板自动获取
# 多节点用逗号分隔，如 node_id=363,356,337
type=${S_PANEL_TYPE}
panel_url=${S_PANEL_URL}
panel_key=${S_PANEL_KEY}
node_id=${S_NODE_ID}
heki_key=${S_LICENSE_KEY}
CFGEOF

    # ---- 检测节点协议类型，按需配置证书/Reality ----
    echo ""
    echo -e "${CYAN}正在检测节点协议类型...${NC}"
    NEED_CERT=false
    NEED_REALITY=false
    DETECT_OUTPUT=""
    if [ -f "${BIN_PATH}" ]; then
        DETECT_OUTPUT=$("${BIN_PATH}" detect -c "${CONFIG_FILE}" 2>/dev/null)
    fi

    if [ -n "${DETECT_OUTPUT}" ]; then
        echo ""
        echo -e "${CYAN}节点检测结果:${NC}"
        while IFS='|' read -r D_NID D_TYPE D_TLS D_EXTRA; do
            case "${D_TYPE}" in
                ss)       TYPE_LABEL="Shadowsocks" ;;
                ssr)      TYPE_LABEL="ShadowsocksR" ;;
                vmess)    TYPE_LABEL="VMess" ;;
                anytls)   TYPE_LABEL="AnyTLS" ;;
                vless)    TYPE_LABEL="VLESS" ;;
                trojan)   TYPE_LABEL="Trojan" ;;
                hysteria) TYPE_LABEL="Hysteria2" ;;
                naive)    TYPE_LABEL="Naive" ;;
                mieru)    TYPE_LABEL="Mieru" ;;
                *)        TYPE_LABEL="${D_TYPE}" ;;
            esac
            TLS_LABEL=""
            case "${D_TLS}" in
                tls)     TLS_LABEL=" + TLS" ;;
                reality) TLS_LABEL=" + Reality" ;;
            esac
            echo -e "  Node ${D_NID}: ${GREEN}${TYPE_LABEL}${TLS_LABEL}${NC} (${D_EXTRA})"

            # 判断是否需要证书或 Reality
            # AnyTLS/Hysteria2: 面板有域名(sni=xxx)时程序会自动申请证书，无需手动配
            HAS_SNI=false
            echo "${D_EXTRA}" | grep -q "sni=" && HAS_SNI=true

            case "${D_TLS}" in
                tls)
                    if [ "${D_TYPE}" = "anytls" ] || [ "${D_TYPE}" = "hysteria" ]; then
                        # 面板有域名 → 程序自动申请，不需要手动配
                        if ${HAS_SNI}; then
                            AUTO_DOMAIN=$(echo "${D_EXTRA}" | sed 's/.*sni=//;s/,.*//')
                            echo -e "    ${YELLOW}→ 域名 ${AUTO_DOMAIN} 将在启动时自动申请证书${NC}"
                        else
                            # 面板没域名，需要手动配
                            NEED_CERT=true
                        fi
                    else
                        NEED_CERT=true
                    fi
                    ;;
                reality) NEED_REALITY=true ;;
            esac
        done <<< "${DETECT_OUTPUT}"
    else
        echo -e "${YELLOW}协议检测失败（面板可能无法连接），将显示所有配置选项${NC}"
        NEED_CERT=true
        NEED_REALITY=true
    fi

    # 证书配置（仅在需要时显示）
    if ${NEED_CERT}; then
        echo ""
        echo -e "${CYAN}---- 证书配置（TLS 节点需要）----${NC}"
        echo -e "  ${GREEN}1.${NC} 手动指定证书路径"
        echo -e "  ${GREEN}2.${NC} HTTP 验证自动申请（需要 80 端口）"
        echo -e "  ${GREEN}3.${NC} DNS 验证自动申请"
        echo -e "  ${GREEN}0.${NC} 跳过（稍后用 heki cert 配置）"
        echo ""
        read -p "证书配置方式 [0]: " CERT_CHOICE
        CERT_CHOICE=${CERT_CHOICE:-0}

        case ${CERT_CHOICE} in
            1)
                read -p "证书文件路径 (fullchain.pem): " S_CERT_FILE
                read -p "私钥文件路径 (private.key): " S_KEY_FILE
                if [ -n "${S_CERT_FILE}" ] && [ -n "${S_KEY_FILE}" ]; then
                    cat >> "${CONFIG_FILE}" << CERTEOF

# TLS 证书（手动指定）
cert_file=${S_CERT_FILE}
key_file=${S_KEY_FILE}
CERTEOF
                    echo -e "${GREEN}证书路径已配置${NC}"
                fi
                ;;
            2)
                read -p "证书域名: " S_CERT_DOMAIN
                if [ -n "${S_CERT_DOMAIN}" ]; then
                    read -p "密钥类型 (留空=RSA, ec-256, ec-384) [ec-256]: " S_KEY_LEN
                    S_KEY_LEN=${S_KEY_LEN:-ec-256}
                    cat >> "${CONFIG_FILE}" << CERTEOF

# 自动证书申请（HTTP 验证，需要 80 端口）
cert_domain=${S_CERT_DOMAIN}
cert_mode=http
cert_key_length=${S_KEY_LEN}
CERTEOF
                    echo -e "${GREEN}HTTP 自动证书已配置，域名: ${S_CERT_DOMAIN}${NC}"
                fi
                ;;
            3)
                read -p "证书域名: " S_CERT_DOMAIN
                if [ -n "${S_CERT_DOMAIN}" ]; then
                    read -p "密钥类型 (留空=RSA, ec-256, ec-384) [ec-256]: " S_KEY_LEN
                    S_KEY_LEN=${S_KEY_LEN:-ec-256}
                    echo ""
                    echo -e "${CYAN}常见 DNS 服务商:${NC}"
                    echo "  dns_cf  - Cloudflare"
                    echo "  dns_dp  - DNSPod"
                    echo "  dns_ali - 阿里云"
                    echo "  dns_aws - AWS Route53"
                    echo "  完整列表: https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
                    echo ""
                    read -p "DNS 服务商代码: " S_DNS_PROVIDER
                    if [ -z "${S_DNS_PROVIDER}" ]; then
                        echo -e "${RED}DNS 服务商不能为空${NC}"
                    else
                        cat >> "${CONFIG_FILE}" << CERTEOF

# 自动证书申请（DNS 验证）
cert_domain=${S_CERT_DOMAIN}
cert_mode=dns
cert_key_length=${S_KEY_LEN}
dns_provider=${S_DNS_PROVIDER}
CERTEOF
                        echo -e "${YELLOW}请输入 DNS 环境变量（每行一个，格式: KEY=VALUE，空行结束）${NC}"
                        echo -e "${YELLOW}例如 Cloudflare: CF_Email=xxx@xx.com 然后 CF_Key=xxxxx${NC}"
                        while true; do
                            read -p "  > " DNS_LINE
                            [ -z "${DNS_LINE}" ] && break
                            echo "${DNS_LINE}" >> "${CONFIG_FILE}"
                        done
                        echo -e "${GREEN}DNS 自动证书已配置${NC}"
                    fi
                fi
                ;;
            0|"")
                echo -e "${YELLOW}跳过证书配置${NC}"
                ;;
        esac
    fi

    # Reality 配置（仅在需要时显示）
    if ${NEED_REALITY}; then
        echo ""
        echo -e "${CYAN}---- VLESS Reality 配置 ----${NC}"
        echo -e "  ${GREEN}1.${NC} 自动生成 x25519 密钥对（推荐）"
        echo -e "  ${GREEN}2.${NC} 手动输入已有私钥"
        echo -e "  ${GREEN}0.${NC} 跳过（稍后用 heki reality gen 配置）"
        echo ""
        read -p "Reality 配置方式 [0]: " REALITY_CHOICE
        REALITY_CHOICE=${REALITY_CHOICE:-0}

        case ${REALITY_CHOICE} in
            1)
                _setup_reality_auto
                ;;
            2)
                _setup_reality_manual
                ;;
            0|"")
                echo -e "${YELLOW}跳过 Reality 配置${NC}"
                ;;
        esac
    fi

    echo ""
    echo -e "${GREEN}配置完成: ${CONFIG_FILE}${NC}"
    echo ""
    echo -e "  面板类型: ${GREEN}${S_PANEL_TYPE}${NC}"
    echo -e "  面板地址: ${GREEN}${S_PANEL_URL}${NC}"
    echo -e "  节点 ID:  ${GREEN}${S_NODE_ID}${NC}"
    echo ""

    if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        read -p "检测到服务正在运行，是否重启使配置生效？(y/N): " do_rs
        if [ "${do_rs}" = "y" ] || [ "${do_rs}" = "Y" ]; then
            do_restart
        else
            echo -e "${YELLOW}请手动重启: heki restart${NC}"
        fi
    else
        echo -e "${GREEN}启动服务...${NC}"
        systemctl start ${SERVICE_NAME}
        sleep 1
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            echo -e "${GREEN}Heki 启动成功${NC}"
        else
            echo -e "${RED}启动失败，请查看日志: heki log${NC}"
        fi
    fi
}

do_modify() {
    check_root
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在，请先运行: heki setup${NC}"
        return
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       Heki 修改配置                 ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "${GREEN}当前配置:${NC}"
    echo "----------------------------------------"
    cat "${CONFIG_FILE}"
    echo "----------------------------------------"
    echo ""
    echo -e "${CYAN}可修改项（直接回车跳过不修改）:${NC}"
    echo ""

    # 面板配置
    echo -e "${CYAN}---- 面板对接 ----${NC}"
    CUR_PANEL_TYPE=$(grep "^type=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
    CUR_PANEL_URL=$(grep "^panel_url=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
    CUR_NODE_ID=$(grep "^node_id=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)

    if [ -z "${CUR_PANEL_TYPE}" ]; then CUR_PANEL_TYPE="sspanel-uim(默认)"; fi
    echo -e "  面板类型: ${CUR_PANEL_TYPE} (1=sspanel-uim 2=xboard 3=v2board 4=xiaov2board)"
    read -p "面板类型 [直接回车跳过]: " NEW_PANEL_TYPE_CHOICE
    if [ -n "${NEW_PANEL_TYPE_CHOICE}" ]; then
        case ${NEW_PANEL_TYPE_CHOICE} in
            1) NEW_PANEL_TYPE="sspanel-uim" ;;
            2) NEW_PANEL_TYPE="xboard" ;;
            3) NEW_PANEL_TYPE="v2board" ;;
            4) NEW_PANEL_TYPE="xiaov2board" ;;
            sspanel-uim|xboard|v2board|xiaov2board) NEW_PANEL_TYPE="${NEW_PANEL_TYPE_CHOICE}" ;;
            *) echo -e "${RED}无效选项，跳过${NC}"; NEW_PANEL_TYPE="" ;;
        esac
        if [ -n "${NEW_PANEL_TYPE}" ]; then
            if grep -q "^type=" "${CONFIG_FILE}" 2>/dev/null; then
                sed -i "s|^type=.*|type=${NEW_PANEL_TYPE}|" "${CONFIG_FILE}"
            else
                # 在 panel_url 之前插入 type=
                sed -i "/^panel_url=/i type=${NEW_PANEL_TYPE}" "${CONFIG_FILE}"
            fi
            echo -e "${GREEN}  已更新 type = ${NEW_PANEL_TYPE}${NC}"
        fi
    fi

    read -p "面板地址 [${CUR_PANEL_URL}]: " NEW_PANEL_URL
    if [ -n "${NEW_PANEL_URL}" ]; then
        sed -i "s|^panel_url=.*|panel_url=${NEW_PANEL_URL}|" "${CONFIG_FILE}"
        echo -e "${GREEN}  已更新 panel_url${NC}"
    fi

    read -p "通信密钥 [不显示，直接回车跳过]: " NEW_PANEL_KEY
    if [ -n "${NEW_PANEL_KEY}" ]; then
        sed -i "s|^panel_key=.*|panel_key=${NEW_PANEL_KEY}|" "${CONFIG_FILE}"
        echo -e "${GREEN}  已更新 panel_key${NC}"
    fi

    read -p "节点 ID [${CUR_NODE_ID}] (多个用逗号分隔，如 363,356,337): " NEW_NODE_ID
    if [ -n "${NEW_NODE_ID}" ]; then
        sed -i "s|^node_id=.*|node_id=${NEW_NODE_ID}|" "${CONFIG_FILE}"
        echo -e "${GREEN}  已更新 node_id = ${NEW_NODE_ID}${NC}"
    fi

    # 授权码
    CUR_LICENSE_KEY=$(grep "^heki_key=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
    if [ -z "${CUR_LICENSE_KEY}" ]; then CUR_LICENSE_KEY="未设置"; fi
    read -p "授权码 [${CUR_LICENSE_KEY}]: " NEW_LICENSE_KEY
    if [ -n "${NEW_LICENSE_KEY}" ]; then
        if grep -q "^heki_key=" "${CONFIG_FILE}" 2>/dev/null; then
            sed -i "s|^heki_key=.*|heki_key=${NEW_LICENSE_KEY}|" "${CONFIG_FILE}"
        else
            echo "heki_key=${NEW_LICENSE_KEY}" >> "${CONFIG_FILE}"
        fi
        echo -e "${GREEN}  已更新 heki_key${NC}"
    fi

    # 可选高级配置
    echo ""
    echo -e "${CYAN}---- 高级配置（通常不需要修改）----${NC}"

    # proxy_protocol
    CUR_PP=$(grep "^proxy_protocol=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2)
    if [ -z "${CUR_PP}" ]; then CUR_PP="未设置"; fi
    read -p "Proxy Protocol [${CUR_PP}] (true/false): " NEW_PP
    if [ -n "${NEW_PP}" ]; then
        if grep -q "^proxy_protocol=" "${CONFIG_FILE}" 2>/dev/null; then
            sed -i "s|^proxy_protocol=.*|proxy_protocol=${NEW_PP}|" "${CONFIG_FILE}"
        else
            echo "proxy_protocol=${NEW_PP}" >> "${CONFIG_FILE}"
        fi
        echo -e "${GREEN}  已更新 proxy_protocol${NC}"
    fi

    # force_proxy_protocol
    CUR_FPP=$(grep "^force_proxy_protocol=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2)
    if [ -n "${CUR_FPP}" ] || [ "${NEW_PP}" = "true" ]; then
        if [ -z "${CUR_FPP}" ]; then CUR_FPP="未设置"; fi
        read -p "强制 Proxy Protocol [${CUR_FPP}] (true/false): " NEW_FPP
        if [ -n "${NEW_FPP}" ]; then
            if grep -q "^force_proxy_protocol=" "${CONFIG_FILE}" 2>/dev/null; then
                sed -i "s|^force_proxy_protocol=.*|force_proxy_protocol=${NEW_FPP}|" "${CONFIG_FILE}"
            else
                echo "force_proxy_protocol=${NEW_FPP}" >> "${CONFIG_FILE}"
            fi
            echo -e "${GREEN}  已更新 force_proxy_protocol${NC}"
        fi
    fi

    # check_interval
    CUR_SYNC=$(grep "^check_interval=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2)
    if [ -z "${CUR_SYNC}" ]; then CUR_SYNC="60(默认)"; fi
    read -p "用户同步间隔 秒 [${CUR_SYNC}]: " NEW_SYNC
    if [ -n "${NEW_SYNC}" ]; then
        if grep -q "^check_interval=" "${CONFIG_FILE}" 2>/dev/null; then
            sed -i "s|^check_interval=.*|check_interval=${NEW_SYNC}|" "${CONFIG_FILE}"
        else
            echo "check_interval=${NEW_SYNC}" >> "${CONFIG_FILE}"
        fi
        echo -e "${GREEN}  已更新 check_interval${NC}"
    fi

    # submit_interval
    CUR_REPORT=$(grep "^submit_interval=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2)
    if [ -z "${CUR_REPORT}" ]; then CUR_REPORT="120(默认)"; fi
    read -p "流量上报间隔 秒 [${CUR_REPORT}]: " NEW_REPORT
    if [ -n "${NEW_REPORT}" ]; then
        if grep -q "^submit_interval=" "${CONFIG_FILE}" 2>/dev/null; then
            sed -i "s|^submit_interval=.*|submit_interval=${NEW_REPORT}|" "${CONFIG_FILE}"
        else
            echo "submit_interval=${NEW_REPORT}" >> "${CONFIG_FILE}"
        fi
        echo -e "${GREEN}  已更新 submit_interval${NC}"
    fi

    # 证书配置
    echo ""
    echo -e "${CYAN}---- 证书配置 ----${NC}"
    CUR_CERT_DOMAIN=$(grep "^cert_domain=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
    CUR_CERT_MODE=$(grep "^cert_mode=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
    CUR_CERT_FILE=$(grep "^cert_file=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)

    if [ -n "${CUR_CERT_DOMAIN}" ]; then
        echo -e "  当前: 自动申请 (${CUR_CERT_MODE}) 域名=${CUR_CERT_DOMAIN}"
    elif [ -n "${CUR_CERT_FILE}" ]; then
        echo -e "  当前: 手动证书 ${CUR_CERT_FILE}"
    else
        echo -e "  当前: 未配置"
    fi
    echo -e "  输入 'auto' 配置自动申请，'manual' 配置手动路径，直接回车跳过"
    read -p "  证书配置: " CERT_ACTION

    case "${CERT_ACTION}" in
        auto)
            read -p "  证书域名: " NEW_CERT_DOMAIN
            if [ -n "${NEW_CERT_DOMAIN}" ]; then
                read -p "  验证方式 (http/dns) [http]: " NEW_CERT_MODE
                NEW_CERT_MODE=${NEW_CERT_MODE:-http}
                read -p "  密钥类型 (留空=RSA, ec-256, ec-384) [ec-256]: " NEW_KEY_LEN
                NEW_KEY_LEN=${NEW_KEY_LEN:-ec-256}

                # 删除旧的证书配置
                sed -i '/^cert_domain=/d' "${CONFIG_FILE}"
                sed -i '/^cert_mode=/d' "${CONFIG_FILE}"
                sed -i '/^cert_key_length=/d' "${CONFIG_FILE}"
                sed -i '/^dns_provider=/d' "${CONFIG_FILE}"
                sed -i '/^cert_file=/d' "${CONFIG_FILE}"
                sed -i '/^key_file=/d' "${CONFIG_FILE}"

                if [ "${NEW_CERT_MODE}" = "dns" ]; then
                    read -p "  DNS 服务商 (dns_cf/dns_dp/dns_ali): " NEW_DNS_PROVIDER
                    cat >> "${CONFIG_FILE}" << CERTEOF

# 自动证书（DNS 验证）
cert_domain=${NEW_CERT_DOMAIN}
cert_mode=dns
cert_key_length=${NEW_KEY_LEN}
dns_provider=${NEW_DNS_PROVIDER}
CERTEOF
                    echo -e "${YELLOW}  请输入 DNS 环境变量（每行一个，空行结束）${NC}"
                    while true; do
                        read -p "    > " DNS_LINE
                        [ -z "${DNS_LINE}" ] && break
                        echo "${DNS_LINE}" >> "${CONFIG_FILE}"
                    done
                else
                    cat >> "${CONFIG_FILE}" << CERTEOF

# 自动证书（HTTP 验证）
cert_domain=${NEW_CERT_DOMAIN}
cert_mode=http
cert_key_length=${NEW_KEY_LEN}
CERTEOF
                fi
                echo -e "${GREEN}  证书配置已更新${NC}"
            fi
            ;;
        manual)
            read -p "  证书文件路径: " NEW_CERT_FILE
            read -p "  私钥文件路径: " NEW_KEY_FILE
            if [ -n "${NEW_CERT_FILE}" ] && [ -n "${NEW_KEY_FILE}" ]; then
                # 删除旧的证书配置
                sed -i '/^cert_domain=/d' "${CONFIG_FILE}"
                sed -i '/^cert_mode=/d' "${CONFIG_FILE}"
                sed -i '/^cert_file=/d' "${CONFIG_FILE}"
                sed -i '/^key_file=/d' "${CONFIG_FILE}"

                cat >> "${CONFIG_FILE}" << CERTEOF

# TLS 证书（手动指定）
cert_file=${NEW_CERT_FILE}
key_file=${NEW_KEY_FILE}
CERTEOF
                echo -e "${GREEN}  证书路径已更新${NC}"
            fi
            ;;
    esac

    echo ""
    echo -e "${GREEN}修改完成${NC}"
    echo ""

    if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        read -p "是否重启使配置生效？(y/N): " do_rs
        if [ "${do_rs}" = "y" ] || [ "${do_rs}" = "Y" ]; then
            do_restart
        else
            echo -e "${YELLOW}请手动重启: heki restart${NC}"
        fi
    fi
}

do_version() {
    echo "Heki v$(get_version)"
}

# 辅助函数：确保 acme.sh 已安装
_ensure_acme_installed() {
    local ACME_BIN="/root/.acme.sh/acme.sh"
    if [ -f "${ACME_BIN}" ]; then
        return 0
    fi

    echo -e "${YELLOW}正在安装 acme.sh ...${NC}"
    export HOME=/root
    curl -s https://get.acme.sh | sh -s email=cert-heki@gmail.com
    if [ $? -ne 0 ] || [ ! -f "${ACME_BIN}" ]; then
        echo -e "${RED}acme.sh 安装失败${NC}"
        return 1
    fi
    # 设置默认 CA 为 Let's Encrypt
    HOME=/root "${ACME_BIN}" --set-default-ca --server letsencrypt >/dev/null 2>&1
    echo -e "${GREEN}acme.sh 安装成功${NC}"
    return 0
}

# 辅助函数：直接在脚本中申请证书，实时显示 acme.sh 输出
# 参数: domain key_length mode dns_provider dns_env_str
# dns_env_str 格式: "CF_Email=xxx CF_Key=yyy"
_issue_cert_realtime() {
    local DOMAIN="$1"
    local KEY_LEN="$2"
    local MODE="$3"
    local DNS_PROVIDER="$4"
    local DNS_ENV_STR="$5"

    local ACME_BIN="/root/.acme.sh/acme.sh"
    local CERT_DIR="/etc/heki/certs/${DOMAIN}"
    local CERT_FILE="${CERT_DIR}/fullchain.pem"
    local KEY_FILE="${CERT_DIR}/private.key"

    # 检查证书是否已存在且有效
    if [ -f "${CERT_FILE}" ] && [ -f "${KEY_FILE}" ]; then
        local EXPIRY DAYS_LEFT
        EXPIRY=$(openssl x509 -enddate -noout -in "${CERT_FILE}" 2>/dev/null | sed 's/notAfter=//')
        DAYS_LEFT=$(cert_days_left "${CERT_FILE}")
        if [ -n "${EXPIRY}" ]; then
            echo -e "${GREEN}证书已存在: ${CERT_FILE}${NC}"
            echo -e "  过期时间: $(format_cert_date "${EXPIRY}")${DAYS_LEFT:+ (剩余 ${DAYS_LEFT} 天)}"
            echo ""
            read -p "是否强制重新申请？(y/N): " FORCE_ISSUE
            if [ "${FORCE_ISSUE}" != "y" ] && [ "${FORCE_ISSUE}" != "Y" ]; then
                echo -e "${GREEN}使用现有证书${NC}"
                _ask_restart
                return
            fi
        fi
    fi

    # 安装 acme.sh
    if ! _ensure_acme_installed; then
        echo -e "${RED}无法继续，请手动安装 acme.sh${NC}"
        return
    fi

    # 创建证书目录
    mkdir -p "${CERT_DIR}"

    # 设置默认 CA 和注册账号
    echo -e "${CYAN}设置 Let's Encrypt 为默认 CA ...${NC}"
    HOME=/root "${ACME_BIN}" --set-default-ca --server letsencrypt >/dev/null 2>&1
    HOME=/root "${ACME_BIN}" --register-account -m cert-heki@gmail.com --server letsencrypt >/dev/null 2>&1

    # HTTP 模式：检查 80 端口
    if [ "${MODE}" = "http" ]; then
        local PORT80_PID
        PORT80_PID=$(ss -tlnp 2>/dev/null | grep -E ':80\b' | head -1)
        if [ -n "${PORT80_PID}" ]; then
            echo -e "${YELLOW}检测到 80 端口被占用:${NC}"
            echo "  ${PORT80_PID}"
            # 如果是 heki 占用，临时停止
            if echo "${PORT80_PID}" | grep -q "heki"; then
                echo -e "${YELLOW}临时停止 heki 以释放 80 端口...${NC}"
                systemctl stop heki 2>/dev/null
                sleep 1
            else
                echo -e "${YELLOW}请确保 80 端口空闲，或使用 DNS 验证方式${NC}"
                read -p "继续申请？(y/N): " CONT
                if [ "${CONT}" != "y" ] && [ "${CONT}" != "Y" ]; then
                    return
                fi
            fi
        fi
    fi

    # 构建 acme.sh --issue 命令
    local ISSUE_CMD="HOME=/root ${ACME_BIN} --issue -d ${DOMAIN} --server letsencrypt"

    if [ -n "${KEY_LEN}" ] && [ "${KEY_LEN}" != "RSA" ]; then
        ISSUE_CMD="${ISSUE_CMD} --keylength ${KEY_LEN}"
    fi

    case "${MODE}" in
        http)
            ISSUE_CMD="${ISSUE_CMD} --standalone"
            ;;
        dns)
            ISSUE_CMD="${ISSUE_CMD} --dns ${DNS_PROVIDER}"
            ;;
    esac

    ISSUE_CMD="${ISSUE_CMD} --force"

    # 导出 DNS 环境变量
    if [ -n "${DNS_ENV_STR}" ]; then
        for pair in ${DNS_ENV_STR}; do
            export "${pair}"
        done
    fi

    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  正在申请证书: ${DOMAIN}${NC}"
    echo -e "${CYAN}  验证方式: ${MODE}${NC}"
    echo -e "${CYAN}  密钥类型: ${KEY_LEN}${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # 执行申请，实时显示输出
    eval "${ISSUE_CMD}" 2>&1
    local ISSUE_EXIT=$?

    echo ""

    if [ ${ISSUE_EXIT} -ne 0 ]; then
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}  证书申请失败!${NC}"
        echo -e "${RED}========================================${NC}"
        echo ""
        echo -e "${YELLOW}常见原因:${NC}"
        if [ "${MODE}" = "http" ]; then
            echo "  - 域名未解析到本机 IP"
            echo "  - 80 端口被占用"
            echo "  - 防火墙阻止了 80 端口"
        else
            echo "  - DNS API 凭据错误"
            echo "  - DNS 服务商代码不正确"
            echo "  - DNS 传播延迟（可重试）"
        fi
        echo ""
        echo -e "  查看详细日志: ${CYAN}cat /root/.acme.sh/acme.sh.log${NC}"
        return
    fi

    # 安装证书到指定目录
    echo -e "${CYAN}安装证书到 ${CERT_DIR} ...${NC}"
    local INSTALL_CMD="HOME=/root ${ACME_BIN} --install-cert -d ${DOMAIN} --fullchain-file ${CERT_FILE} --key-file ${KEY_FILE}"
    if echo "${KEY_LEN}" | grep -q "^ec-"; then
        INSTALL_CMD="${INSTALL_CMD} --ecc"
    fi

    eval "${INSTALL_CMD}" 2>&1
    local INSTALL_EXIT=$?

    if [ ${INSTALL_EXIT} -ne 0 ]; then
        echo -e "${RED}证书安装失败${NC}"
        return
    fi

    # 验证证书
    echo ""
    if [ -f "${CERT_FILE}" ] && [ -f "${KEY_FILE}" ]; then
        local SUBJECT ISSUER EXPIRY
        SUBJECT=$(openssl x509 -in "${CERT_FILE}" -noout -subject 2>/dev/null | sed 's/subject=//')
        ISSUER=$(openssl x509 -in "${CERT_FILE}" -noout -issuer 2>/dev/null | sed 's/issuer=//')
        EXPIRY=$(openssl x509 -in "${CERT_FILE}" -noout -enddate 2>/dev/null | sed 's/notAfter=//')

        echo -e "${GREEN}========================================${NC}"
        echo -e "${GREEN}  证书申请成功!${NC}"
        echo -e "${GREEN}========================================${NC}"
        echo ""
        echo -e "  域名:     ${GREEN}${DOMAIN}${NC}"
        echo -e "  颁发者:   ${ISSUER}"
        echo -e "  过期时间: $(format_cert_date "${EXPIRY}")"
        echo -e "  证书文件: ${CERT_FILE}"
        echo -e "  私钥文件: ${KEY_FILE}"
    else
        echo -e "${RED}证书文件未找到，申请可能失败${NC}"
        return
    fi

    _ask_restart
}

# 辅助函数：删除配置文件中旧的证书配置
_remove_old_cert_config() {
    sed -i '/^# 自动证书/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^cert_domain=/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^cert_mode=/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^cert_key_length=/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^dns_provider=/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^DNS_/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^CF_/d' "${CONFIG_FILE}" 2>/dev/null
}

# ============================================================
# Reality 配置辅助函数
# ============================================================

# 自动生成 x25519 密钥对并写入配置
_setup_reality_auto() {
    if [ ! -f "${BIN_PATH}" ]; then
        echo -e "${RED}Heki 未安装，无法生成密钥${NC}"
        return
    fi

    echo ""
    echo -e "${CYAN}正在生成 x25519 密钥对...${NC}"
    local KEY_OUTPUT
    KEY_OUTPUT=$("${BIN_PATH}" x25519 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "${RED}生成失败: ${KEY_OUTPUT}${NC}"
        return
    fi

    local PRIV_KEY
    local PUB_KEY
    PRIV_KEY=$(echo "${KEY_OUTPUT}" | grep "Private key:" | awk '{print $3}')
    PUB_KEY=$(echo "${KEY_OUTPUT}" | grep "Public key:" | awk '{print $3}')

    if [ -z "${PRIV_KEY}" ] || [ -z "${PUB_KEY}" ]; then
        echo -e "${RED}解析密钥失败${NC}"
        return
    fi

    # 写入配置文件（先删除旧的）
    _remove_old_reality_config
    cat >> "${CONFIG_FILE}" << REALITYEOF

# VLESS Reality 私钥（自动生成）
reality_private_key=${PRIV_KEY}
REALITYEOF

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Reality 密钥对已生成${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "  私钥（已自动写入配置）:"
    echo -e "    ${GREEN}${PRIV_KEY}${NC}"
    echo ""
    echo -e "  公钥（${RED}请复制到面板 reality_public_key${NC}）:"
    echo -e "    ${GREEN}${PUB_KEY}${NC}"
    echo ""
    echo -e "${YELLOW}面板 custom_config 示例:${NC}"
    echo -e '  {"tls":2,"flow":"xtls-rprx-vision","network":"tcp",'
    echo -e "   \"reality_public_key\":\"${PUB_KEY}\","
    echo -e '   "reality_short_id":"abcd1234",'
    echo -e '   "reality_server_name":"www.microsoft.com",'
    echo -e '   "offset_port_node":443}'
    echo ""
}

# 手动输入 Reality 私钥
_setup_reality_manual() {
    echo ""
    read -p "请输入 x25519 私钥 (base64): " INPUT_KEY
    if [ -z "${INPUT_KEY}" ]; then
        echo -e "${RED}私钥不能为空${NC}"
        return
    fi

    _remove_old_reality_config
    cat >> "${CONFIG_FILE}" << REALITYEOF

# VLESS Reality 私钥（手动配置）
reality_private_key=${INPUT_KEY}
REALITYEOF

    echo -e "${GREEN}Reality 私钥已写入配置${NC}"
}

# 删除旧的 Reality 配置
_remove_old_reality_config() {
    sed -i '/^# VLESS Reality/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^reality_private_key=/d' "${CONFIG_FILE}" 2>/dev/null
    sed -i '/^reality_dest=/d' "${CONFIG_FILE}" 2>/dev/null
}

# do_reality 独立命令：配置/查看/生成 Reality 密钥
do_reality() {
    check_root
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在，请先运行: heki setup${NC}"
        return
    fi

    local ACTION="$1"

    case "${ACTION}" in
        gen|generate|new)
            _setup_reality_auto
            _ask_restart
            ;;
        set)
            _setup_reality_manual
            _ask_restart
            ;;
        show|"")
            local CUR_KEY
            CUR_KEY=$(grep "^reality_private_key=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
            if [ -n "${CUR_KEY}" ]; then
                echo -e "${GREEN}当前 Reality 私钥: ${CUR_KEY}${NC}"
                # 用 heki 程序计算对应公钥
                if [ -f "${BIN_PATH}" ]; then
                    echo ""
                    echo -e "${YELLOW}如需重新生成密钥对: heki reality gen${NC}"
                fi
            else
                echo -e "${YELLOW}未配置 Reality 私钥${NC}"
                echo ""
                echo "用法:"
                echo "  heki reality gen    自动生成密钥对（推荐）"
                echo "  heki reality set    手动输入私钥"
                echo "  heki reality show   查看当前配置"
            fi
            ;;
        *)
            echo "用法: heki reality [gen|set|show]"
            echo ""
            echo "  heki reality gen    自动生成 x25519 密钥对"
            echo "  heki reality set    手动输入已有私钥"
            echo "  heki reality show   查看当前 Reality 配置"
            ;;
    esac
}

# 辅助函数：询问是否重启
_ask_restart() {
    echo ""
    if systemctl is-active --quiet ${SERVICE_NAME} 2>/dev/null; then
        echo -e "${YELLOW}配置已修改，必须重启服务才能生效！${NC}"
        read -p "是否立即重启？(Y/n): " do_rs
        if [ "${do_rs}" != "n" ] && [ "${do_rs}" != "N" ]; then
            do_restart
        else
            echo -e "${RED}警告: 配置未生效，请稍后手动执行: heki restart${NC}"
        fi
    else
        read -p "是否启动服务？(Y/n): " do_st
        if [ "${do_st}" != "n" ] && [ "${do_st}" != "N" ]; then
            do_start
        fi
    fi
}

do_cert() {
    check_root
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       Heki 证书管理                 ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    # 显示当前证书状态
    if [ -f "${CONFIG_FILE}" ]; then
        CUR_CERT_DOMAIN=$(grep "^cert_domain=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
        CUR_CERT_MODE=$(grep "^cert_mode=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
        CUR_CERT_FILE=$(grep "^cert_file=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
        CUR_ANYTLS_CERT=$(grep "^anytls_cert_file=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)

        if [ -n "${CUR_CERT_DOMAIN}" ]; then
            echo -e "  当前: ${GREEN}自动申请 (${CUR_CERT_MODE})${NC} 域名=${CUR_CERT_DOMAIN}"
        elif [ -n "${CUR_CERT_FILE}" ]; then
            echo -e "  当前: ${GREEN}手动证书${NC} ${CUR_CERT_FILE}"
        elif [ -n "${CUR_ANYTLS_CERT}" ]; then
            echo -e "  当前: ${GREEN}手动证书 (AnyTLS)${NC} ${CUR_ANYTLS_CERT}"
        else
            # 检查是否有从面板自动申请的证书（AnyTLS SNI 自动申请，配置文件里不会写 cert_domain）
            NODES_DIR="${INSTALL_DIR}/nodes"
            AUTO_FOUND=false
            if [ -d "${NODES_DIR}" ]; then
                for nf in "${NODES_DIR}"/node_*.conf; do
                    [ -f "$nf" ] || continue
                    NSNI=$(grep "^anytls_sni=" "$nf" 2>/dev/null | head -1 | cut -d= -f2-)
                    if [ -n "${NSNI}" ] && [ -f "/etc/heki/certs/${NSNI}/fullchain.pem" ]; then
                        echo -e "  当前: ${GREEN}自动申请 (AnyTLS)${NC} 域名=${NSNI}"
                        AUTO_FOUND=true
                        break
                    fi
                done
            fi
            if ! ${AUTO_FOUND}; then
                echo -e "  当前: ${YELLOW}未配置证书${NC}"
            fi
        fi
    else
        echo -e "  ${RED}配置文件不存在，请先运行: heki setup${NC}"
        return
    fi

    # 检查已有证书文件
    if [ -d "/etc/heki/certs" ]; then
        echo ""
        echo -e "  ${CYAN}已有证书:${NC}"
        for d in /etc/heki/certs/*/; do
            [ -d "$d" ] || continue
            domain=$(basename "$d")
            if [ -f "${d}fullchain.pem" ]; then
                expiry_raw=$(openssl x509 -enddate -noout -in "${d}fullchain.pem" 2>/dev/null | sed 's/notAfter=//')
                expiry=$(format_cert_date "${expiry_raw}")
                days_left=$(cert_days_left "${d}fullchain.pem")
                if [ -n "${days_left}" ] && [ "${days_left}" -le 7 ]; then
                    echo -e "    ${domain} → ${RED}${expiry} (剩余 ${days_left} 天，即将过期)${NC}"
                elif [ -n "${days_left}" ] && [ "${days_left}" -le 30 ]; then
                    echo -e "    ${domain} → ${YELLOW}${expiry} (剩余 ${days_left} 天)${NC}"
                else
                    echo -e "    ${domain} → ${GREEN}${expiry}${NC}${days_left:+ (剩余 ${days_left} 天)}"
                fi
            fi
        done
    fi

    echo ""
    echo -e "  ${GREEN}1.${NC} 自动申请证书 - HTTP 验证（需要 80 端口）"
    echo -e "  ${GREEN}2.${NC} 自动申请证书 - DNS 验证（Cloudflare）"
    echo -e "  ${GREEN}3.${NC} 自动申请证书 - DNS 验证（其他服务商）"
    echo -e "  ${GREEN}4.${NC} 手动指定证书路径"
    echo -e "  ${GREEN}5.${NC} 查看证书详情"
    echo -e "  ${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择 [0-5]: " cert_choice

    case ${cert_choice} in
        1)
            read -p "证书域名: " NEW_DOMAIN
            [ -z "${NEW_DOMAIN}" ] && { echo -e "${RED}域名不能为空${NC}"; return; }
            read -p "密钥类型 (留空=RSA, ec-256, ec-384) [ec-256]: " KEY_LEN
            KEY_LEN=${KEY_LEN:-ec-256}

            # 写入配置
            _remove_old_cert_config
            cat >> "${CONFIG_FILE}" << CERTEOF

# 自动证书（HTTP 验证）
cert_domain=${NEW_DOMAIN}
cert_mode=http
cert_key_length=${KEY_LEN}
CERTEOF
            echo -e "${GREEN}已写入证书配置${NC}"
            echo ""

            # 直接在脚本中申请证书，实时显示过程
            _issue_cert_realtime "${NEW_DOMAIN}" "${KEY_LEN}" "http" "" ""
            ;;
        2)
            read -p "证书域名: " NEW_DOMAIN
            [ -z "${NEW_DOMAIN}" ] && { echo -e "${RED}域名不能为空${NC}"; return; }
            read -p "密钥类型 [ec-256]: " KEY_LEN
            KEY_LEN=${KEY_LEN:-ec-256}
            read -p "Cloudflare Email: " CF_EMAIL
            read -p "Cloudflare API Key (Global): " CF_KEY
            [ -z "${CF_EMAIL}" ] || [ -z "${CF_KEY}" ] && { echo -e "${RED}凭据不能为空${NC}"; return; }

            _remove_old_cert_config
            cat >> "${CONFIG_FILE}" << CERTEOF

# 自动证书（DNS-Cloudflare）
cert_domain=${NEW_DOMAIN}
cert_mode=dns
cert_key_length=${KEY_LEN}
dns_provider=dns_cf
CF_Email=${CF_EMAIL}
CF_Key=${CF_KEY}
CERTEOF
            echo -e "${GREEN}已写入证书配置${NC}"
            echo ""

            # 直接在脚本中申请证书，实时显示过程
            _issue_cert_realtime "${NEW_DOMAIN}" "${KEY_LEN}" "dns" "dns_cf" "CF_Email=${CF_EMAIL} CF_Key=${CF_KEY}"
            ;;
        3)
            read -p "证书域名: " NEW_DOMAIN
            [ -z "${NEW_DOMAIN}" ] && { echo -e "${RED}域名不能为空${NC}"; return; }
            read -p "密钥类型 [ec-256]: " KEY_LEN
            KEY_LEN=${KEY_LEN:-ec-256}
            echo ""
            echo -e "${CYAN}常见 DNS 服务商:${NC}"
            echo "  dns_cf  - Cloudflare    dns_dp  - DNSPod"
            echo "  dns_ali - 阿里云        dns_aws - AWS Route53"
            echo "  完整列表: https://github.com/acmesh-official/acme.sh/wiki/dnsapi"
            echo ""
            read -p "DNS 服务商代码: " DNS_PROV
            [ -z "${DNS_PROV}" ] && { echo -e "${RED}不能为空${NC}"; return; }

            # 收集 DNS 环境变量
            echo -e "${YELLOW}请输入 DNS 环境变量（每行一个，格式: KEY=VALUE，空行结束）${NC}"
            DNS_ENV_STR=""
            DNS_ENV_YAML=""
            while true; do
                read -p "  > " DNS_LINE
                [ -z "${DNS_LINE}" ] && break
                DNS_K="${DNS_LINE%%=*}"
                DNS_V="${DNS_LINE#*=}"
                if [ -n "${DNS_ENV_STR}" ]; then
                    DNS_ENV_STR="${DNS_ENV_STR} "
                fi
                DNS_ENV_STR="${DNS_ENV_STR}${DNS_K}=${DNS_V}"
                DNS_ENV_YAML="${DNS_ENV_YAML}${DNS_K}=${DNS_V}\n"
            done

            _remove_old_cert_config
            cat >> "${CONFIG_FILE}" << CERTEOF

# 自动证书（DNS 验证）
cert_domain=${NEW_DOMAIN}
cert_mode=dns
cert_key_length=${KEY_LEN}
dns_provider=${DNS_PROV}
CERTEOF
            # 写入 DNS 环境变量到配置文件
            if [ -n "${DNS_ENV_YAML}" ]; then
                printf "%b" "${DNS_ENV_YAML}" >> "${CONFIG_FILE}"
            fi
            echo -e "${GREEN}已写入证书配置${NC}"
            echo ""

            # 直接在脚本中申请证书，实时显示过程
            _issue_cert_realtime "${NEW_DOMAIN}" "${KEY_LEN}" "dns" "${DNS_PROV}" "${DNS_ENV_STR}"
            ;;
        4)
            read -p "证书文件路径 (fullchain.pem): " CERT_PATH
            read -p "私钥文件路径 (private.key): " KEY_PATH
            if [ -n "${CERT_PATH}" ] && [ -n "${KEY_PATH}" ]; then
                if [ ! -f "${CERT_PATH}" ]; then
                    echo -e "${RED}证书文件不存在: ${CERT_PATH}${NC}"
                    return
                fi
                if [ ! -f "${KEY_PATH}" ]; then
                    echo -e "${RED}私钥文件不存在: ${KEY_PATH}${NC}"
                    return
                fi
                _remove_old_cert_config
                # 删除旧的证书配置
                sed -i '/^cert_file=/d' "${CONFIG_FILE}" 2>/dev/null
                sed -i '/^key_file=/d' "${CONFIG_FILE}" 2>/dev/null
                cat >> "${CONFIG_FILE}" << CERTEOF

# TLS 证书（手动指定）
cert_file=${CERT_PATH}
key_file=${KEY_PATH}
CERTEOF
                echo -e "${GREEN}手动证书已配置${NC}"
                _ask_restart
            fi
            ;;
        5)
            echo ""
            if [ -d "/etc/heki/certs" ]; then
                for d in /etc/heki/certs/*/; do
                    [ -d "$d" ] || continue
                    domain=$(basename "$d")
                    if [ -f "${d}fullchain.pem" ]; then
                        local c_subject c_issuer c_expiry c_start c_days
                        c_subject=$(openssl x509 -in "${d}fullchain.pem" -noout -subject 2>/dev/null | sed 's/subject=//')
                        c_issuer=$(openssl x509 -in "${d}fullchain.pem" -noout -issuer 2>/dev/null | sed 's/issuer=//')
                        c_start=$(openssl x509 -in "${d}fullchain.pem" -noout -startdate 2>/dev/null | sed 's/notBefore=//')
                        c_expiry=$(openssl x509 -in "${d}fullchain.pem" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
                        c_days=$(cert_days_left "${d}fullchain.pem")
                        echo -e "${CYAN}域名: ${domain}${NC}"
                        echo -e "  主体:     ${c_subject}"
                        echo -e "  颁发者:   ${c_issuer}"
                        echo -e "  签发时间: $(format_cert_date "${c_start}")"
                        echo -e "  过期时间: $(format_cert_date "${c_expiry}")${c_days:+ (剩余 ${c_days} 天)}"
                        echo -e "  证书文件: ${d}fullchain.pem"
                        echo -e "  私钥文件: ${d}private.key"
                    else
                        echo -e "${CYAN}域名: ${domain}${NC}"
                        echo "  证书文件不存在"
                    fi
                    echo ""
                done
            else
                echo -e "${YELLOW}没有自动申请的证书${NC}"
            fi
            # 检查手动证书
            if [ -n "${CUR_CERT_FILE}" ] && [ -f "${CUR_CERT_FILE}" ]; then
                local m_issuer m_expiry m_days
                m_issuer=$(openssl x509 -in "${CUR_CERT_FILE}" -noout -issuer 2>/dev/null | sed 's/issuer=//')
                m_expiry=$(openssl x509 -in "${CUR_CERT_FILE}" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
                m_days=$(cert_days_left "${CUR_CERT_FILE}")
                echo -e "${CYAN}手动证书: ${CUR_CERT_FILE}${NC}"
                echo -e "  颁发者:   ${m_issuer}"
                echo -e "  过期时间: $(format_cert_date "${m_expiry}")${m_days:+ (剩余 ${m_days} 天)}"
            fi
            ;;
        0|"") return ;;
    esac
}

do_node() {
    check_root
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在，请先运行: heki setup${NC}"
        return
    fi

    local ACTION="$1"
    local TARGET_ID="$2"

    # 读取当前 node_id
    local CUR_NODE_ID
    CUR_NODE_ID=$(grep "^node_id=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)

    case "${ACTION}" in
        add)
            if [ -z "${TARGET_ID}" ]; then
                read -p "要添加的节点 ID: " TARGET_ID
            fi
            if [ -z "${TARGET_ID}" ]; then
                echo -e "${RED}节点 ID 不能为空${NC}"
                return
            fi
            # 验证是否为数字
            case "${TARGET_ID}" in
                *[!0-9]*|'')
                    echo -e "${RED}节点 ID 必须是数字${NC}"
                    return
                    ;;
            esac
            # 检查是否已存在
            IFS=',' read -ra EXISTING <<< "${CUR_NODE_ID}"
            for eid in "${EXISTING[@]}"; do
                eid=$(echo "${eid}" | xargs)
                if [ "${eid}" = "${TARGET_ID}" ]; then
                    echo -e "${YELLOW}节点 ${TARGET_ID} 已存在，当前: node_id=${CUR_NODE_ID}${NC}"
                    return
                fi
            done
            # 追加
            local NEW_NODE_ID="${CUR_NODE_ID},${TARGET_ID}"
            sed -i "s|^node_id=.*|node_id=${NEW_NODE_ID}|" "${CONFIG_FILE}"
            echo -e "${GREEN}已添加节点 ${TARGET_ID}，当前: node_id=${NEW_NODE_ID}${NC}"

            # 检查是否已配置 Reality 私钥，如果没有则提示
            local HAS_REALITY_KEY
            HAS_REALITY_KEY=$(grep "^reality_private_key=" "${CONFIG_FILE}" 2>/dev/null | head -1 | cut -d= -f2-)
            if [ -z "${HAS_REALITY_KEY}" ]; then
                echo ""
                echo -e "${YELLOW}提示: 如果新节点使用 VLESS Reality，需要配置私钥${NC}"
                read -p "是否现在配置 Reality 私钥？(y/N): " SETUP_REALITY
                if [ "${SETUP_REALITY}" = "y" ] || [ "${SETUP_REALITY}" = "Y" ]; then
                    echo -e "  ${GREEN}1.${NC} 自动生成 x25519 密钥对（推荐）"
                    echo -e "  ${GREEN}2.${NC} 手动输入已有私钥"
                    read -p "选择 [1]: " RC
                    RC=${RC:-1}
                    case ${RC} in
                        1) _setup_reality_auto ;;
                        2) _setup_reality_manual ;;
                    esac
                fi
            fi

            _ask_restart
            ;;
        del|rm|remove)
            if [ -z "${TARGET_ID}" ]; then
                read -p "要删除的节点 ID: " TARGET_ID
            fi
            if [ -z "${TARGET_ID}" ]; then
                echo -e "${RED}节点 ID 不能为空${NC}"
                return
            fi
            # 过滤掉目标 ID
            IFS=',' read -ra EXISTING <<< "${CUR_NODE_ID}"
            local NEW_IDS=()
            local FOUND=false
            for eid in "${EXISTING[@]}"; do
                eid=$(echo "${eid}" | xargs)
                if [ "${eid}" = "${TARGET_ID}" ]; then
                    FOUND=true
                else
                    NEW_IDS+=("${eid}")
                fi
            done
            if ! ${FOUND}; then
                echo -e "${YELLOW}节点 ${TARGET_ID} 不存在，当前: node_id=${CUR_NODE_ID}${NC}"
                return
            fi
            if [ ${#NEW_IDS[@]} -eq 0 ]; then
                echo -e "${RED}不能删除最后一个节点${NC}"
                return
            fi
            local NEW_NODE_ID
            NEW_NODE_ID=$(IFS=','; echo "${NEW_IDS[*]}")
            sed -i "s|^node_id=.*|node_id=${NEW_NODE_ID}|" "${CONFIG_FILE}"
            
            # 删除节点配置文件
            local NODE_CONF="${INSTALL_DIR}/nodes/node_${TARGET_ID}.conf"
            if [ -f "${NODE_CONF}" ]; then
                rm -f "${NODE_CONF}"
                echo -e "${GREEN}已删除节点配置文件: ${NODE_CONF}${NC}"
            fi
            
            echo -e "${GREEN}已删除节点 ${TARGET_ID}，当前: node_id=${NEW_NODE_ID}${NC}"
            echo -e "${YELLOW}注意: 必须重启服务才能生效！${NC}"
            _ask_restart
            ;;
        list|ls|"")
            echo -e "${CYAN}当前节点配置: node_id=${CUR_NODE_ID}${NC}"
            
            # 解析配置中的节点ID列表
            IFS=',' read -ra CONFIGURED_IDS <<< "${CUR_NODE_ID}"
            declare -A CONFIGURED_MAP
            for cid in "${CONFIGURED_IDS[@]}"; do
                cid=$(echo "${cid}" | xargs)
                CONFIGURED_MAP["${cid}"]=1
            done
            
            # 显示运行中的节点详情
            NODES_DIR="${INSTALL_DIR}/nodes"
            if [ -d "${NODES_DIR}" ]; then
                NODE_FILES=$(ls "${NODES_DIR}"/node_*.conf 2>/dev/null)
                if [ -n "${NODE_FILES}" ]; then
                    echo ""
                    echo -e "${CYAN}节点详情:${NC}"
                    local HAS_ORPHAN=false
                    for nf in ${NODE_FILES}; do
                        NID=$(grep "^node_id=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                        NTYPE=$(grep "^server_type=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                        NPORT=$(grep "^listen_port=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                        
                        # 检查是否在配置中
                        local STATUS_MARK=""
                        if [ -z "${CONFIGURED_MAP[${NID}]}" ]; then
                            STATUS_MARK="${RED}[已删除-待重启]${NC}"
                            HAS_ORPHAN=true
                        else
                            STATUS_MARK="${GREEN}[运行中]${NC}"
                        fi
                        
                        DETAIL=""
                        case "${NTYPE}" in
                            ss)     DETAIL=$(grep "^ss_method=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2) ;;
                            vmess)  DETAIL=$(grep "^vmess_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2) ;;
                            anytls) DETAIL=$(grep "^anytls_sni=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2) ;;
                            vless)
                                DETAIL=$(grep "^vless_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                VFLOW=$(grep "^vless_flow=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                [ -n "${VFLOW}" ] && DETAIL="${DETAIL},flow=${VFLOW}"
                                ;;
                            ssr)
                                DETAIL=$(grep "^ssr_protocol=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                OBFS=$(grep "^ssr_obfs=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                [ -n "${OBFS}" ] && DETAIL="${DETAIL},obfs=${OBFS}"
                                ;;
                            trojan)
                                DETAIL=$(grep "^trojan_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                [ -z "${DETAIL}" ] && DETAIL="tcp"
                                ;;
                            hysteria)
                                HOBFS=$(grep "^hysteria_obfs_type=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                DETAIL=""
                                [ -n "${HOBFS}" ] && [ "${HOBFS}" != "plain" ] && DETAIL="obfs=${HOBFS}"
                                ;;
                            naive)
                                NTLS=$(grep "^naive_enable_tls=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                NSNI=$(grep "^naive_server_name=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                DETAIL=""
                                [ "${NTLS}" = "true" ] && DETAIL="tls"
                                [ -n "${NSNI}" ] && DETAIL="${DETAIL:+${DETAIL},}sni=${NSNI}"
                                ;;
                            mieru)
                                MTRANS=$(grep "^mieru_transport=" "${nf}" 2>/dev/null | head -1 | cut -d= -f2)
                                DETAIL="transport=${MTRANS}"
                                ;;
                        esac
                        echo -e "  Node ${NID}: ${GREEN}${NTYPE}${NC} | port=${NPORT} | ${DETAIL} ${STATUS_MARK}"
                    done
                    
                    if ${HAS_ORPHAN}; then
                        echo ""
                        echo -e "${YELLOW}提示: 发现已删除但未重启的节点，请执行 'heki restart' 使配置生效${NC}"
                    fi
                fi
            fi
            ;;
        *)
            echo "用法: heki node [add|del|list] [节点ID]"
            echo ""
            echo "  heki node list       查看当前节点"
            echo "  heki node add 100    添加节点 100"
            echo "  heki node del 100    删除节点 100"
            ;;
    esac
}

_node_menu() {
    check_root
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo -e "${RED}配置文件不存在，请先运行: heki setup${NC}"
        return
    fi
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}       Heki 节点管理                 ${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    # 显示当前节点
    do_node list
    echo ""
    echo -e "  ${GREEN}1.${NC} 添加节点"
    echo -e "  ${GREEN}2.${NC} 删除节点"
    echo -e "  ${GREEN}0.${NC} 返回"
    echo ""
    read -p "请选择 [0-2]: " node_choice
    case ${node_choice} in
        1) do_node add ;;
        2) do_node del ;;
        0|"") return ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
}

show_menu() {
    local VER
    VER=$(get_version | awk '{print $2}')
    [ -z "${VER}" ] && VER=$(get_version)
    echo ""
    echo -e "${CYAN}${BOLD}  Heki 管理脚本  ${VER}${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""
    echo -e "  ${GREEN}1.${NC} 启动 Heki"
    echo -e "  ${GREEN}2.${NC} 停止 Heki"
    echo -e "  ${GREEN}3.${NC} 重启 Heki"
    echo -e "  ${GREEN}4.${NC} 查看状态"
    echo -e "  ${GREEN}5.${NC} 查看日志"
    echo -e "  ${GREEN}6.${NC} 查看配置"
    echo -e "  ${GREEN}7.${NC} 修改配置"
    echo -e "  ${GREEN}8.${NC} 节点管理（增删节点）"
    echo -e "  ${GREEN}9.${NC} 重新配置引导"
    echo -e "  ${GREEN}10.${NC} 证书管理"
    echo -e "  ${GREEN}11.${NC} Reality 密钥管理"
    echo -e "  ${GREEN}12.${NC} 设置开机自启"
    echo -e "  ${GREEN}13.${NC} 取消开机自启"
    echo -e "  ${GREEN}14.${NC} 更新 Heki"
    echo -e "  ${GREEN}15.${NC} 卸载 Heki"
    echo -e "  ${GREEN}16.${NC} 查看版本"
    echo -e "  ${GREEN}0.${NC} 退出"
    echo ""
    echo -e "  当前状态: $(get_status)  开机自启: $(get_enabled)"
    echo ""

    read -p "请输入选项 [0-16]: " choice
    case ${choice} in
        1) do_start ;;
        2) do_stop ;;
        3) do_restart ;;
        4) do_status ;;
        5) do_log ;;
        6) do_config ;;
        7) do_modify ;;
        8) _node_menu ;;
        9) do_setup ;;
        10) do_cert ;;
        11) do_reality ;;
        12) do_enable ;;
        13) do_disable ;;
        14) do_update ;;
        15) do_uninstall ;;
        16) do_version ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
}

# 主入口
case "$1" in
    start)      do_start ;;
    stop)       do_stop ;;
    restart)    do_restart ;;
    enable)     do_enable ;;
    disable)    do_disable ;;
    log)        do_log ;;
    status)     do_status ;;
    config)     shift; do_config "$@" ;;
    node)       do_node "$2" "$3" ;;
    modify)     do_modify ;;
    update)     do_update "$2" ;;
    install)    do_install ;;
    uninstall)  do_uninstall ;;
    setup)      do_setup ;;
    cert)       do_cert ;;
    reality)    do_reality "$2" ;;
    x25519)
        if [ -f "${BIN_PATH}" ]; then
            "${BIN_PATH}" x25519
        else
            echo -e "${RED}Heki 未安装，请先安装${NC}"
        fi
        ;;
    version|v|-v) do_version ;;
    help|-h|--help)
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
        echo "后端类型: v2ray(vmess), vless, ss, ssr, trojan, hysteria, anytls, naive, mieru"
        echo ""
        echo "不带参数运行将显示交互式管理菜单"
        ;;
    "")         show_menu ;;
    *)
        echo -e "${RED}未知命令: $1${NC}"
        echo "运行 'heki help' 查看帮助"
        exit 1
        ;;
esac
