#!/bin/bash

# Landscape Router 交互式安装脚本
# 适用于 Debian 13 x86_64 架构 和 Armbian aarch64 架构 (需要内核版本 >= 6.9) 

# 全局变量
INSTALL_LOG=""
LANDSCAPE_DIR=""
WEB_SERVER_INSTALLED=false
TIMEZONE_SHANGHAI=false
SWAP_DISABLED=false
USE_CUSTOM_MIRROR=false
MIRROR_SOURCE="ustc"  # 默认使用中科大源
SUPPORTED_SYSTEM=false  # 是否为支持换源的系统
DOCKER_INSTALLED=false
DOCKER_MIRROR="aliyun"
DOCKER_ENABLE_IPV6=false
MODIFY_APACHE_PORT=false
APACHE_PORT="8080"
LAN_CONFIG=""
GITHUB_MIRROR=""
USE_GITHUB_MIRROR=false
MAX_RETRY=10
IS_ARMBIAN=false
ADMIN_USER="root"
ADMIN_PASS="root"
TEMP_PASS=""
INSTALL_PPP=false
APT_UPDATED=false
TEMP_LOG_DIR=""

# 主逻辑
main() {
    # 初始化临时日志
    init_temp_log
    
    log "Landscape Router 交互式安装脚本开始执行"

    # 检查系统环境
    check_system

    # 询问用户配置
    ask_user_config
    
    # 执行安装
    perform_installation
    
    # 完成安装
    finish_installation
}

# 函数定义部分

# 初始化临时日志
init_temp_log() {
    # 直接在 /tmp 目录下创建临时日志文件
    local timestamp
    timestamp=$(date +"%Y_%m_%d-%H_%M_%S-%3N")
    INSTALL_LOG="/tmp/install-$timestamp.log"
    TEMP_LOG_DIR="/tmp"
    
    # 创建空日志文件
    touch "$INSTALL_LOG"
    
    echo "临时安装日志将保存到: $INSTALL_LOG"
    log "临时安装日志初始化完成"
}

# 记录日志
log() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" | tee -a "$INSTALL_LOG"
}

# 检查系统环境
check_system() {
    log "检查系统环境"
    
    # 检查是否具有 apt
    if ! command -v apt >/dev/null 2>&1; then
        log "错误: 系统中未找到 apt 包管理器"
        exit 1
    fi
    
    # 检查是否有 systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        log "错误: 系统中未找到 systemd"
        exit 1
    fi
    
    # 检查是否有 /etc/network/interfaces
    if [ ! -f "/etc/network/interfaces" ]; then
        log "错误: 系统中未找到 /etc/network/interfaces 文件"
        exit 1
    fi
    
    # 检查内核版本 (需要 > 6.9) 
    local kernel_version
    kernel_version=$(uname -r | cut -d'-' -f1)
    local major_version
    local minor_version
    major_version=$(echo "$kernel_version" | cut -d'.' -f1)
    minor_version=$(echo "$kernel_version" | cut -d'.' -f2)
    
    if [ "$major_version" -lt 6 ] || { [ "$major_version" -eq 6 ] && [ "$minor_version" -lt 9 ]; }; then
        log "错误: 内核版本过低, 需要 6.9 以上版本, 当前版本为 $kernel_version"
        log "请先升级内核版本后再运行此脚本"
        exit 1
    fi
    
    # 检查架构
    local arch
    arch=$(uname -m)
    if [ "$arch" != "x86_64" ] && [ "$arch" != "aarch64" ]; then
        log "警告: 此脚本主要适用于 x86_64 或 aarch64 架构, 当前架构为 $arch"
    fi
    
    # 检查是否以 root 权限运行
    if [ "$EUID" -ne 0 ]; then
        log "错误: 此脚本需要 root 权限运行"
        exit 1
    fi
    
    log "系统环境检查完成"
}

