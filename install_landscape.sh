#!/bin/bash

# Landscape Router 交互式安装脚本
# 适用于 Debian、Ubuntu、Mint、Armbian (需要内核版本 >= 6.9) 
# 适用于 x86_64 架构 和 Armbian aarch64 架构


# 全局变量
INSTALL_LOG=""
LANDSCAPE_DIR=""
WEB_SERVER_INSTALLED=false
WEB_SERVER_TYPE=""
WEB_SERVER_PREINSTALLED=false
TIMEZONE_SHANGHAI=false
SWAP_DISABLED=false
USE_CUSTOM_MIRROR=false
MIRROR_SOURCE="aliyun"  # 默认使用阿里云源
SUPPORTED_SYSTEM=false  # 是否为支持换源的系统
DOCKER_INSTALLED=false
DOCKER_MIRROR="aliyun"
DOCKER_ENABLE_IPV6=false
LAN_CONFIG=""
GITHUB_MIRROR=""
USE_GITHUB_MIRROR=false
MAX_RETRY=10
ADMIN_USER="root"
ADMIN_PASS="root"
TEMP_PASS=""
INSTALL_PPP=false
APT_UPDATED=false
TEMP_LOG_DIR=""
APT_SOURCE_BACKED_UP=false  # 是否已经备份过源文件
DOWNLOAD_HANDLER=false      # 是否下载 handler
HANDLER_ARCHITECTURES=()    # 要下载的 handler 架构列表

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
    
    # 检查是否已安装web server (apache2, nginx, lighttpd)
    if ! dpkg -l | grep -q apache2 && ! command -v nginx >/dev/null 2>&1 && ! command -v lighttpd >/dev/null 2>&1; then
        log "警告: 系统中未检测到 web server 环境 (apache2/nginx/lighttpd)"
        log "Landscape Router 需要 web server 环境才能正常运行"
        log "缺少 web server 可能会导致主机失联问题"
    else
        WEB_SERVER_PREINSTALLED=true
        # 确定已安装的web server类型
        if dpkg -l | grep -q apache2; then
            WEB_SERVER_TYPE="apache2"
        elif command -v nginx >/dev/null 2>&1; then
            WEB_SERVER_TYPE="nginx"
        elif command -v lighttpd >/dev/null 2>&1; then
            WEB_SERVER_TYPE="lighttpd"
        fi
        log "检测到系统已安装 web server 环境: $WEB_SERVER_TYPE"
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
    
    # 检查是否安装了 curl 或 wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log "错误: 系统中未找到 curl 或 wget，至少需要安装其中一个工具"
        exit 1
    elif command -v curl >/dev/null 2>&1; then
        log "检测到系统已安装 curl"
    elif command -v wget >/dev/null 2>&1; then
        log "检测到系统已安装 wget"
    fi

    log "系统环境检查完成"

    # 检查系统发行版
    local system_id=""
    local system_name=""
    if [ -f "/etc/os-release" ]; then
        system_id=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        system_name=$(grep "^NAME=" /etc/os-release | cut -d'=' -f2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
    fi
    
    # 检查是否为支持的系统
    local supported_system=false
    case "$system_id" in
        "debian"|"armbian"|"raspbian")
            supported_system=true
            ;;
        *)
            # 检查名称中是否包含支持的系统名
            if echo "$system_name" | grep -qE "(debian|armbian|raspbian)"; then
                supported_system=true
            fi
            ;;
    esac
    
    # 对于非支持的系统，询问是否继续
    if [ "$supported_system" = false ]; then
        echo "警告: 检测到您的系统为 $system_name ($system_id)。"
        echo "警告: 此系统未经测试，可能存在兼容性问题。"
        read -rp "是否继续安装? (y/n): " answer
        if [[ "$answer" =~ ^[Nn]$ ]]; then
            log "用户选择退出安装"
            exit 0
        fi
    fi
}