# 询问用户配置
ask_user_config() {
    log "开始询问用户配置"
    
    # 提示用户所有问题回答完成后可以再次修改
    echo ""
    echo "注意: 您需要回答以下所有问题, 回答结束后可以检查和修改任何配置项。"
    echo ""
    
    # 询问是否修改时区为中国上海
    read -rp "是否将系统时区修改为亚洲/上海? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        TIMEZONE_SHANGHAI=true
    fi

    # 询问是否关闭 swap
    read -rp "是否禁用 swap (虚拟内存) ? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        SWAP_DISABLED=true
    fi

    # 询问是否换源 (仅对支持的系统进行询问)
    # 检查是否为支持换源的系统 (Debian, Ubuntu, Linux Mint)
    if grep -q "Debian" /etc/os-release || grep -q "Ubuntu" /etc/os-release || grep -q "Linux Mint" /etc/os-release; then
        echo "请选择要使用的 apt 软件源镜像 (默认不换源):"
        echo "0) 不换源 (默认)"
        echo "1) 中科大"
        echo "2) 清华大学"
        echo "3) 阿里云"
        echo "4) 网易(不支持Alpine)"
        echo "5) 腾讯"
        echo "6) 华为"
        read -rp "请选择 (0-6, 默认为0): " answer
        case "$answer" in
            1) 
                USE_CUSTOM_MIRROR=true
                MIRROR_SOURCE="ustc"
                ;;
            2) 
                USE_CUSTOM_MIRROR=true
                MIRROR_SOURCE="tsinghua"
                ;;
            3) 
                USE_CUSTOM_MIRROR=true
                MIRROR_SOURCE="aliyun"
                ;;
            4) 
                USE_CUSTOM_MIRROR=true
                MIRROR_SOURCE="netease"
                ;;
            5)
                USE_CUSTOM_MIRROR=true
                MIRROR_SOURCE="tencent"
                ;;
            6)
                USE_CUSTOM_MIRROR=true
                MIRROR_SOURCE="huawei"
                ;;
            *)
                USE_CUSTOM_MIRROR=false
                ;;
        esac
    else
        echo "当前系统不支持自动换源功能"
        echo "仅支持 Debian、Ubuntu 和 Linux Mint 系统换源"
    fi

    # 询问是否安装 Docker
    read -rp "是否安装 Docker? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        DOCKER_INSTALLED=true
        
        # 询问 Docker 镜像源
        echo "请选择 Docker 镜像源:"
        echo "1) 阿里云 (默认)"
        echo "2) Azure 中国云"
        echo "3) 官方源 (国外)"
        read -rp "请选择 (1-3, 默认为1): " answer
        case "$answer" in
            2) DOCKER_MIRROR="azure" ;;
            3) DOCKER_MIRROR="official" ;;
            *) DOCKER_MIRROR="aliyun" ;;
        esac
        
        # 询问是否为 Docker 开启 IPv6
        read -rp "是否为 Docker 开启 IPv6 支持? (y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            DOCKER_ENABLE_IPV6=true
        fi
    fi

    # 询问是否修改 Apache 端口
    read -rp "是否修改 Apache 端口以避免与其他反向代理软件冲突? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        MODIFY_APACHE_PORT=true
        read -rp "请输入新的 Apache 端口 (默认为 8080): " answer
        if [[ -n "$answer" ]] && [[ "$answer" =~ ^[0-9]+$ ]]; then
            APACHE_PORT="$answer"
        fi
    fi

    # 询问是否安装 ppp 用于 pppoe 拨号
    read -rp "是否安装 ppp 用于 pppoe 拨号? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        INSTALL_PPP=true
    fi

    # 询问是否使用 GitHub 镜像加速
    echo "请选择 GitHub 镜像加速地址 (默认启用 https://ghfast.top):"
    echo "0) 不使用加速"
    echo "1) https://ghfast.top (默认)"
    echo "2) 自定义地址"
    read -rp "请选择 (0-2, 默认为1): " answer
    case "$answer" in
        0)
            USE_GITHUB_MIRROR=false
            ;;
        2)
            read -rp "请输入 GitHub 镜像加速地址: " custom_mirror
            if [ -n "$custom_mirror" ]; then
                USE_GITHUB_MIRROR=true
                GITHUB_MIRROR="$custom_mirror"
            else
                USE_GITHUB_MIRROR=false
            fi
            ;;
        *)
            USE_GITHUB_MIRROR=true
            GITHUB_MIRROR="https://ghfast.top"
            ;;
    esac
    
    # 询问 Landscape 安装路径
    while true; do
        read -rp "请输入 Landscape Router 安装路径 (默认: /root/.landscape-router): " LANDSCAPE_DIR
        if [ -z "$LANDSCAPE_DIR" ]; then
            LANDSCAPE_DIR="/root/.landscape-router"
        fi
        
        if [ ! -d "$(dirname "$LANDSCAPE_DIR")" ]; then
            log "错误: 指定的安装路径的上级目录不存在"
            continue
        fi
        
        break
    done

    # 询问管理员账号密码
    read -rp "Landscape Router 管理员 用户名、密码 均为 root, 是否修改? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        read -rp "请输入管理员用户名 (默认: root): " custom_user
        if [ -n "$custom_user" ]; then
            ADMIN_USER="$custom_user"
        fi
        
        read -rsp "请输入管理员密码 (默认: root): " TEMP_PASS
        echo  # 换行
        if [ -n "$TEMP_PASS" ]; then
            ADMIN_PASS="$TEMP_PASS"
        fi
        # 清除临时密码变量
        TEMP_PASS=""
    fi
    
    # 配置 LAN 网卡
    config_lan_interface
    
    # 显示所有配置供用户检查和修改
    local config_confirmed=false
    while [ "$config_confirmed" = false ]; do
        echo ""
        echo "=============================="
        echo "请检查您的配置:"
        echo "=============================="
        echo "1. 系统时区设置为亚洲/上海: $([ "$TIMEZONE_SHANGHAI" = true ] && echo "是" || echo "否")"
        echo "2. 禁用 swap (虚拟内存): $([ "$SWAP_DISABLED" = true ] && echo "是" || echo "否")"
        echo "3. 更换 apt 软件源: $([ "$USE_CUSTOM_MIRROR" = true ] && echo "是" || echo "否")"
        if [ "$USE_CUSTOM_MIRROR" = true ]; then
            local mirror_name="未知"
            case "$MIRROR_SOURCE" in
                "ustc") mirror_name="中科大" ;;
                "tsinghua") mirror_name="清华大学" ;;
                "aliyun") mirror_name="阿里云" ;;
                "netease") mirror_name="网易(不支持Alpine)" ;;
                "tencent") mirror_name="腾讯" ;;
                "huawei") mirror_name="华为" ;;
            esac
            echo "   镜像源: $mirror_name"
        fi
        echo "4. 安装 Docker: $([ "$DOCKER_INSTALLED" = true ] && echo "是" || echo "否")"
        if [ "$DOCKER_INSTALLED" = true ]; then
            echo "   Docker 镜像源: $DOCKER_MIRROR"
            echo "   Docker IPv6 支持: $([ "$DOCKER_ENABLE_IPV6" = true ] && echo "是" || echo "否")"
        fi
        echo "5. 修改 Apache 端口: $([ "$MODIFY_APACHE_PORT" = true ] && echo "是" || echo "否")"
        if [ "$MODIFY_APACHE_PORT" = true ]; then
            echo "   Apache 端口: $APACHE_PORT"
        fi
        echo "6. 安装 ppp (用于 PPPOE 拨号): $([ "$INSTALL_PPP" = true ] && echo "是" || echo "否")"
        echo "7. 使用 GitHub 镜像加速: $([ "$USE_GITHUB_MIRROR" = true ] && echo "是" || echo "否")"
        if [ "$USE_GITHUB_MIRROR" = true ]; then
            echo "   GitHub 镜像地址: $GITHUB_MIRROR"
        fi
        echo "8. Landscape Router 安装路径: $LANDSCAPE_DIR"
        echo "9. 管理员账号: $ADMIN_USER"
        echo "   管理员密码: $ADMIN_PASS"
        echo "10. LAN 网桥配置:"
        echo "    名称 = $(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2)"
        echo "    IP地址 = $(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)"
        echo "    DHCP起始地址 = $(echo "$LAN_CONFIG" | grep "dhcp_start" | cut -d '"' -f 2)"
        echo "    DHCP结束地址 = $(echo "$LAN_CONFIG" | grep "dhcp_end" | cut -d '"' -f 2)"
        echo "    网络掩码 = $(echo "$LAN_CONFIG" | grep "network_mask" | awk -F'= ' '{print $2}')"
        local interfaces_list
        interfaces_list=$(echo "$LAN_CONFIG" | grep "interfaces" | cut -d '(' -f 2 | cut -d ')' -f 1)
        echo "    绑定网卡 = $interfaces_list"
        echo "=============================="
        
        read -rp "是否需要修改配置? (输入编号修改对应配置, 输入 'done' 完成配置): " config_choice
        case "$config_choice" in
            1)
                read -rp "是否将系统时区修改为亚洲/上海? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    TIMEZONE_SHANGHAI=true
                else
                    TIMEZONE_SHANGHAI=false
                fi
                ;;
            2)
                read -rp "是否禁用 swap? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    SWAP_DISABLED=true
                else
                    SWAP_DISABLED=false
                fi
                ;;
            3)
                if [ "$SUPPORTED_SYSTEM" = true ]; then
                    read -rp "是否更换 apt 软件源? (y/n): " answer
                    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                        USE_CUSTOM_MIRROR=true
                        
                        # 询问使用哪个镜像源
                        echo "请选择要使用的镜像源:"
                        echo "1) 中科大 (默认)"
                        echo "2) 清华大学"
                        echo "3) 阿里云"
                        echo "4) 网易(不支持Alpine)"
                        echo "5) 腾讯"
                        echo "6) 华为"
                        read -rp "请选择 (1-6, 默认为1): " answer
                        case "$answer" in
                            2) MIRROR_SOURCE="tsinghua" ;;
                            3) MIRROR_SOURCE="aliyun" ;;
                            4) MIRROR_SOURCE="netease" ;;
                            5) MIRROR_SOURCE="tencent" ;;
                            6) MIRROR_SOURCE="huawei" ;;
                            *) MIRROR_SOURCE="ustc" ;;
                        esac
                    else
                        USE_CUSTOM_MIRROR=false
                    fi
                elif [ "$IS_ARMBIAN" = false ]; then
                    echo "当前系统不支持自动换源功能"
                    echo "仅支持 Debian、Ubuntu 和 Linux Mint 系统换源"
                else
                    echo "Armbian 系统不提供换源功能"
                fi
                ;;
            4)
                read -rp "是否安装 Docker? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    DOCKER_INSTALLED=true
                    
                    echo "请选择 Docker 镜像源:"
                    echo "1) 阿里云 (默认)"
                    echo "2) Azure 中国云"
                    echo "3) 官方源 (国外)"
                    read -rp "请选择 (1-3, 默认为1): " answer
                    case "$answer" in
                        2) DOCKER_MIRROR="azure" ;;
                        3) DOCKER_MIRROR="official" ;;
                        *) DOCKER_MIRROR="aliyun" ;;
                    esac
                    
                    read -rp "是否为 Docker 开启 IPv6 支持? (y/n): " answer
                    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                        DOCKER_ENABLE_IPV6=true
                    else
                        DOCKER_ENABLE_IPV6=false
                    fi
                else
                    DOCKER_INSTALLED=false
                fi
                ;;
            5)
                read -rp "是否修改 Apache 端口以避免与其他反向代理软件冲突? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    MODIFY_APACHE_PORT=true
                    read -rp "请输入新的 Apache 端口 (默认为 8080): " answer
                    if [[ -n "$answer" ]] && [[ "$answer" =~ ^[0-9]+$ ]]; then
                        APACHE_PORT="$answer"
                    fi
                else
                    MODIFY_APACHE_PORT=false
                fi
                ;;
            6)
                read -rp "是否安装 ppp 用于 pppoe 拨号? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    INSTALL_PPP=true
                else
                    INSTALL_PPP=false
                fi
                ;;
            7)
                echo "请选择 GitHub 镜像加速地址 (默认启用 https://ghfast.top):"
                echo "0) 不使用加速"
                echo "1) https://ghfast.top (默认)"
                echo "2) 自定义地址"
                read -rp "请选择 (0-2, 默认为1): " answer
                case "$answer" in
                    0)
                        USE_GITHUB_MIRROR=false
                        ;;
                    2)
                        read -rp "请输入 GitHub 镜像加速地址: " custom_mirror
                        if [ -n "$custom_mirror" ]; then
                            USE_GITHUB_MIRROR=true
                            GITHUB_MIRROR="$custom_mirror"
                        else
                            USE_GITHUB_MIRROR=false
                        fi
                        ;;
                    *)
                        USE_GITHUB_MIRROR=true
                        GITHUB_MIRROR="https://ghfast.top"
                        ;;
                esac
                ;;
            8)
                while true; do
                    read -rp "请输入 Landscape Router 安装路径 (默认: /root/.landscape-router): " LANDSCAPE_DIR
                    if [ -z "$LANDSCAPE_DIR" ]; then
                        LANDSCAPE_DIR="/root/.landscape-router"
                    fi
                    
                    if [ ! -d "$(dirname "$LANDSCAPE_DIR")" ]; then
                        log "错误: 指定的安装路径的上级目录不存在"
                        continue
                    fi
                    
                    break
                done
                ;;
            9)
                read -rp "是否设置 Landscape Router 管理员账号密码? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    read -rp "请输入管理员用户名 (默认: root): " custom_user
                    if [ -n "$custom_user" ]; then
                        ADMIN_USER="$custom_user"
                    fi
                    
                    read -rsp "请输入管理员密码 (默认: root): " TEMP_PASS
                    echo  # 换行
                    if [ -n "$TEMP_PASS" ]; then
                        ADMIN_PASS="$TEMP_PASS"
                    fi
                    # 清除临时密码变量
                    TEMP_PASS=""
                fi
                ;;
            10)
                echo "重新配置 LAN 网卡"
                config_lan_interface
                ;;
            done)
                config_confirmed=true
                ;;
            *)
                echo "无效选择, 请重新输入"
                echo "按任意键继续..."
                read -n 1 -s
                ;;
        esac
    done
    
    log "用户配置询问完成"
}


# 配置 LAN 网卡
config_lan_interface() {
    echo "开始配置 LAN 网卡"
    
    # 询问网桥名称
    read -rp "请输入要创建的 LAN 网桥名称 (默认为 lan1): " bridge_name
    if [ -z "$bridge_name" ]; then
        bridge_name="lan1"
    fi
    
    # 获取可用网卡列表
    local interfaces
    interfaces=$(ip link show | awk -F': ' '/^[0-9]+: [a-zA-Z]/ {print $2}' | grep -v lo)
    
    # 显示网卡详细信息
    echo "可用网络接口信息: "
    local i=1
    for iface in $interfaces; do
        echo "$i) $iface"
        # 显示IP地址信息
        local ip_info=$(ip addr show $iface 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        if [ -n "$ip_info" ]; then
            echo "   IP地址: $ip_info"
        fi
        # 显示MAC地址
        local mac_info=$(ip addr show $iface | grep "link/ether" | awk '{print $2}')
        echo "   MAC地址: $mac_info"
        i=$((i+1))
    done
    echo ""
    
    # 选择绑定到网桥的物理网卡
    selected_interfaces=()
    local valid_input=false
    
    while [ "$valid_input" = false ]; do
        echo "请输入要绑定到 $bridge_name 网桥的网卡编号 (多个编号用空格分隔):"
        read -r choice
        
        # 检查输入格式有效性
        if ! [[ "$choice" =~ ^[0-9\ ]+$ ]]; then
            echo "输入无效, 只能包含数字和空格"
            continue
        fi
        
        # 检查每个编号的有效性
        valid_input=true
        local max_index=$((i-1))
        
        for c in $choice; do
            if [ "$c" -lt 1 ] || [ "$c" -gt "$max_index" ]; then
                echo "编号 $c 超出范围, 请输入 1 到 $max_index 的数字"
                valid_input=false
                break
            fi
        done
        
        # 检查是否有重复选择
        local unique_check=()
        for c in $choice; do
            if [[ " ${unique_check[*]} " =~ " ${c} " ]]; then
                echo "检测到重复的选择: $c"
                valid_input=false
                break
            fi
            unique_check+=("$c")
        done
    done
    
    # 处理选择的网卡
    echo "已选择的网卡: "
    for c in $choice; do
        local selected_iface
        selected_iface=$(echo "$interfaces" | sed -n "${c}p")
        selected_interfaces+=("$selected_iface")
        echo "- $selected_iface"
    done
    
    # 验证 IP 地址格式的函数
    function valid_ip() {
        local ip=$1
        local stat=1
        
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            IFS='.' read -r -a ip_parts <<< "$ip"
            
            if [ "${ip_parts[0]}" -eq 127 ] && [ "${ip_parts[1]}" -le 255 ] && [ "${ip_parts[2]}" -le 255 ] && [ "${ip_parts[3]}" -le 255 ]; then
                stat=0
            elif [ "${ip_parts[0]}" -ge 1 ] && [ "${ip_parts[0]}" -le 255 ] && \
                 [ "${ip_parts[1]}" -ge 0 ] && [ "${ip_parts[1]}" -le 255 ] && \
                 [ "${ip_parts[2]}" -ge 0 ] && [ "${ip_parts[2]}" -le 255 ] && \
                 [ "${ip_parts[3]}" -ge 1 ] && [ "${ip_parts[3]}" -le 254 ]; then
                stat=0
            fi
        fi
        
        return $stat
    }
    
    # 询问 LAN IP
    while true; do
        read -rp "请输入 LAN 网桥的 IP 地址 (默认为 192.168.88.1): " lan_ip
        if [ -z "$lan_ip" ]; then
            lan_ip="192.168.88.1"
            break
        fi
        
        if valid_ip "$lan_ip"; then
            break
        else
            echo "输入的 IP 地址无效, 请输入有效的 IP 地址 (例如: 192.168.88.1) "
        fi
    done
    
    # 询问 DHCP 范围
    while true; do
        read -rp "请输入 DHCP IP 范围起始地址 (默认为 192.168.88.100): " dhcp_start
        if [ -z "$dhcp_start" ]; then
            dhcp_start="192.168.88.100"
            break
        fi
        
        if valid_ip "$dhcp_start"; then
            break
        else
            echo "输入的 IP 地址无效, 请输入有效的 IP 地址 (例如: 192.168.88.100) "
        fi
    done
    
    while true; do
        read -rp "请输入 DHCP IP 范围结束地址 (默认为 192.168.88.200): " dhcp_end
        if [ -z "$dhcp_end" ]; then
            dhcp_end="192.168.88.200"
            break
        fi
        
        if valid_ip "$dhcp_end"; then
            # 检查结束IP是否在合理范围内
            local start_octets=(${dhcp_start//./ })
            local end_octets=(${dhcp_end//./ })
            
            if [ "${end_octets[3]}" -le "${start_octets[3]}" ]; then
                echo "DHCP 结束地址必须大于起始地址"
            elif [ $((end_octets[3] - start_octets[3])) -gt 100 ]; then
                echo "DHCP 地址范围不应超过 100 个地址"
            else
                break
            fi
        else
            echo "输入的 IP 地址无效, 请输入有效的 IP 地址 (例如: 192.168.88.200) "
        fi
    done
    
    # 询问网络掩码
    while true; do
        read -rp "请输入网络掩码位数 (默认为 24): " network_mask
        if [ -z "$network_mask" ]; then
            network_mask=24
            break
        fi
        
        if [[ "$network_mask" =~ ^[0-9]+$ ]] && [ "$network_mask" -ge 8 ] && [ "$network_mask" -le 32 ]; then
            break
        else
            echo "输入的网络掩码无效, 请输入 8 到 32 之间的数字"
        fi
    done
    
    # 构建 LAN 配置
    LAN_CONFIG="bridge_name = \"$bridge_name\"
lan_ip = \"$lan_ip\"
dhcp_start = \"$dhcp_start\"
dhcp_end = \"$dhcp_end\"
network_mask = $network_mask
interfaces = ($(printf '"%s", ' "${selected_interfaces[@]}" | sed 's/, $//'))"
}

# 执行安装
perform_installation() {
    log "开始执行安装"
    
    # 1. 创建 Landscape 目录 (移到第一个) 
    create_landscape_dir
    
    # 2. 修改时区
    if [ "$TIMEZONE_SHANGHAI" = true ]; then
        setup_timezone
    fi
    
    # 3. 关闭 swap
    if [ "$SWAP_DISABLED" = true ]; then
        disable_swap
    fi
    
    # 4. 换源
    if [ "$USE_CUSTOM_MIRROR" = true ]; then
        change_apt_mirror
    fi
    
    # 5. 下载并安装 Landscape Router
    install_landscape_router
    
    # 6. 创建 systemd 服务
    create_systemd_service
    
    # 6. 检查并安装 webserver
    if ! dpkg -l | grep -q apache2; then
        log "检测到系统未安装 web server 环境, 将自动安装 Apache2"
        install_webserver
    else
        log "检测到系统已安装 web server 环境"
    fi
    
    # 7. 安装 Docker
    if [ "$DOCKER_INSTALLED" = true ]; then
        install_docker
        configure_docker
    fi
    
    # 8. 修改 Apache 端口
    if [ "$MODIFY_APACHE_PORT" = true ]; then
        modify_apache_port
    fi
    
    # 9. 安装 ppp
    if [ "$INSTALL_PPP" = true ]; then
        install_ppp
    fi
    
    # 10. 配置网络接口
    configure_network_interfaces
    
    # 11. 创建管理员账号密码配置文件
    create_landscape_toml
    
    # 12. 关闭本机 DNS 服务
    disable_local_dns
    
    log "安装执行完成"
}

# 设置时区
setup_timezone() {
    log "设置系统时区为亚洲/上海"
    timedatectl set-timezone Asia/Shanghai
    log "时区设置完成"
}


# 关闭 swap
disable_swap() {
    log "禁用 swap (虚拟内存)"
    
    # 注释掉 fstab 中的 swap 条目
    sed -i 's/^[^#].*swap.*/#&/' /etc/fstab
    
    log "swap (虚拟内存)  已禁用"
}

# 换源
change_apt_mirror() {
    log "更换 apt 软件源"
    
    # 检查是否为支持的系统类型
    local is_supported=false
    if grep -q "Debian" /etc/os-release || grep -q "Ubuntu" /etc/os-release || grep -q "Linux Mint" /etc/os-release; then
        is_supported=true
    fi
    
    if [ "$is_supported" = false ]; then
        log "警告: 不支持的系统类型，仅支持 Debian、Ubuntu 和 Linux Mint"
        log "提示: 不支持小众发行版换源，建议小众发行版自行换源"
        return 0
    fi
    
    # 检查系统类型
    local system_type=""
    local system_version=""
    local version_codename=""
    
    if grep -q "Debian" /etc/os-release; then
        system_type="debian"
        system_version=$(grep "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        version_codename=$(grep "VERSION_CODENAME" /etc/os-release | cut -d'=' -f2)
    elif grep -q "Ubuntu" /etc/os-release; then
        system_type="ubuntu"
        system_version=$(grep "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        version_codename=$(grep "VERSION_CODENAME" /etc/os-release | cut -d'=' -f2)
    elif grep -q "Linux Mint" /etc/os-release; then
        system_type="linuxmint"
        system_version=$(grep "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        # Linux Mint 使用 Ubuntu 的代号，需要特殊处理
        # 从 VERSION 中提取 Ubuntu 代号
        local ubuntu_codename=$(grep "UBUNTU_CODENAME" /etc/os-release | cut -d'=' -f2)
        if [ -n "$ubuntu_codename" ]; then
            version_codename="$ubuntu_codename"
        else
            # 如果没有 UBUNTU_CODENAME，尝试从 VERSION 中提取
            local version_desc=$(grep "VERSION=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
            # 这里简化处理，实际应该根据 Linux Mint 版本映射到 Ubuntu 代号
            version_codename="focal"  # 默认 focal，实际应该有更精确的映射
        fi
    fi
    
    # 确定使用的镜像源URL
    local mirror_url=""
    case "$MIRROR_SOURCE" in
        "ustc")
            case "$system_type" in
                "debian") mirror_url="https://mirrors.ustc.edu.cn/debian/" ;;
                "ubuntu") mirror_url="https://mirrors.ustc.edu.cn/ubuntu/" ;;
                "linuxmint") mirror_url="https://mirrors.ustc.edu.cn/linuxmint/" ;;
            esac
            ;;
        "tsinghua")
            case "$system_type" in
                "debian") mirror_url="https://mirrors.tuna.tsinghua.edu.cn/debian/" ;;
                "ubuntu") mirror_url="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/" ;;
                "linuxmint") mirror_url="https://mirrors.tuna.tsinghua.edu.cn/linuxmint/" ;;
            esac
            ;;
        "aliyun")
            case "$system_type" in
                "debian") mirror_url="https://mirrors.aliyun.com/debian/" ;;
                "ubuntu") mirror_url="https://mirrors.aliyun.com/ubuntu/" ;;
                "linuxmint") mirror_url="https://mirrors.aliyun.com/linuxmint/" ;;
            esac
            ;;
        "netease")
            case "$system_type" in
                "debian") mirror_url="https://mirrors.163.com/debian/" ;;
                "ubuntu") mirror_url="https://mirrors.163.com/ubuntu/" ;;
                "linuxmint") mirror_url="https://mirrors.163.com/linuxmint/" ;;
            esac
            ;;
        "tencent")
            case "$system_type" in
                "debian") mirror_url="https://mirrors.cloud.tencent.com/debian/" ;;
                "ubuntu") mirror_url="https://mirrors.cloud.tencent.com/ubuntu/" ;;
                "linuxmint") mirror_url="https://mirrors.cloud.tencent.com/linuxmint/" ;;
            esac
            ;;
        "huawei")
            case "$system_type" in
                "debian") mirror_url="https://mirrors.huaweicloud.com/repository/debian/" ;;
                "ubuntu") mirror_url="https://mirrors.huaweicloud.com/repository/ubuntu/" ;;
                "linuxmint") mirror_url="https://mirrors.huaweicloud.com/repository/linuxmint/" ;;
            esac
            ;;
    esac
    
    log "系统类型: $system_type"
    log "系统版本: $system_version"
    log "版本代号: $version_codename"
    log "使用镜像源: $MIRROR_SOURCE ($mirror_url)"
    
    # 备份原源
    if [ -f "/etc/apt/sources.list" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
    fi
    
    # 根据系统类型生成对应的源列表
    case "$system_type" in
        "debian")
            # 如果无法获取版本代号，则使用通用代号
            if [ -z "$version_codename" ]; then
                version_codename="stable"
            fi
            
            # 写入新源
            cat > /etc/apt/sources.list << EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可取消注释