# 询问用户配置
ask_user_config() {
    log "开始询问用户配置"
    echo "=============================="
    # 提示用户所有问题回答完成后可以再次修改
    echo ""
    echo "注意: 您需要回答以下所有问题, 回答结束后可以检查和修改任何配置项。"
    echo ""
    echo "-----------------------------"
    # 检查web server环境
    ask_webserver
    
    echo "-----------------------------"
    # 询问是否修改时区为中国上海
    read -rp "是否将系统时区修改为亚洲/上海? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        TIMEZONE_SHANGHAI=true
    fi
    echo "-----------------------------"

    # 询问是否关闭 swap
    read -rp "是否禁用 swap (虚拟内存) ? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        SWAP_DISABLED=true
    fi
    echo "-----------------------------"

    # 询问是否换源 (仅对支持的系统进行询问)
    # 检查是否为支持换源的系统 (Debian, Ubuntu, Linux Mint, Armbian, Raspbian)
    ask_apt_mirror
    echo "-----------------------------"

    # 询问是否安装 Docker
    read -rp "是否安装 Docker(含compose)? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        DOCKER_INSTALLED=true
        
        # 询问 Docker 镜像源
        ask_docker_mirror
        
        # 询问是否为 Docker 开启 IPv6
        read -rp "是否为 Docker 开启 IPv6 支持? (y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            DOCKER_ENABLE_IPV6=true
        fi
    fi
    echo "-----------------------------"

    # 询问是否安装 ppp 用于 pppoe 拨号
    read -rp "是否安装 ppp 用于 pppoe 拨号? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        INSTALL_PPP=true
    fi
    echo "-----------------------------"

    # 询问是否使用 GitHub 镜像加速
    ask_github_mirror
    echo "-----------------------------"
    
    # 询问是否下载 handler
    ask_download_handler
    echo "-----------------------------"
    
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
    echo "-----------------------------"

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
    echo "-----------------------------"
    
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
            if [ "$USE_CUSTOM_MIRROR" = true ]; then
                case "$MIRROR_SOURCE" in
                    "ustc") mirror_name="中国科学技术大学" ;;
                    "tsinghua") mirror_name="清华大学" ;;
                    "aliyun") mirror_name="阿里云" ;;
                    "sjtu") mirror_name="上海交通大学" ;;
                    "zju") mirror_name="浙江大学" ;;
                    "nju") mirror_name="南京大学" ;;
                    "hit") mirror_name="哈尔滨工业大学" ;;
                esac
            fi
            echo "   镜像源: $mirror_name"
        fi
        # 只有当web server不是预装时才显示web server安装选项
        if [ "$WEB_SERVER_PREINSTALLED" != true ]; then
            echo "4. 安装 Web Server: $([ "$WEB_SERVER_INSTALLED" = true ] && echo "是" || echo "否")"
            if [ "$WEB_SERVER_INSTALLED" = true ]; then
                echo "   Web Server 类型: $WEB_SERVER_TYPE"
            fi
        else
            echo "4. 检测到系统已预装 Web Server: $WEB_SERVER_TYPE"
        fi
        echo "5. 安装 Docker(含compose): $([ "$DOCKER_INSTALLED" = true ] && echo "是" || echo "否")"
        if [ "$DOCKER_INSTALLED" = true ]; then
            echo "   Docker 镜像源: $DOCKER_MIRROR"
            echo "   Docker IPv6 支持: $([ "$DOCKER_ENABLE_IPV6" = true ] && echo "是" || echo "否")"
        fi
        echo "6. 安装 ppp (用于 PPPOE 拨号): $([ "$INSTALL_PPP" = true ] && echo "是" || echo "否")"
        echo "7. 使用 GitHub 镜像加速: $([ "$USE_GITHUB_MIRROR" = true ] && echo "是" || echo "否")"
        if [ "$USE_GITHUB_MIRROR" = true ]; then
            echo "   GitHub 镜像地址: $GITHUB_MIRROR"
        fi
        echo "8. 下载 redirect_pkg_handler: $([ "$DOWNLOAD_HANDLER" = true ] && echo "是" || echo "否")"
        if [ "$DOWNLOAD_HANDLER" = true ]; then
            echo "   要下载的 handler 版本: ${HANDLER_ARCHITECTURES[*]}"
        fi
        echo "9. Landscape Router 安装路径: $LANDSCAPE_DIR"
        echo "10. 管理员账号: $ADMIN_USER"
        echo "    管理员密码: $ADMIN_PASS"
        echo "11. LAN 网桥配置:"
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
            done)
                config_confirmed=true
                ;;
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
                # 询问是否换源 (仅对支持的系统进行询问)
                # 检查是否为支持换源的系统 (Debian, Ubuntu, Linux Mint, Armbian, Raspbian)
                ask_apt_mirror
                ;;
            4)
                # 只有当web server不是预装时才允许修改web server配置
                ask_webserver
                ;;
            5)
                read -rp "是否安装 Docker(含compose)? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    # 检查是否已安装 curl，如未安装则提醒会自动安装
                    if ! command -v curl &> /dev/null; then
                        echo "注意: 系统未安装 curl，安装 Docker 时将自动安装 curl"
                    fi
                    
                    DOCKER_INSTALLED=true
                    
                    ask_docker_mirror
                    
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
            6)
                read -rp "是否安装 ppp 用于 pppoe 拨号? (y/n): " answer
                if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                    INSTALL_PPP=true
                else
                    INSTALL_PPP=false
                fi
                ;;
            7)
                ask_github_mirror
                ;;
            8)
                ask_download_handler
                ;;
            9)
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
            10)
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
            11)
                config_lan_interface
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