deb $mirror_url $version_codename main contrib non-free non-free-firmware
# deb-src $mirror_url $version_codename main contrib non-free non-free-firmware

deb $mirror_url $version_codename-updates main contrib non-free non-free-firmware
# deb-src $mirror_url $version_codename-updates main contrib non-free non-free-firmware

deb $mirror_url $version_codename-backports main contrib non-free non-free-firmware
# deb-src $mirror_url $version_codename-backports main contrib non-free non-free-firmware

deb ${mirror_url}security/ $version_codename-security main contrib non-free non-free-firmware
# deb-src ${mirror_url}security/ $version_codename-security main contrib non-free non-free-firmware
EOF
            ;;
            
        "ubuntu"|"linuxmint")
            # 如果无法获取版本代号，则使用通用代号
            if [ -z "$version_codename" ]; then
                version_codename="focal"  # 默认使用 focal
            fi
            
            # 写入新源
            cat > /etc/apt/sources.list << EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可取消注释
deb $mirror_url $version_codename main restricted universe multiverse
# deb-src $mirror_url $version_codename main restricted universe multiverse

deb $mirror_url $version_codename-updates main restricted universe multiverse
# deb-src $mirror_url $version_codename-updates main restricted universe multiverse

deb $mirror_url $version_codename-backports main restricted universe multiverse
# deb-src $mirror_url $version_codename-backports main restricted universe multiverse

deb ${mirror_url}security/ $version_codename-security main restricted universe multiverse
# deb-src ${mirror_url}security/ $version_codename-security main restricted universe multiverse
EOF
            ;;
    esac
    
    # 更新包索引
    apt_update
    
    log "apt 软件源更换完成"
}


# 安装 webserver
install_webserver() {
    log "安装 Apache2"
    apt_update
    apt_install "apache2"
}

# 安装 Docker
install_docker() {
    log "安装 Docker"
    
    # 检查 curl 是否已安装, 未安装则安装
    if ! command -v curl &> /dev/null; then
        log "未检测到 curl, 正在安装..."
        apt_update
        apt_install "curl"
    else
        log "curl 已安装"
    fi
    
    local retry=0
    local max_retry=1
    local user_choice=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在安装 Docker (尝试 $((retry+1))/$max_retry)"
            
            # 根据选择的镜像源安装 Docker
            case "$DOCKER_MIRROR" in
                "aliyun")
                    if curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun; then
                        log "Docker 安装成功"
                        return 0
                    fi
                    ;;
                "azure")
                    if curl -fsSL https://get.docker.com | bash -s docker --mirror AzureChinaCloud; then
                        log "Docker 安装成功"
                        return 0
                    fi
                    ;;
                *)
                    if curl -fsSL https://get.docker.com | bash; then
                        log "Docker 安装成功"
                        return 0
                    fi
                    ;;
            esac
            
            retry=$((retry+1))
            log "Docker 安装失败"
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "Docker 安装失败, 请选择操作:"
            echo "  r) 重试一次"
            echo "  m) 重新选择镜像源再试"
            echo "  n) 退出安装"
            read -rp "请输入选项 (r/m/n): " user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            case "$user_choice" in
                "r")
                    # 重试，保持当前镜像源
                    user_choice="y"  # 重置选择以便继续循环
                    retry=0  # 重置重试计数
                    ;;
                "m")
                    # 重新选择镜像源
                    echo "请选择 Docker 镜像源:"
                    echo "1) 阿里云 (默认)"
                    echo "2) Azure 中国云"
                    echo "3) 官方源 (国外)"
                    read -rp "请选择 (1-3, 默认为1): " mirror_choice
                    case "$mirror_choice" in
                        2) DOCKER_MIRROR="azure" ;;
                        3) DOCKER_MIRROR="official" ;;
                        *) DOCKER_MIRROR="aliyun" ;;
                    esac
                    user_choice="y"  # 重置选择以便继续循环
                    retry=0  # 重置重试计数
                    ;;
                *)
                    # 默认为退出安装
                    user_choice="n"
                    ;;
            esac
        fi
    done
    
    log "错误: Docker 安装失败"
    exit 1
}