ask_apt_mirror() { 

    # 询问是否换源 (仅对支持的系统进行询问)
    # 检查是否为支持换源的系统 (Debian, Ubuntu, Linux Mint, Armbian, Raspbian)
    if grep -q "Debian" /etc/os-release || grep -q "Ubuntu" /etc/os-release || grep -q "Linux Mint" /etc/os-release || grep -q "Armbian" /etc/os-release || grep -q "Raspbian" /etc/os-release || grep -q "Raspberry Pi OS" /etc/os-release; then
        USE_CUSTOM_MIRROR=true
        
        # 询问使用哪个镜像源
        echo "请选择要使用的镜像源:"
        echo "0) 不换源"
        echo "1) 阿里云（默认）"
        echo "2) 清华大学"
        echo "3) 上海交通大学"
        echo "4) 浙江大学"
        echo "5) 中国科学技术大学"
        echo "6) 南京大学"
        echo "7) 哈尔滨工业大学"
        read -rp "请选择 (0-7, 默认为 1 阿里云 ): " answer
        case "$answer" in
            1|"") 
                MIRROR_SOURCE="aliyun"
                ;;
            2) 
                MIRROR_SOURCE="tsinghua"
                ;;
            3) 
                MIRROR_SOURCE="sjtu"
                ;;
            4)
                MIRROR_SOURCE="zju"
                ;;
            5)
                MIRROR_SOURCE="ustc"
                ;;
            6)
                MIRROR_SOURCE="nju"
                ;;
            7)
                MIRROR_SOURCE="hit"
                ;;
            *)
                USE_CUSTOM_MIRROR=false
                ;;
        esac
    else
        echo "当前系统不支持自动换源功能"
        echo "仅支持 Debian、Ubuntu、Linux Mint、Armbian 和 Raspbian 系统换源"
    fi

}

ask_webserver() { 
    # 只有当web server不是预装时才允许修改web server配置
    if [ "$WEB_SERVER_PREINSTALLED" != true ]; then
        echo "Landscape Router 需要 web server 环境才能正常运行"
        echo "缺少 web server 可能会导致主机失联问题"
        echo ""
        echo "本脚本中 web server 环境 检测/安装 的功能未经验证"
        echo "建议自行处理后, 再执行安装脚本"
        echo ""
        echo "请选择要安装的 Web Server:"
        echo "1) 退出安装脚本, 自行处理 (推荐)(默认)"
        echo "2) Apache2"
        echo "3) Nginx"
        echo "4) Lighttpd"
        echo "5) 继续安装脚本，不安装 web server"
        read -rp "请选择 (1-5, 默认为 1): " webserver_choice
        case "$webserver_choice" in
            2)
                WEB_SERVER_INSTALLED=true
                WEB_SERVER_TYPE="apache2"
                ;;
            3)
                WEB_SERVER_INSTALLED=true
                WEB_SERVER_TYPE="nginx"
                ;;
            4)
                WEB_SERVER_INSTALLED=true
                WEB_SERVER_TYPE="lighttpd"
                ;;
            5)
                WEB_SERVER_INSTALLED=false
                WEB_SERVER_TYPE=""
                ;;
            *)
                log "用户选择退出安装"
                exit 1
                ;;
        esac
    else
        echo "系统已预装 web server ($WEB_SERVER_TYPE)，无法修改此配置"
    fi

}

ask_docker_mirror() {
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
}

ask_github_mirror() { 
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
}


# 暂不支持 aarch64-musl
# 询问是否下载 handler 及选择架构
ask_download_handler() {
    echo ""
    echo "redirect_pkg_handler 是 分流到 Docker 容器 功能不可缺少该组件"
    echo ""
    read -rp "是否下载 redirect_pkg_handler 相关文件? (y/n): " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
        DOWNLOAD_HANDLER=true
        
        # 获取系统架构
        local system_arch
        system_arch=$(uname -m)
        
        echo "请选择要下载的 redirect_pkg_handler 版本 (可多选，用空格分隔):"
        # 根据系统架构提供相应的选项
        case "$system_arch" in
            x86_64)
                echo "1) musl 版（适用于 Alpine 等构建的镜像）(常见)"
                echo "2) Glibc 版（适用于 Debian 等构建的镜像）"
                echo "3) 全选"
                read -rp "请输入选项 (默认为 1): " handler_choice
                
                # 默认选择 x86_64
                if [ -z "$handler_choice" ]; then
                    handler_choice="1"
                fi
                
                # 根据选择设置要下载的架构
                HANDLER_ARCHITECTURES=()
                if [[ "$handler_choice" =~ 3 ]]; then
                    HANDLER_ARCHITECTURES=("x86_64" "x86_64-musl")
                else
                    [[ "$handler_choice" =~ 1 ]] && HANDLER_ARCHITECTURES+=("x86_64-musl")
                    [[ "$handler_choice" =~ 2 ]] && HANDLER_ARCHITECTURES+=("x86_64")
                fi
                ;;
            aarch64)
                # echo "1) musl 版（适用于 Alpine 等构建的镜像）"
                echo "2) Glibc 版（适用于 Debian 等构建的镜像）"
                # echo "3) 全选"
                read -rp "请输入选项 (默认为 2): " handler_choice
                
                # 默认选择 aarch64
                if [ -z "$handler_choice" ]; then
                    handler_choice="2"
                fi
                
                # 根据选择设置要下载的架构
                HANDLER_ARCHITECTURES=()
                if [[ "$handler_choice" =~ 3 ]]; then
                    HANDLER_ARCHITECTURES=("aarch64")
                else
                    [[ "$handler_choice" =~ 1 ]] && HANDLER_ARCHITECTURES+=("aarch64-musl")
                    [[ "$handler_choice" =~ 2 ]] && HANDLER_ARCHITECTURES+=("aarch64")
                fi
                ;;
            *)
                echo "检测到不常见的系统架构: $system_arch"
                echo "1) x86_64 musl 版（适用于 Alpine 等构建的镜像）"
                echo "2) x86_64 Glibc 版（适用于 Debian 等构建的镜像）"
                # echo "3) aarch64 musl 版（适用于 Alpine 等构建的镜像）"
                echo "4) aarch64 Glibc 版（适用于 Debian 等构建的镜像）"
                echo "5) 全选"
                read -rp "请输入选项 (默认为 5): " handler_choice
                
                # 默认全选
                if [ -z "$handler_choice" ]; then
                    handler_choice="5"
                fi
                
                # 根据选择设置要下载的架构
                HANDLER_ARCHITECTURES=()
                if [[ "$handler_choice" =~ 5 ]]; then
                    HANDLER_ARCHITECTURES=("x86_64" "x86_64-musl" "aarch64")
                else
                    [[ "$handler_choice" =~ 1 ]] && HANDLER_ARCHITECTURES+=("x86_64-musl")
                    [[ "$handler_choice" =~ 2 ]] && HANDLER_ARCHITECTURES+=("x86_64")
                    # [[ "$handler_choice" =~ 3 ]] && HANDLER_ARCHITECTURES+=("aarch64-musl")
                    [[ "$handler_choice" =~ 4 ]] && HANDLER_ARCHITECTURES+=("aarch64")
                fi
                ;;
        esac
        
        echo "将下载以下版本的 handler: ${HANDLER_ARCHITECTURES[*]}"
    else
        DOWNLOAD_HANDLER=false
    fi
}