# 配置 Docker
configure_docker() {
    log "配置 Docker"
    
    # 为 Docker 配置全局时区
    mkdir -p /etc/systemd/system/docker.service.d
    cat > /etc/systemd/system/docker.service.d/timezone.conf << EOF
[Service]
Environment="TZ=Asia/Shanghai"
EOF
    
    # 为 Docker 开启 IPv6 (如果需要)
    if [ "$DOCKER_ENABLE_IPV6" = true ]; then
        cat > /etc/docker/daemon.json << EOF
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80"
}
EOF
    fi
    
    # 重启 Docker 服务
    systemctl daemon-reload
    systemctl restart docker
    
    log "Docker 配置完成"
}

# 修改 Apache 端口
modify_apache_port() {
    log "修改 Apache 端口为 $APACHE_PORT"
    
    # 修改端口配置
    sed -i "s/Listen 80/Listen $APACHE_PORT/" /etc/apache2/ports.conf
    sed -i "s/:80>/:$APACHE_PORT>/" /etc/apache2/sites-available/000-default.conf
    
    # 重启 Apache
    systemctl restart apache2
    
    log "Apache 端口修改完成"
}

# 处理 apt 换源选择的通用函数
handle_apt_mirror_choice() {
    log "用户选择换源操作"
    if [ "$USE_CUSTOM_MIRROR" = false ]; then
        echo "当前未配置自定义镜像源，无法换源。"
        echo "请选择: "
        echo "1) 再次尝试3次"
        echo "2) 退出安装 (输入除1以外的任意字符)"
        read -r user_choice
        
        if [ "$user_choice" != "1" ]; then
            log "用户选择退出安装"
            exit 1
        else
            user_choice="y"
        fi
        echo "$user_choice"  # 返回用户选择
    else
        # 备份当前源
        if [ -f "/etc/apt/sources.list" ]; then
            cp /etc/apt/sources.list /etc/apt/sources.list.pre-fail.bak
        fi
        
        # 根据当前镜像源切换到下一个可用镜像源
        local next_mirror=""
        case "$MIRROR_SOURCE" in
            "ustc") next_mirror="tsinghua" ;;
            "tsinghua") next_mirror="aliyun" ;;
            "aliyun") next_mirror="tencent" ;;
            "tencent") next_mirror="huawei" ;;
            "huawei") next_mirror="netease" ;;
            "netease") next_mirror="ustc" ;;
            *) next_mirror="ustc" ;;
        esac
        
        MIRROR_SOURCE="$next_mirror"
        change_apt_mirror
        echo "y"  # 返回用户选择以便继续循环
    fi
}

# 处理 GitHub 镜像加速选择的通用函数
handle_github_mirror_choice() {
    local binary_name="$1"  # 传入正在下载的文件名
    log "用户选择使用 GitHub 镜像加速"
    if [ "$USE_GITHUB_MIRROR" = false ]; then
        echo "请选择 GitHub 镜像加速地址:"
        echo "1) https://ghfast.top"
        echo "2) 自定义地址"
        echo "3) 取消并再次尝试3次"
        read -rp "请选择 (1-3): " mirror_choice
        
        case "$mirror_choice" in
            1)
                USE_GITHUB_MIRROR=true
                GITHUB_MIRROR="https://ghfast.top"
                echo "1"  # 表示选择了镜像1
                ;;
            2)
                read -rp "请输入 GitHub 镜像加速地址: " custom_mirror
                if [ -n "$custom_mirror" ]; then
                    USE_GITHUB_MIRROR=true
                    GITHUB_MIRROR="$custom_mirror"
                    echo "2"  # 表示选择了自定义镜像
                else
                    echo "输入的镜像地址为空，取消使用镜像加速"
                    echo "3"  # 表示取消操作
                fi
                ;;
            *)
                echo "3"  # 表示取消操作
                ;;
        esac
    else
        echo "当前已配置 GitHub 镜像加速，无法进一步优化"
        echo "y"  # 继续重试
    fi
}

# 独立的 apt update 函数
apt_update() {
    if [ "$APT_UPDATED" = false ]; then
        log "执行 apt update"
        
        local retry=0
        local max_retry=3
        local user_choice=""
        
        while [ "$user_choice" != "n" ]; do
            retry=0
            while [ $retry -lt $max_retry ]; do
                if apt update; then
                    APT_UPDATED=true
                    log "apt update 执行完成"
                    return 0
                else
                    retry=$((retry+1))
                    log "apt update 失败, 正在进行第 $retry/$max_retry 次重试"
                    sleep 3
                fi
            done
            
            if [ $retry -eq $max_retry ]; then
                echo "apt update 失败, 是否再次尝试3次？(y/n) 或输入 'm' 尝试换源: "
                read -r user_choice
                user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
                
                # 如果用户选择换源
                if [ "$user_choice" = "m" ]; then
                    user_choice=$(handle_apt_mirror_choice)
                    retry=0  # 重置重试计数
                fi
            fi
        done
        
        log "错误: apt update 失败"
        exit 1
    else
        log "apt update 已执行过, 跳过"
    fi
}

# 带重试机制的 apt install 函数
apt_install() {
    local packages="$1"
    log "安装软件包: $packages"
    
    local retry=0
    local max_retry=3
    local user_choice=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            if apt install $packages -y; then
                log "软件包 $packages 安装完成"
                return 0
            else
                retry=$((retry+1))
                log "软件包 $packages 安装失败, 正在进行第 $retry/$max_retry 次重试"
                sleep 3
            fi
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "软件包 $packages 安装失败, 是否再次尝试3次？(y/n) 或输入 'm' 尝试换源: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择换源
            if [ "$user_choice" = "m" ]; then
                user_choice=$(handle_apt_mirror_choice)
                retry=0  # 重置重试计数
            fi
        fi
    done
    
    log "错误: 软件包 $packages 安装失败"
    exit 1
}

# 安装 ppp
install_ppp() {
    log "安装 ppp"
    apt_update
    apt_install "ppp"
}

# 创建 Landscape 目录
create_landscape_dir() {
    log "创建 Landscape Router 目录: $LANDSCAPE_DIR"
    mkdir -p "$LANDSCAPE_DIR"
    
    # 在 Landscape 目录下创建 script-log 目录
    mkdir -p "$LANDSCAPE_DIR/script-log"
    
    # 将临时日志移动到 Landscape 目录下
    if [ -f "$INSTALL_LOG" ]; then
        local log_filename
        log_filename=$(basename "$INSTALL_LOG")
        
        # 先尝试直接移动日志文件
        if ! mv "$INSTALL_LOG" "$LANDSCAPE_DIR/script-log/$log_filename" 2>/dev/null; then
            # 如果直接移动失败, 尝试复制并清理原文件
            cp "$INSTALL_LOG" "$LANDSCAPE_DIR/script-log/$log_filename" && rm -f "$INSTALL_LOG"
        fi
        
        # 更新日志文件路径
        INSTALL_LOG="$LANDSCAPE_DIR/script-log/$log_filename"
        log "日志路径已更新到: $INSTALL_LOG"
    fi
    
    log "Landscape Router 目录创建完成"
}


# 安装 Landscape Router
install_landscape_router() {
    log "下载并安装 Landscape Router"
    
    # 检查 curl 是否已安装, 未安装则安装
    if ! command -v curl &> /dev/null; then
        log "未检测到 curl, 正在安装..."
        apt_update
        apt_install "curl"
    else
        log "curl 已安装"
    fi
    
        # 根据架构确定二进制文件名
    local binary_filename=""
    local system_arch
    system_arch=$(uname -m)
    if [ "$system_arch" = "aarch64" ]; then
        binary_filename="landscape-webserver-aarch64"
    else
        binary_filename="landscape-webserver-x86_64"
    fi
    
    # 直接下载 latest 版本的 landscape-webserver 二进制文件
    local binary_url
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        binary_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_filename"
    else
        binary_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_filename"
    fi
    
    local retry=0
    local max_retry=3
    local user_choice=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在下载 $binary_filename (尝试 $((retry+1))/$max_retry)"
            if curl -fsSL -o "$LANDSCAPE_DIR/$binary_filename" "$binary_url"; then
                log "$binary_filename 下载成功"
                break
            else
                retry=$((retry+1))
                log "下载失败, 等待 5 秒后重试"
                sleep 5
            fi
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "下载 $binary_filename 失败, 是否再次尝试3次？(y/n) 或输入 'm' 使用 GitHub 镜像加速: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择使用 GitHub 镜像加速
            if [ "$user_choice" = "m" ]; then
                local mirror_result=""
                mirror_result=$(handle_github_mirror_choice "$binary_filename")
                
                case "$mirror_result" in
                    "1")
                        # 更新下载 URL
                        binary_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_filename"
                        user_choice="y"  # 重置选择以便继续循环
                        retry=0  # 重置重试计数
                        ;;
                    "2")
                        # 更新下载 URL
                        binary_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_filename"
                        user_choice="y"  # 重置选择以便继续循环
                        retry=0  # 重置重试计数
                        ;;
                    *)
                        user_choice="y"
                        ;;
                esac
            fi
        else
            # 下载成功则跳出循环
            break
        fi
    done
    
    if [ $retry -eq $max_retry ] && [ "$user_choice" = "n" ]; then
        log "错误: 下载 $binary_filename 失败"
        exit 1
    fi
    
    # 确保 unzip 已安装
    log "检查并安装 unzip 工具"
    
    if ! command -v unzip &> /dev/null; then
        log "未检测到 unzip, 正在安装..."
        apt_update
        apt_install "unzip"
    else
        log "unzip 已安装"
    fi
    
    # 下载 latest 版本的 static.zip
    local static_url
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        static_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
    else
        static_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
    fi
    
    retry=0
    user_choice=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在下载 static.zip (尝试 $((retry+1))/$max_retry)"
            if curl -fsSL -o "/tmp/static.zip" "$static_url"; then
                log "static.zip 下载成功"
                break
            else
                retry=$((retry+1))
                log "下载失败, 等待 5 秒后重试"
                sleep 5
            fi
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "下载 static.zip 失败, 是否再次尝试3次？(y/n) 或输入 'm' 使用 GitHub 镜像加速: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择使用 GitHub 镜像加速
            if [ "$user_choice" = "m" ]; then
                local mirror_result=""
                mirror_result=$(handle_github_mirror_choice "static.zip")
                
                case "$mirror_result" in
                    "1")
                        # 更新下载 URL
                        static_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
                        user_choice="y"  # 重置选择以便继续循环
                        retry=0  # 重置重试计数
                        ;;
                    "2")
                        # 更新下载 URL
                        static_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
                        user_choice="y"  # 重置选择以便继续循环
                        retry=0  # 重置重试计数
                        ;;
                    *)
                        user_choice="y"
                        ;;
                esac
            fi
        else
            # 下载成功则跳出循环
            break
        fi
    done
    
    if [ $retry -eq $max_retry ] && [ "$user_choice" = "n" ]; then
        log "错误: 下载 static.zip 失败"
        exit 1
    fi
    
    # 解压 static.zip
    log "解压 static.zip"
    unzip -q /tmp/static.zip -d /tmp/static
    
    # 查找正确的 static 目录 (包含 index.html 和 assets 目录)
    local static_dir=""
    find_static_dir() {
        local search_dir="$1"
        
        # 检查当前目录
        if [ -f "$search_dir/index.html" ] && [ -d "$search_dir/assets" ]; then
            echo "$search_dir"
            return 0
        fi
        
        # 在子目录中递归查找
        for dir in "$search_dir"/*/; do
            if [ -d "$dir" ]; then
                local result
                result=$(find_static_dir "$dir")
                if [ -n "$result" ]; then
                    echo "$result"
                    return 0
                fi
            fi
        done
        
        return 1
    }
    
    static_dir=$(find_static_dir "/tmp/static")
    if [ -z "$static_dir" ]; then
        log "错误: 无法找到正确的 static 目录"
        exit 1
    fi
    
    log "找到正确的 static 目录: $static_dir"
    
    # 复制 static 目录到 Landscape Router 目录
    log "复制 static 目录到 $LANDSCAPE_DIR"
    rm -rf "$LANDSCAPE_DIR/static"
    cp -r "$static_dir" "$LANDSCAPE_DIR/static"
    
    # 清理临时文件
    rm -rf /tmp/static.zip /tmp/static
    
    # 添加执行权限
    chmod +x "$LANDSCAPE_DIR/$binary_filename"
    
    # 获取版本信息
    local version
    version=$("$LANDSCAPE_DIR/$binary_filename" --version 2>/dev/null)
    if [ -n "$version" ]; then
        log "Landscape Router 版本信息: $version"
    else
        log "无法获取 Landscape Router 版本信息"
    fi
    
    log "Landscape Router 部署完成"
}


# 创建 systemd 服务
create_systemd_service() {
    log "创建 Landscape Router systemd 服务"
    
    # 根据架构确定二进制文件名
    local binary_filename=""
    local system_arch
    system_arch=$(uname -m)
    if [ "$system_arch" = "aarch64" ]; then
        binary_filename="landscape-webserver-aarch64"
    else
        binary_filename="landscape-webserver-x86_64"
    fi
    
    cat > /etc/systemd/system/landscape-router.service << EOF
[Unit]
Description=Landscape Router

[Service]
ExecStart=$LANDSCAPE_DIR/$binary_filename
Restart=always
User=root
LimitMEMLOCK=infinity


[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载 systemd 配置
    systemctl daemon-reload
    
    log "Landscape Router systemd 服务创建完成"
}

# 配置网络接口
configure_network_interfaces() {
    log "配置所有网络接口为 manual 模式"
    
    # 备份原网络配置
    cp /etc/network/interfaces /etc/network/interfaces.bak
    
    # 创建基础配置
    cat > /etc/network/interfaces << EOF
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback


EOF

# 这几行是从上面拿下来的, 是无效的代码, 先放在这里, 后面会删除
# # LAN bridge
# auto $(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2)
# iface $(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2) inet static
#     address $(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)
#     netmask 255.255.255.0

    # 添加绑定到网桥的物理接口
    local interfaces_list
    interfaces_list=$(echo "$LAN_CONFIG" | grep "interfaces" | cut -d '(' -f 2 | cut -d ')' -f 1)
    
    IFS=', ' read -r -a iface_array <<< "$interfaces_list"
    for iface in "${iface_array[@]}"; do
        iface=$(echo "$iface" | tr -d '"')
        if [ -n "$iface" ]; then
            cat >> /etc/network/interfaces << EOF
auto $iface
iface $iface inet manual

EOF
        fi
    done
    log "LAN 网桥配置 开始"
    # 创建 landscape_init.toml 配置文件
    create_landscape_init_toml
    
    log "LAN 网桥配置 完成"
}


# 创建 landscape_init.toml 配置文件
create_landscape_init_toml() {
    log "创建 landscape_init.toml 配置文件"
    
    local bridge_name
    bridge_name=$(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2)
    
    local lan_ip
    lan_ip=$(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)
    
    local dhcp_start
    dhcp_start=$(echo "$LAN_CONFIG" | grep "dhcp_start" | cut -d '"' -f 2)
    
    local dhcp_end
    dhcp_end=$(echo "$LAN_CONFIG" | grep "dhcp_end" | cut -d '"' -f 2)
    
    local network_mask
    network_mask=$(echo "$LAN_CONFIG" | grep "network_mask" | awk -F'= ' '{print $2}')
    
    local interfaces_list
    interfaces_list=$(echo "$LAN_CONFIG" | grep "interfaces" | cut -d '(' -f 2 | cut -d ')' -f 1)
    
    cat > "$LANDSCAPE_DIR/landscape_init.toml" << EOF
# ==== 创建 $bridge_name 网桥 ====
[[ifaces]]
name = "$bridge_name"
create_dev_type = "bridge"
zone_type = "lan"
enable_in_boot = true
wifi_mode = "undefined"

# $bridge_name 开启 ebpf 路由
[[route_lans]]
iface_name = "$bridge_name"
enable = true

# ==== 绑定物理网卡到 $bridge_name 网桥 ====
EOF

    # 添加绑定的物理接口
    IFS=', ' read -r -a iface_array <<< "$interfaces_list"
    for iface in "${iface_array[@]}"; do
        iface=$(echo "$iface" | tr -d '"')
        if [ -n "$iface" ]; then
            cat >> "$LANDSCAPE_DIR/landscape_init.toml" << EOF

[[ifaces]]
name = "$iface"
create_dev_type = "no_need_to_create"
controller_name = "$bridge_name"
zone_type = "undefined"
enable_in_boot = true
wifi_mode = "undefined"
EOF
        fi
    done

    cat >> "$LANDSCAPE_DIR/landscape_init.toml" << EOF

# ==== $bridge_name 配置 DHCP ====
[[dhcpv4_services]]
iface_name = "$bridge_name"
enable = true

[dhcpv4_services.config]
ip_range_start = "$dhcp_start"
ip_range_end = "$dhcp_end"
server_ip_addr = "$lan_ip"
network_mask = $network_mask
mac_binding_records = []
EOF

    log "landscape_init.toml 配置文件创建完成"
}

# 创建 landscape.toml 配置文件 (包含管理员账号密码) 
create_landscape_toml() {
    log "创建 landscape.toml 配置文件"
    
    mkdir -p "$LANDSCAPE_DIR/etc/landscape"
    
    cat > "$LANDSCAPE_DIR/etc/landscape/landscape.toml" << EOF
[auth]
# 管理员账号、密码
admin_user = "$ADMIN_USER"
admin_pass = "$ADMIN_PASS"
EOF

    log "landscape.toml 配置文件创建完成"
}

# 关闭本机 DNS 服务
disable_local_dns() {
    log "关闭本机 DNS 服务"
    
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    systemctl mask systemd-resolved 2>/dev/null || true
    
    log "本机 DNS 服务关闭完成"
}

# 完成安装
finish_installation() {
    log "完成安装过程"

    # 设置开机自启
    systemctl enable landscape-router.service >/dev/null 2>&1

    # 显示安装完成信息
    echo ""
    echo "管理员密码 不会出现在 安装脚本日志文件中"
    echo "安装脚本日志文件保存在: $INSTALL_LOG"
    echo ""
    echo "升级 Landscape Router 的方法:"
    echo ""
    echo "1. 从 https://github.com/ThisSeanZhang/landscape/releases 下载最新版本"
    echo "2. 停止服务: systemctl stop landscape-router.service"
    echo "3. 替换文件并赋予执行权限, 如 755"
    echo "4. 启动服务: systemctl start landscape-router.service"
    echo "或者使用项目提供的升级脚本 upgrade_landscape.sh"
    echo ""
    echo "如果遇到主机失联情况, 请按以下步骤操作:"
    echo ""
    echo "1. 在物理机上将合适网卡改为 static 并配置 IP/掩码"
    echo "2. 通过配置的 IP 访问 主机 或 Landscape UI"
    echo ""
    local lan_ip
    lan_ip=$(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)
    echo "接下来 SSH 连接可能会中断"
    echo "请通过 $lan_ip 连接 SSH 服务"
    echo ""
    echo "=============================="
    echo "Landscape Router 安装完成!"
    echo "=============================="
    echo ""
    echo "请通过浏览器, 访问以下地址管理您的 Landscape Router :"
    echo ""
    echo "  http://$lan_ip:6300"
    echo ""
    echo "管理员用户名: $ADMIN_USER"
    echo "管理员密码: $ADMIN_PASS"
    echo ""
    echo "=============================="
    echo ""
    echo "网络配置即将生效"
    echo "已启动 Landscape Router 服务"
    # 重启网络服务 并 启动 Landscape Router 服务
    echo "安装完成, 脚本退出"
    systemctl restart networking && systemctl start landscape-router.service

    log "安装完成"
}

# 调用主函数
main "$@"