# 配置 LAN 网卡
config_lan_interface() {
    echo ""
    echo "WAN 配置，请稍候在 UI 中进行"
    echo ""
    echo "现在开始配置 LAN 网桥"
    
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
    valid_ip() {
        local ip=$1
        local stat=1
        
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            IFS='.' read -r -a ip_parts <<< "$ip"
            
            # 检查每个部分是否为0-255之间的有效值
            if [ "${ip_parts[0]}" -ge 0 ] && [ "${ip_parts[0]}" -le 255 ] && \
               [ "${ip_parts[1]}" -ge 0 ] && [ "${ip_parts[1]}" -le 255 ] && \
               [ "${ip_parts[2]}" -ge 0 ] && [ "${ip_parts[2]}" -le 255 ] && \
               [ "${ip_parts[3]}" -ge 0 ] && [ "${ip_parts[3]}" -le 255 ]; then
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
            
            # 检查是否在同一子网
            if [ "${start_octets[0]}" -eq "${end_octets[0]}" ] && \
               [ "${start_octets[1]}" -eq "${end_octets[1]}" ] && \
               [ "${start_octets[2]}" -eq "${end_octets[2]}" ]; then
                # 检查结束地址是否大于起始地址
                if [ "${end_octets[3]}" -gt "${start_octets[3]}" ]; then
                    break
                else
                    echo "DHCP 结束地址必须大于起始地址"
                fi
            else
                echo "DHCP 起始和结束地址必须在同一子网"
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
    
    # 7. 检查并安装 webserver
    # 当系统已安装web server时，不再执行安装
    if [ "$WEB_SERVER_INSTALLED" = true ] && [ -n "$WEB_SERVER_TYPE" ]; then
        if ! dpkg -l | grep -q "$WEB_SERVER_TYPE" && ! command -v "$WEB_SERVER_TYPE" >/dev/null 2>&1; then
            log "检测到系统未安装 $WEB_SERVER_TYPE, 将自动安装"
            install_webserver
        else
            log "检测到系统已安装 $WEB_SERVER_TYPE，跳过安装"
        fi
    # elif [ "$WEB_SERVER_INSTALLED" = true ] && [ -z "$WEB_SERVER_TYPE" ]; then
    else
        log "用户选择不安装 web server, 跳过安装步骤"
    fi
    
    # 8. 安装 Docker
    if [ "$DOCKER_INSTALLED" = true ]; then
        install_docker
        configure_docker
    fi
    
    
    # 9. 安装 ppp
    if [ "$INSTALL_PPP" = true ]; then
        install_ppp
    fi
    
    # 10. 下载 handler
    if [ "$DOWNLOAD_HANDLER" = true ]; then
        download_handlers
    fi
    
    # 11. 配置网络接口
    configure_network_interfaces
    
    # 12. 创建管理员账号密码配置文件
    # 认证配置已合并到 landscape_init.toml 中，不再需要单独调用
    
    # 13. 关闭本机 DNS 服务
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
    if grep -q "Debian" /etc/os-release || grep -q "Ubuntu" /etc/os-release || grep -q "Linux Mint" /etc/os-release || grep -q "Armbian" /etc/os-release || grep -q "Raspbian" /etc/os-release || grep -q "Raspberry Pi OS" /etc/os-release; then
        is_supported=true
    fi
    
    if [ "$is_supported" = false ]; then
        log "警告: 不支持的系统类型，仅支持 Debian、Ubuntu、Linux Mint、Armbian 和 Raspbian"
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
            # 从版本描述中提取Ubuntu代号，例如从 "21.2 (Victoria)" 提取 "Victoria"
            # 或者从 "20.3 (Una)" 提取 "focal" (因为Linux Mint 20.x基于Ubuntu 20.04/focal)
            if [[ $version_desc =~ \((.*)\) ]]; then
                local mint_codename="${BASH_REMATCH[1],,}"  # 转换为小写
                
                # 根据Linux Mint代号映射到Ubuntu代号
                case "$mint_codename" in
                    "vanessa"|"vera"|"victoria"|"virginia") 
                        version_codename="jammy"  # Ubuntu 22.04
                        ;;
                    "una"|"uma"|"ulyssa"|"ulyana"|"julia")
                        version_codename="focal"  # Ubuntu 20.04
                        ;;
                    "tricia"|"tina"|"tessa"|"tara"|"ulyana")
                        version_codename="bionic" # Ubuntu 18.04
                        ;;
                    *)
                        version_codename="focal"  # 默认使用 focal
                        ;;
                esac
            else
                version_codename="focal"  # 默认使用 focal
            fi
        fi
    elif grep -q "Armbian" /etc/os-release; then
        system_type="armbian"
        system_version=$(grep "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        version_codename=$(grep "VERSION_CODENAME" /etc/os-release | cut -d'=' -f2)
        # 如果没有 VERSION_CODENAME，尝试从其他字段获取
        if [ -z "$version_codename" ]; then
            # Armbian 通常基于 Debian，尝试获取 Debian 版本代号
            version_codename=$(grep "DEBIAN_VERSION" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        fi
        # 如果仍然为空，则使用默认值
        if [ -z "$version_codename" ]; then
            version_codename="bullseye"  # 默认使用 bullseye
        fi
    elif grep -q "Raspbian" /etc/os-release || grep -q "Raspberry Pi OS" /etc/os-release; then
        system_type="raspbian"
        system_version=$(grep "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
        version_codename=$(grep "VERSION_CODENAME" /etc/os-release | cut -d'=' -f2)
        # 如果没有 VERSION_CODENAME，则使用默认值
        if [ -z "$version_codename" ]; then
            version_codename="bullseye"  # 默认使用 bullseye
        fi
    fi
    
    # 确定使用的镜像源URL - 优化后的实现
    local mirror_url=""
    # 构建镜像源映射关系，减少重复代码
    local mirror_base=""
    case "$MIRROR_SOURCE" in
        "ustc")      mirror_base="https://mirrors.ustc.edu.cn" ;;
        "tsinghua")  mirror_base="https://mirrors.tuna.tsinghua.edu.cn" ;;
        "aliyun")    mirror_base="https://mirrors.aliyun.com" ;;
        "sjtu")      mirror_base="https://mirror.sjtu.edu.cn" ;;
        "zju")       mirror_base="https://mirrors.zju.edu.cn" ;;
        "nju")       mirror_base="https://mirrors.nju.edu.cn" ;;
        "hit")       mirror_base="https://mirrors.hit.edu.cn" ;;
    esac
    
    # 根据系统类型设置镜像URL
    case "$system_type" in
        "debian")    mirror_url="${mirror_base}/debian/" ;;
        "raspbian")  mirror_url="${mirror_base}/raspbian/raspbian/" ;;
        "ubuntu")    mirror_url="${mirror_base}/ubuntu/" ;;
        "linuxmint") mirror_url="${mirror_base}/linuxmint/" ;;
        "armbian")   mirror_url="${mirror_base}/armbian/" ;;
    esac
    
    log "系统类型: $system_type"
    log "系统版本: $system_version"
    log "版本代号: $version_codename"
    log "使用镜像源: $MIRROR_SOURCE ($mirror_url)"
    
    local timestamp
    timestamp=$(date +"%Y_%m_%d-%H_%M_%S-%3N")

    # 备份原源，仅在第一次换源时进行
    if [ "$APT_SOURCE_BACKED_UP" = false ] && [ -f "/etc/apt/sources.list" ]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.pre-fail-$timestamp.bak
        APT_SOURCE_BACKED_UP=true
        log "已备份原始源文件到 /etc/apt/sources.list.pre-fail-$timestamp.bak"
    fi
    
    # 根据系统类型生成对应的源列表
    case "$system_type" in
        "debian"|"armbian"|"raspbian")
            # 如果无法获取版本代号，则使用通用代号
            if [ -z "$version_codename" ]; then
                version_codename="stable"
            fi
            
            # 针对不同镜像源，Debian/Armbian/Raspbian 安全更新使用专门的URL
            local security_mirror_url="$mirror_url"
            case "$MIRROR_SOURCE" in
                "sjtu"|"zju"|"nju"|"hit")
                    # 高校镜像站等使用独立的安全更新路径
                    security_mirror_url="https://${MIRROR_SOURCE}.debian.org/debian-security/"
                    ;;
                *)
                    # 默认使用镜像站的debian-security子路径
                    security_mirror_url="${mirror_url}debian-security/"
                    ;;
            esac
            
            # 特别处理 Debian 12 (bookworm) 及以上版本的安全更新源
            if [ "$system_type" = "debian" ] || [ "$system_type" = "armbian" ] || [ "$system_type" = "raspbian" ]; then
                if [[ "$version_codename" > "bullseye" ]]; then
                    security_mirror_url="https://security.debian.org/debian-security"
                fi
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

deb $security_mirror_url $version_codename-security main contrib non-free non-free-firmware
# deb-src $security_mirror_url $version_codename-security main contrib non-free non-free-firmware
EOF
            ;;
            
        "ubuntu"|"linuxmint")
            # 如果无法获取版本代号，则使用通用代号
            if [ -z "$version_codename" ]; then
                version_codename="focal"  # 默认使用 focal
            fi
            
            # 针对不同镜像源，Ubuntu/Linux Mint 安全更新使用专门的URL
            local ubuntu_security_mirror_url="$mirror_url"
            case "$MIRROR_SOURCE" in
                "sjtu"|"zju"|"nju"|"hit")
                    # 高校镜像站等使用独立的安全更新路径
                    ubuntu_security_mirror_url="https://${MIRROR_SOURCE}.ubuntu.com/ubuntu-security/"
                    ;;
                *)
                    # 默认使用镜像站的ubuntu-security子路径
                    ubuntu_security_mirror_url="${mirror_url}ubuntu-security/"
                    ;;
            esac
            
            # 特别处理 Ubuntu 22.04 (jammy) 及以上版本的安全更新源
            if [[ "$version_codename" > "focal" ]]; then
                ubuntu_security_mirror_url="https://security.ubuntu.com/ubuntu"
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

deb $ubuntu_security_mirror_url $version_codename-security main restricted universe multiverse
# deb-src $ubuntu_security_mirror_url $version_codename-security main restricted universe multiverse
EOF
            ;;
    esac
    
    # 更新包索引
    apt_update
    
    log "apt 软件源更换完成"
}


# 安装 webserver
install_webserver() {
    log "安装 Web Server: $WEB_SERVER_TYPE"
    apt_update
    
    case "$WEB_SERVER_TYPE" in
        "apache2")
            apt_install "apache2"
            ;;
        "nginx")
            apt_install "nginx"
            ;;
        "lighttpd")
            apt_install "lighttpd"
            ;;
        *)
            log "未知的 Web Server 类型: $WEB_SERVER_TYPE"
            apt_install "apache2"
            WEB_SERVER_TYPE="apache2"
            ;;
    esac
}

# 安装 Docker
install_docker() {
    log "安装 Docker(含compose)"
    
    # 检查 curl 是否已安装, 未安装则安装
    if ! command -v curl &> /dev/null; then
        log "未检测到 curl, 正在安装..."
        apt_update
        apt_install "curl"
    else
        log "curl 已安装"
    fi
    
    local retry=0
    local max_retry=3
    local user_choice=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在安装 Docker(含compose) 耗时较长 请稍候 (尝试 $((retry+1))/$max_retry)"
            
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
            log "Docker(含compose) 安装失败"
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "Docker(含compose) 安装失败, 请选择操作:"
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
                    ask_docker_mirror
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
    
    log "错误: Docker(含compose) 安装失败"
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
                echo "apt update 失败, 是否再次尝试3次？(y/n) 或输入 'm' 选择镜像源: "
                read -r user_choice
                user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
                
                # 如果用户选择换源
                if [ "$user_choice" = "m" ]; then
                    ask_apt_mirror
                    change_apt_mirror
                    user_choice="y"  # 重置选择以便继续循环
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
            echo "软件包 $packages 安装失败, 是否再次尝试3次？(y/n) 或输入 'm' 选择镜像源: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择换源
            if [ "$user_choice" = "m" ]; then
                ask_apt_mirror
                change_apt_mirror
                user_choice="y"  # 重置选择以便继续循环
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
    
    # 在 Landscape 目录下创建 script_logs 目录
    mkdir -p "$LANDSCAPE_DIR/script_logs"
    
    # 将临时日志移动到 Landscape 目录下
    if [ -f "$INSTALL_LOG" ]; then
        local log_filename
        log_filename=$(basename "$INSTALL_LOG")
        
        # 先尝试直接移动日志文件
        if ! mv "$INSTALL_LOG" "$LANDSCAPE_DIR/script_logs/$log_filename" 2>/dev/null; then
            # 如果直接移动失败, 尝试复制并清理原文件
            cp "$INSTALL_LOG" "$LANDSCAPE_DIR/script_logs/$log_filename" && rm -f "$INSTALL_LOG"
        fi
        
        # 更新日志文件路径
        INSTALL_LOG="$LANDSCAPE_DIR/script_logs/$log_filename"
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
            log "正在下载 $binary_filename  耗时较长 请稍候 (尝试 $((retry+1))/$max_retry)"
            if command -v wget >/dev/null 2>&1; then
                if wget -O "$LANDSCAPE_DIR/$binary_filename" "$binary_url"; then
                    log "$binary_filename 下载成功"
                    break
                fi
            elif command -v curl >/dev/null 2>&1; then
                if curl -fSL --progress-bar -o "$LANDSCAPE_DIR/$binary_filename" "$binary_url"; then
                    log "$binary_filename 下载成功"
                    break
                fi
            fi
            retry=$((retry+1))
            log "下载失败, 等待 5 秒后重试"
            sleep 5
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "下载 $binary_filename 失败, 是否再次尝试3次？(y/n) 或输入 'm' 使用 GitHub 镜像加速: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择使用 GitHub 镜像加速
            if [ "$user_choice" = "m" ]; then
                ask_github_mirror
                
                if [ "$USE_GITHUB_MIRROR" = true ]; then
                    # 更新下载 URL
                    binary_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_filename"
                    user_choice="y"  # 重置选择以便继续循环
                    retry=0  # 重置重试计数
                fi
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
            log "正在下载 static.zip 耗时较长 请稍候(尝试 $((retry+1))/$max_retry)"
            if command -v wget >/dev/null 2>&1; then
                if wget -O /tmp/static.zip "$static_url"; then
                    log "static.zip 下载成功"
                    break
                fi
            elif command -v curl >/dev/null 2>&1; then
                if curl -fSL --progress-bar -o /tmp/static.zip "$static_url"; then
                    log "static.zip 下载成功"
                    break
                fi
            fi
            retry=$((retry+1))
            log "下载失败, 等待 5 秒后重试"
            sleep 5
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "下载 static.zip 失败, 是否再次尝试3次？(y/n) 或输入 'm' 使用 GitHub 镜像加速: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择使用 GitHub 镜像加速
            if [ "$user_choice" = "m" ]; then
                ask_github_mirror
                
                if [ "$USE_GITHUB_MIRROR" = true ]; then
                    # 更新下载 URL
                    static_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
                    user_choice="y"  # 重置选择以便继续循环
                    retry=0  # 重置重试计数
                fi
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

# 下载 handler 文件
download_handlers() {
    log "开始下载 redirect_pkg_handler 文件"
    
    # 不再创建单独的 handler 目录，直接使用 LANDSCAPE_DIR
    
    # 检查 curl 是否已安装, 未安装则安装
    if ! command -v curl &> /dev/null; then
        log "未检测到 curl, 正在安装..."
        apt_update
        apt_install "curl"
    else
        log "curl 已安装"
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
    
    # 下载 redirect_pkg_handler.sh 脚本
    local handler_script_url
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        handler_script_url="$GITHUB_MIRROR/https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh"
    else
        handler_script_url="https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh"
    fi
    
    local retry=0
    local max_retry=3
    local user_choice=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在下载 redirect_pkg_handler.sh 脚本 (尝试 $((retry+1))/$max_retry)"
            if command -v wget >/dev/null 2>&1; then
                if wget -O "$LANDSCAPE_DIR/redirect_pkg_handler.sh" "$handler_script_url"; then
                    log "redirect_pkg_handler.sh 下载成功"
                    break
                fi
            elif command -v curl >/dev/null 2>&1; then
                if curl -fSL --progress-bar -o "$LANDSCAPE_DIR/redirect_pkg_handler.sh" "$handler_script_url"; then
                    log "redirect_pkg_handler.sh 下载成功"
                    break
                fi
            fi
            retry=$((retry+1))
            log "下载失败, 等待 5 秒后重试"
            sleep 5
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "下载 redirect_pkg_handler.sh 失败, 是否再次尝试3次？(y/n) 或输入 'm' 使用 GitHub 镜像加速: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择使用 GitHub 镜像加速
            if [ "$user_choice" = "m" ]; then
                ask_github_mirror
                
                if [ "$USE_GITHUB_MIRROR" = true ]; then
                    # 更新下载 URL
                    handler_script_url="$GITHUB_MIRROR/https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh"
                    user_choice="y"  # 重置选择以便继续循环
                    retry=0  # 重置重试计数
                fi
            fi
        else
            # 下载成功则跳出循环
            break
        fi
    done
    
    if [ $retry -eq $max_retry ] && [ "$user_choice" = "n" ]; then
        log "错误: 下载 redirect_pkg_handler.sh 失败"
        exit 1
    fi
    
    # 为脚本添加执行权限
    chmod +x "$LANDSCAPE_DIR/redirect_pkg_handler.sh"
    log "已为 redirect_pkg_handler.sh 添加执行权限"
    
    # 下载各个架构的 handler 二进制文件
    for arch in "${HANDLER_ARCHITECTURES[@]}"; do
        local handler_filename="redirect_pkg_handler-$arch"
        local handler_url
        
        if [ "$USE_GITHUB_MIRROR" = true ]; then
            handler_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$handler_filename"
        else
            handler_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/$handler_filename"
        fi
        
        retry=0
        user_choice=""
        
        while [ "$user_choice" != "n" ]; do
            retry=0
            while [ $retry -lt $max_retry ]; do
                log "正在下载 $handler_filename (尝试 $((retry+1))/$max_retry)"
                if command -v wget >/dev/null 2>&1; then
                    if wget -O "$LANDSCAPE_DIR/$handler_filename" "$handler_url"; then
                        log "$handler_filename 下载成功"
                        break
                    fi
                elif command -v curl >/dev/null 2>&1; then
                    if curl -fSL --progress-bar -o "$LANDSCAPE_DIR/$handler_filename" "$handler_url"; then
                        log "$handler_filename 下载成功"
                        break
                    fi
                fi
                retry=$((retry+1))
                log "下载失败, 等待 5 秒后重试"
                sleep 5
            done
            
            if [ $retry -eq $max_retry ]; then
                echo "下载 $handler_filename 失败, 是否再次尝试3次？(y/n) 或输入 'm' 使用 GitHub 镜像加速: "
                read -r user_choice
                user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
                
                # 如果用户选择使用 GitHub 镜像加速
                if [ "$user_choice" = "m" ]; then
                    ask_github_mirror
                    
                    if [ "$USE_GITHUB_MIRROR" = true ]; then
                        # 更新下载 URL
                        handler_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$handler_filename"
                        user_choice="y"  # 重置选择以便继续循环
                        retry=0  # 重置重试计数
                    fi
                fi
            else
                # 下载成功则跳出循环
                break
            fi
        done
        
        if [ $retry -eq $max_retry ] && [ "$user_choice" = "n" ]; then
            log "错误: 下载 $handler_filename 失败"
            exit 1
        fi
        
        # 为二进制文件添加执行权限
        chmod +x "$LANDSCAPE_DIR/$handler_filename"
        log "已为 $handler_filename 添加执行权限"
    done
    
    log "所有 redirect_pkg_handler 文件下载完成"
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

    # 获取所有网络接口
    local all_interfaces
    all_interfaces=$(ip link show | awk -F': ' '/^[0-9]+: [a-zA-Z]/ {print $2}' | grep -v lo)
    
    # 处理所有网卡，将物理网卡设置为manual模式（排除虚拟网卡）
    for iface in $all_interfaces; do
        # 跳过虚拟网卡 (docker、veth、br、tap、tun等开头的接口)
        if [[ "$iface" =~ ^(docker|veth|br|tap|tun|vboxnet|vmnet|macvtap|ip6tnl|sit|gre|gretap|erspan|ipip|ip6gre|ip6gretap|ip6erspan|vti|vti6|nlmon|nflog|nfqueue|vcan|vxcan|mpls|rwl|wwan|ppp|sl|isdn|hdlc|arc|appletalk|rose|netrom|ax25|dccp|sctp|llc|ieee802154|caif|caif6|caif2|caif4|caif5|caif7|caif8|caif9|caif10|caif11|caif12|caif13|caif14|caif15|caif16|caif17|caif18|caif19|caif20) ]]; then
            log "跳过虚拟网卡: $iface"
            continue
        fi
        
        # 将物理网卡设置为manual模式
        log "将物理网卡 $iface 设置为 manual 模式"
        cat >> /etc/network/interfaces << EOF
auto $iface
iface $iface inet manual

EOF
    done
    
    log "LAN 网桥配置开始"
    # 创建 landscape_init.toml 配置文件
    create_landscape_init_toml
    
    log "LAN 网桥配置完成"
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
# ==== Create $bridge_name bridge ====
[[ifaces]]
name = "$bridge_name"
create_dev_type = "bridge"
zone_type = "lan"
enable_in_boot = true
wifi_mode = "undefined"

# Enable ebpf routing for $bridge_name
[[route_lans]]
iface_name = "$bridge_name"
enable = true

# ==== 绑定网卡到 $bridge_name 网桥 ====
# ==== Bind interfaces to $bridge_name bridge ====
EOF

    # 添加绑定的物理接口
    IFS=', ' read -r -a iface_array <<< "$interfaces_list"
    if [ ${#iface_array[@]} -eq 0 ]; then
        log "警告: 未找到要绑定到网桥的物理接口"
    else
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
    fi

    cat >> "$LANDSCAPE_DIR/landscape_init.toml" << EOF

# ==== 为 $bridge_name 配置 DHCP 服务====
# ==== Configure DHCP for $bridge_name ====
[[dhcpv4_services]]
iface_name = "$bridge_name"
enable = true

[dhcpv4_services.config]
ip_range_start = "$dhcp_start"
ip_range_end = "$dhcp_end"
server_ip_addr = "$lan_ip"
network_mask = $network_mask
mac_binding_records = []

# ==== 管理员账号配置 ====
# ==== Administrator account configuration ====
[config.auth]
# 管理员 用户名 和 密码
# Administrator username and password
admin_user = "$ADMIN_USER"
admin_pass = "$ADMIN_PASS"
EOF

    log "landscape_init.toml 配置文件创建完成"
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

# 调用主函数启动脚本执行
main "$@"
