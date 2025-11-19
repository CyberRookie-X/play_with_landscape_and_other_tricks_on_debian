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
# NTP 相关变量
CONFIGURE_NTP=false         # 是否配置 NTP 服务器
NTP_CLIENT_TYPE="chrony"    # NTP 客户端类型 (chrony/ntp)
NTP_PRIMARY_SERVER="aliyun" # 主要 NTP 服务器
NTP_SERVERS_CONFIGURED=""   # 已配置的 NTP 服务器列表

# 下载工具相关全局变量
HAS_WGET=false              # 系统是否有 wget
HAS_CURL=false              # 系统是否有 curl
PREFERRED_DOWNLOAD_TOOL=""  # 首选下载工具 ("wget" 或 "curl")

# 系统信息相关全局变量
SYSTEM_TYPE=""              # 系统类型 (debian/ubuntu/linuxmint/armbian/raspbian)
SYSTEM_VERSION=""           # 系统版本号
SYSTEM_CODENAME=""          # 系统代号 (如 bullseye/focal/jammy)
SYSTEM_ARCH=""              # 系统架构 (x86_64/aarch64)
SYSTEM_INFO_INITIALIZED=false  # 系统信息是否已初始化

# 内核版本相关全局变量
KERNEL_VERSION=""               # 当前内核版本（纯数字）
KERNEL_BUG_REGEX="^6\.12\.(49|[5-9][0-9]|[1-9][0-9]{2,})$"            # 存在bug的内核版本正则表达式，6.12.49 到 6.12.999
# KERNEL_BUG_REGEX="^6\.(1[0-9]|2[0-9])\."  # 示例：6.10-6.29 版本可能有问题
KERNEL_HAS_BUG=false           # 当前内核版本是否存在bug（bool值）
UPGRADE_KERNEL=false           # 是否需要升级内核

# 主逻辑
main() {
        # 显示安装脚本大标题
    echo ""
    echo "============================================================================"
    echo "============================================================================"
    echo "=====                                                                  ====="
    echo "=====                    Landscape Router 安装脚本                     ====="
    echo "=====                                                                  ====="
    echo "============================================================================"
    echo "============================================================================"
    echo ""

    # 初始化临时日志
    init_temp_log
    
    log "Landscape Router 交互式安装脚本开始执行"

    # 初始化系统信息（在检查系统环境之前）
    init_system_info

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

# 初始化系统信息
init_system_info() {
    if [ "$SYSTEM_INFO_INITIALIZED" = true ]; then
        log "系统信息已初始化，跳过重复检测"
        return 0
    fi
    
    log "初始化系统信息"
    
    # 获取系统架构
    SYSTEM_ARCH=$(uname -m)
    
    # 调用核心检测函数
    detect_system_info
    
    # 检查系统兼容性
    check_system_compatibility
    
    # 标记系统信息已初始化
    SYSTEM_INFO_INITIALIZED=true
    
    log "系统信息初始化完成: $SYSTEM_TYPE $SYSTEM_VERSION ($SYSTEM_CODENAME), 架构: $SYSTEM_ARCH"
}

# 核心系统信息检测函数
detect_system_info() {
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
            if [[ "$version_desc" =~ \((.*)\) ]]; then
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
    
    # 保存检测到的系统信息到全局变量
    SYSTEM_TYPE="$system_type"
    SYSTEM_VERSION="$system_version"
    SYSTEM_CODENAME="$version_codename"

    # 获取并检测内核版本
    get_kernel_version
    check_kernel_bug
}

# 检查系统兼容性
check_system_compatibility() {
    # 检查是否为支持的系统类型
    if grep -q "Debian" /etc/os-release || grep -q "Ubuntu" /etc/os-release || grep -q "Linux Mint" /etc/os-release || grep -q "Armbian" /etc/os-release || grep -q "Raspbian" /etc/os-release || grep -q "Raspberry Pi OS" /etc/os-release; then
        SUPPORTED_SYSTEM=true
    else
        SUPPORTED_SYSTEM=false
    fi
}

# 兼容性包装函数：检测系统类型（保持向后兼容）
detect_system_type() {
    # 如果系统信息已初始化，直接使用全局变量
    if [ "$SYSTEM_INFO_INITIALIZED" = true ]; then
        echo "$SYSTEM_TYPE|$SYSTEM_VERSION|$SYSTEM_CODENAME"
        return 0
    fi
    
    # 如果系统信息未初始化，调用初始化函数
    init_system_info
    
    # 返回系统信息
    echo "$SYSTEM_TYPE|$SYSTEM_VERSION|$SYSTEM_CODENAME"
}

# 兼容性包装函数：检查是否为支持的系统类型（保持向后兼容）
is_supported_system() {
    # 如果系统信息已初始化，直接使用全局变量
    if [ "$SYSTEM_INFO_INITIALIZED" = true ]; then
        [ "$SUPPORTED_SYSTEM" = true ] && return 0 || return 1
    fi
    
    # 如果系统信息未初始化，调用初始化函数
    init_system_info
    
    # 返回系统支持状态
    [ "$SUPPORTED_SYSTEM" = true ] && return 0 || return 1
}

# 获取当前 Linux 内核版本（纯数字）
get_kernel_version() {
    log "检测当前内核版本"
    local full_kernel_version
    full_kernel_version=$(uname -r)
    
    # 使用grep提取连续的数字和点组成的版本号(只要前一段)
    KERNEL_VERSION=$(echo "$full_kernel_version" | grep -o '^[0-9.]\+' | head -1)
    
    # 确保版本号格式为X.Y.Z
    KERNEL_VERSION=$(echo "$KERNEL_VERSION" | awk -F. '{printf "%d.%d.%d", $1, $2, $3}')
    
    log "当前内核版本: $KERNEL_VERSION (原始: $full_kernel_version)"
}

# 检查当前内核版本是否存在 bug
check_kernel_bug() {
    log "检查内核版本是否为存在 bug 的版本"
    
    # 设置存在 bug 的内核版本正则表达式
    # 这里可以自定义要检查的版本模式
    # 在全局变量中填入这个表达式
    # KERNEL_BUG_REGEX="^6\.(1[0-9]|2[0-9])\."  # 示例：6.10-6.29 版本可能有问题
    
    if [[ "$KERNEL_VERSION" =~ $KERNEL_BUG_REGEX ]]; then
        KERNEL_HAS_BUG=true
        log "检测到内核版本 $KERNEL_VERSION 可能存在 bug"
    else
        KERNEL_HAS_BUG=false
        log "内核版本 $KERNEL_VERSION 未发现已知问题"
    fi
}

# 检查下载工具可用性并初始化全局变量
check_download_tools() {
    log "检查下载工具可用性"
    
    # 检查 wget 是否可用
    if command -v wget >/dev/null 2>&1; then
        HAS_WGET=true
        log "检测到系统已安装 wget"
    else
        HAS_WGET=false
    fi
    
    # 检查 curl 是否可用
    if command -v curl >/dev/null 2>&1; then
        HAS_CURL=true
        log "检测到系统已安装 curl"
    else
        HAS_CURL=false
    fi
    
    # 确定首选下载工具，优先使用 wget
    if [ "$HAS_WGET" = true ]; then
        PREFERRED_DOWNLOAD_TOOL="wget"
        log "选择 wget 作为首选下载工具"
    elif [ "$HAS_CURL" = true ]; then
        PREFERRED_DOWNLOAD_TOOL="curl"
        log "选择 curl 作为首选下载工具"
    else
        log "错误: 系统中未找到 wget 或 curl，至少需要安装其中一个工具"
        exit 1
    fi
    
    log "下载工具检查完成: wget=$HAS_WGET, curl=$HAS_CURL, 首选工具=$PREFERRED_DOWNLOAD_TOOL"
}

# 获取下载命令和参数
get_download_command() {
    local tool="$1"
    
    case "$tool" in
        "wget")
            echo "wget --progress=bar:force -O"
            ;;
        "curl")
            echo "curl -fSL --progress-bar -o"
            ;;
        *)
            # 如果没有指定工具，使用全局变量中的首选工具
            if [ -n "$PREFERRED_DOWNLOAD_TOOL" ]; then
                get_download_command "$PREFERRED_DOWNLOAD_TOOL"
            else
                log "错误: 没有可用的下载工具"
                exit 1
            fi
            ;;
    esac
}

# 确保下载工具已安装 (优先使用 wget)
ensure_download_tool_installed() {
    # 使用全局变量检查下载工具
    if [ "$HAS_WGET" = false ] && [ "$HAS_CURL" = false ]; then
        log "未检测到 wget 或 curl，正在安装 wget (优先)..."
        apt_update
        if apt_install "wget"; then
            log "wget 安装成功"
            # 更新全局变量
            HAS_WGET=true
            PREFERRED_DOWNLOAD_TOOL="wget"
        else
            log "wget 安装失败，尝试安装 curl..."
            if apt_install "curl"; then
                log "curl 安装成功"
                # 更新全局变量
                HAS_CURL=true
                PREFERRED_DOWNLOAD_TOOL="curl"
            else
                log "错误: 无法安装 wget 或 curl"
                exit 1
            fi
        fi
    elif [ "$HAS_WGET" = false ] && [ "$HAS_CURL" = true ]; then
        log "系统只有 curl，建议安装 wget 以获得更好的下载体验"
        log "当前将使用 curl 进行下载"
    fi
}

# 根据架构获取二进制文件名
get_binary_filename() {
    # 确保系统信息已初始化
    if [ "$SYSTEM_INFO_INITIALIZED" = false ]; then
        init_system_info
    fi
    
    if [ "$SYSTEM_ARCH" = "aarch64" ]; then
        echo "landscape-webserver-aarch64"
    else
        echo "landscape-webserver-x86_64"
    fi
}

# 下载重试函数
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local file_description="$3"
    local max_retry=3
    local retry=0
    local user_choice=""
    local download_tool=""
    local download_cmd=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在下载 $file_description (尝试 $((retry+1))/$max_retry)"
            
            # 使用全局变量获取首选下载工具和命令
            if [ -n "$PREFERRED_DOWNLOAD_TOOL" ]; then
                download_tool="$PREFERRED_DOWNLOAD_TOOL"
                download_cmd=$(get_download_command "$download_tool")
                log "使用 $download_tool 下载 $file_description"
                
                # 执行下载命令
                if $download_cmd "$output_file" "$url"; then
                    log "$file_description 下载成功"
                    return 0
                else
                    log "$download_tool 下载失败"
                    
                    # 如果首选工具失败，尝试使用另一个可用工具
                    if [ "$download_tool" = "wget" ] && [ "$HAS_CURL" = true ]; then
                        log "wget 失败，尝试使用 curl"
                        download_cmd=$(get_download_command "curl")
                        if $download_cmd "$output_file" "$url"; then
                            log "$file_description 下载成功 (使用 curl)"
                            return 0
                        else
                            log "curl 下载也失败"
                        fi
                    elif [ "$download_tool" = "curl" ] && [ "$HAS_WGET" = true ]; then
                        log "curl 失败，尝试使用 wget"
                        download_cmd=$(get_download_command "wget")
                        if $download_cmd "$output_file" "$url"; then
                            log "$file_description 下载成功 (使用 wget)"
                            return 0
                        else
                            log "wget 下载也失败"
                        fi
                    fi
                fi
            else
                log "错误: 没有可用的下载工具"
                return 1
            fi
            
            retry=$((retry+1))
            log "下载失败, 等待 5 秒后重试"
            sleep 5
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "下载 $file_description 失败, 是否再次尝试3次？(y/n) 或输入 'm' 使用 GitHub 镜像加速: "
            read -r user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            # 如果用户选择使用 GitHub 镜像加速
            if [ "$user_choice" = "m" ]; then
                ask_github_mirror
                
                if [ "$USE_GITHUB_MIRROR" = true ]; then
                    # 更新下载 URL
                    if [[ "$url" == *"github.com"* ]]; then
                        url="$GITHUB_MIRROR/https://$url"
                    fi
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
        log "错误: 下载 $file_description 失败"
        return 1
    fi
    
    return 0
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
    
    # 使用全局变量检查架构
    if [ "$SYSTEM_ARCH" != "x86_64" ] && [ "$SYSTEM_ARCH" != "aarch64" ]; then
        log "警告: 此脚本主要适用于 x86_64 或 aarch64 架构, 当前架构为 $SYSTEM_ARCH"
    fi
    
    # 检查是否以 root 权限运行
    if [ "$EUID" -ne 0 ]; then
        log "错误: 此脚本需要 root 权限运行"
        exit 1
    fi
    
    # 检查下载工具可用性并初始化全局变量
    check_download_tools

    log "系统环境检查完成"

    # 使用全局变量显示系统信息
    log "检测到系统信息: $SYSTEM_TYPE $SYSTEM_VERSION ($SYSTEM_CODENAME), 架构: $SYSTEM_ARCH"
    
    # 对于非支持的系统，询问是否继续
    if [ "$SUPPORTED_SYSTEM" = false ]; then
        echo "警告: 检测到您的系统为 $SYSTEM_TYPE ($SYSTEM_VERSION)。"
        echo "警告: 此系统未经测试，可能存在兼容性问题。"
        read -rp "是否继续安装? (y/n): " user_response
        if [[ "$user_response" =~ ^[Nn]$ ]]; then
            log "用户选择退出安装"
            exit 0
        fi
    fi
}

# 询问时区配置
ask_timezone_config() {
    echo "-----------------------------"
    read -rp "是否将系统时区修改为亚洲/上海? (y/n): " timezone_response
    if [[ ! "$timezone_response" =~ ^[Nn]$ ]]; then
        TIMEZONE_SHANGHAI=true
    else
        TIMEZONE_SHANGHAI=false
    fi
}

# 询问 NTP 配置
ask_ntp_config() {
    echo "-----------------------------"
    read -rp "是否配置 NTP 服务器以同步系统时间? (y/n): " ntp_response
    if [[ ! "$ntp_response" =~ ^[Nn]$ ]]; then
        CONFIGURE_NTP=true
        ask_ntp_server_choice
    else
        CONFIGURE_NTP=false
    fi
}

# 询问 NTP 服务器选择
ask_ntp_server_choice() {
    echo "-----------------------------"
    echo "请选择 NTP 服务器:"
    echo "1) 阿里云 NTP 服务器（默认）"
    echo "2) 腾讯云 NTP 服务器"
    echo "3) 中国国家授时中心 NTP 服务器"
    echo "4) 教育网 NTP 服务器"
    echo "5) 自定义 NTP 服务器"
    read -rp "请选择 (1-5, 默认为 1): " ntp_server_choice
    
    case "$ntp_server_choice" in
        1|"")
            NTP_PRIMARY_SERVER="aliyun"
            NTP_SERVERS_CONFIGURED="ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com ntp4.aliyun.com ntp5.aliyun.com ntp6.aliyun.com ntp7.aliyun.com"
            ;;
        2)
            NTP_PRIMARY_SERVER="tencent"
            NTP_SERVERS_CONFIGURED="ntp.tencent.com ntp2.tencent.com ntp3.tencent.com ntp4.tencent.com ntp5.tencent.com"
            ;;
        3)
            NTP_PRIMARY_SERVER="ntsc"
            NTP_SERVERS_CONFIGURED="ntp.ntsc.ac.cn ntp1.ntsc.ac.cn ntp2.ntsc.ac.cn ntp3.ntsc.ac.cn"
            ;;
        4)
            NTP_PRIMARY_SERVER="edu"
            NTP_SERVERS_CONFIGURED="ntp.sjtu.edu.cn ntp1.sjtu.edu.cn ntp2.sjtu.edu.cn ntp3.sjtu.edu.cn ntp4.sjtu.edu.cn"
            ;;
        5)
            read -rp "请输入自定义 NTP 服务器地址 (多个服务器用空格分隔): " custom_ntp_servers
            if [ -n "$custom_ntp_servers" ]; then
                NTP_PRIMARY_SERVER="custom"
                NTP_SERVERS_CONFIGURED="$custom_ntp_servers"
            else
                echo "未输入自定义 NTP 服务器，使用默认阿里云 NTP 服务器"
                NTP_PRIMARY_SERVER="aliyun"
                NTP_SERVERS_CONFIGURED="ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com ntp4.aliyun.com ntp5.aliyun.com ntp6.aliyun.com ntp7.aliyun.com"
            fi
            ;;
        *)
            echo "无效选择，使用默认阿里云 NTP 服务器"
            NTP_PRIMARY_SERVER="aliyun"
            NTP_SERVERS_CONFIGURED="ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com ntp4.aliyun.com ntp5.aliyun.com ntp6.aliyun.com ntp7.aliyun.com"
            ;;
    esac
    
}

# 询问swap配置
ask_swap_config() {
    echo "-----------------------------"
    read -rp "是否禁用 swap (虚拟内存) ? (y/n): " swap_response
    if [[ ! "$swap_response" =~ ^[Nn]$ ]]; then
        SWAP_DISABLED=true
    else
        SWAP_DISABLED=false
    fi
}

# 询问Docker配置
ask_docker_config() {
    echo "-----------------------------"
    read -rp "是否安装 Docker(含compose)? (y/n): " docker_response
    if [[ ! "$docker_response" =~ ^[Nn]$ ]]; then
        DOCKER_INSTALLED=true
        
        # 询问 Docker 镜像源
        ask_docker_mirror
        echo "-----------------------------"
        # 询问是否为 Docker 开启 IPv6
        read -rp "是否为 Docker 开启 IPv6 支持? (y/n): " docker_ipv6_response
        if [[ ! "$docker_ipv6_response" =~ ^[Nn]$ ]]; then
            DOCKER_ENABLE_IPV6=true
        else
            DOCKER_ENABLE_IPV6=false
        fi
    else
        DOCKER_INSTALLED=false
    fi
}

# 询问PPP配置
ask_ppp_config() {
    echo "-----------------------------"
    read -rp "是否安装 ppp 用于 pppoe 拨号? (y/n): " ppp_response
    if [[ ! "$ppp_response" =~ ^[Nn]$ ]]; then
        INSTALL_PPP=true
    else
        INSTALL_PPP=false
    fi
}

# 询问管理员账号配置
ask_admin_config() {
    echo "-----------------------------"
    read -rp "Landscape Router 管理员 用户名、密码 均为 root, 是否修改? (y/n): " admin_response
    if [[ ! "$admin_response" =~ ^[Nn]$ ]]; then
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
}

# 询问安装路径配置
ask_install_path_config() {
    echo "-----------------------------"
    while true; do
        read -rp "请输入 Landscape Router 安装路径 (默认: /root/.landscape-router): " path_response
        if [ -z "$path_response" ]; then
            LANDSCAPE_DIR="/root/.landscape-router"
        else
            LANDSCAPE_DIR="$path_response"
        fi
        
        if [ ! -d "$(dirname "$LANDSCAPE_DIR")" ]; then
            log "错误: 指定的安装路径的上级目录不存在"
            continue
        fi
        
        break
    done
}

# 显示配置信息
display_configuration() {
    echo ""
    echo "=============================="
    echo "请检查您的配置:"
    echo "=============================="
    echo "1. 升级 kernel 版本: $([ "$UPGRADE_KERNEL" = true ] && echo "是" || echo "否")"
    echo "2. 系统时区设置为亚洲/上海: $([ "$TIMEZONE_SHANGHAI" = true ] && echo "是" || echo "否")"
    echo "3. 配置 NTP 服务器: $([ "$CONFIGURE_NTP" = true ] && echo "是" || echo "否")"
    if [ "$CONFIGURE_NTP" = true ]; then
        local ntp_server_name="未知"
        case "$NTP_PRIMARY_SERVER" in
            "aliyun") ntp_server_name="阿里云 NTP 服务器" ;;
            "tencent") ntp_server_name="腾讯云 NTP 服务器" ;;
            "ntsc") ntp_server_name="中国国家授时中心 NTP 服务器" ;;
            "edu") ntp_server_name="教育网 NTP 服务器" ;;
            "custom") ntp_server_name="自定义 NTP 服务器" ;;
        esac
        echo "   NTP 服务器: $ntp_server_name"
        echo "   注意: 仅配置已安装的 NTP 客户端，不提供 NTP 客户端安装功能"
    fi
    echo "4. 禁用 swap (虚拟内存): $([ "$SWAP_DISABLED" = true ] && echo "是" || echo "否")"
    echo "5. 更换 apt 软件源: $([ "$USE_CUSTOM_MIRROR" = true ] && echo "是" || echo "否")"
    if [ "$USE_CUSTOM_MIRROR" = true ]; then
        local mirror_name="未知"
        case "$MIRROR_SOURCE" in
            "ustc") mirror_name="中国科学技术大学" ;;
            "tsinghua") mirror_name="清华大学" ;;
            "aliyun") mirror_name="阿里云" ;;
            "sjtu") mirror_name="上海交通大学" ;;
            "zju") mirror_name="浙江大学" ;;
            "nju") mirror_name="南京大学" ;;
            "hit") mirror_name="哈尔滨工业大学" ;;
        esac
        echo "   镜像源: $mirror_name"
    fi
    # 只有当web server不是预装时才显示web server安装选项
    if [ "$WEB_SERVER_PREINSTALLED" != true ]; then
        echo "6. 安装 Web Server: $([ "$WEB_SERVER_INSTALLED" = true ] && echo "是" || echo "否")"
        if [ "$WEB_SERVER_INSTALLED" = true ]; then
            echo "   Web Server 类型: $WEB_SERVER_TYPE"
        fi
    else
        echo "6. 检测到系统已预装 Web Server: $WEB_SERVER_TYPE"
    fi
    echo "7. 安装 Docker(含compose): $([ "$DOCKER_INSTALLED" = true ] && echo "是" || echo "否")"
    if [ "$DOCKER_INSTALLED" = true ]; then
        local docker_mirror_name="未知"
        case "$DOCKER_MIRROR" in
            "aliyun") docker_mirror_name="阿里云" ;;
            "azure") docker_mirror_name="Azure 中国云" ;;
            "official") docker_mirror_name="官方源 (国外)" ;;
            "tsinghua") docker_mirror_name="清华大学" ;;
            "sjtu") docker_mirror_name="上海交通大学" ;;
            "zju") docker_mirror_name="浙江大学" ;;
            "ustc") docker_mirror_name="中国科学技术大学" ;;
            "nju") docker_mirror_name="南京大学" ;;
            "hit") docker_mirror_name="哈尔滨工业大学" ;;
        esac
        echo "   Docker 镜像源: $docker_mirror_name"
        echo "   Docker IPv6 支持: $([ "$DOCKER_ENABLE_IPV6" = true ] && echo "是" || echo "否")"
    fi
    echo "8. 安装 ppp (用于 PPPOE 拨号): $([ "$INSTALL_PPP" = true ] && echo "是" || echo "否")"
    echo "9. 使用 GitHub 镜像加速: $([ "$USE_GITHUB_MIRROR" = true ] && echo "是" || echo "否")"
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        echo "   GitHub 镜像地址: $GITHUB_MIRROR"
    fi
    echo "10. 下载 redirect_pkg_handler: $([ "$DOWNLOAD_HANDLER" = true ] && echo "是" || echo "否")"
    if [ "$DOWNLOAD_HANDLER" = true ]; then
        echo "   要下载的 handler 版本: ${HANDLER_ARCHITECTURES[*]}"
    fi
    echo "11. Landscape Router 安装路径: $LANDSCAPE_DIR"
    echo "12. 管理员账号: $ADMIN_USER"
    echo "    管理员密码: $ADMIN_PASS"
    echo "13. LAN 网桥配置:"
    echo "    名称 = $(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2)"
    echo "    IP地址 = $(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)"
    echo "    DHCP起始地址 = $(echo "$LAN_CONFIG" | grep "dhcp_start" | cut -d '"' -f 2)"
    echo "    DHCP结束地址 = $(echo "$LAN_CONFIG" | grep "dhcp_end" | cut -d '"' -f 2)"
    echo "    网络掩码 = $(echo "$LAN_CONFIG" | grep "network_mask" | awk -F'= ' '{print $2}')"
    local interfaces_list
    interfaces_list=$(echo "$LAN_CONFIG" | grep "interfaces" | cut -d '(' -f 2 | cut -d ')' -f 1)
    echo "    绑定网卡 = $interfaces_list"
    echo "=============================="
}

# 修改配置
modify_configuration() {
    local config_choice="$1"
    
    case "$config_choice" in
        1)
            ask_kernel_upgrade
            ;;        
        2)
            ask_timezone_config
            ;;
        3)
            ask_ntp_config
            ;;
        4)
            ask_swap_config
            ;;
        5)
            ask_apt_mirror
            ;;
        6)
            # 只有当web server不是预装时才允许修改web server配置
            ask_webserver
            ;;
        7)
            ask_docker_config
            ;;
        8)
            ask_ppp_config
            ;;
        9)
            ask_github_mirror
            ;;
        10)
            ask_download_handler
            ;;
        11)
            ask_install_path_config
            ;;
        12)
            ask_admin_config
            ;;
        13)
            config_lan_interface
            ;;
        *)
            echo "无效选择, 请重新输入"
            echo "按任意键继续..."
            read -n 1 -s
            return 1
            ;;
    esac
    
    return 0
}

# 询问用户配置
ask_user_config() {
    log "开始询问用户配置"
    echo "=============================="
    # 提示用户所有问题回答完成后可以再次修改
    echo ""
    echo "注意: 您需要回答以下十余个问题, 回答结束后可以检查和修改任何配置项。"
    echo ""
    echo "大部分问题可以回车默认，所有安装操作将在询问结束后一并执行"
    echo ""
    # 检查并询问内核版本升级
    if [ "$KERNEL_HAS_BUG" = true ]; then
        ask_kernel_upgrade
    fi

    # 检查web server环境
    ask_webserver   
    
    # 询问时区配置
    ask_timezone_config
    
    # 询问NTP配置
    ask_ntp_config
    
    # 询问swap配置
    ask_swap_config

    # 询问是否换源 (仅对支持的系统进行询问)
    ask_apt_mirror

    # 询问Docker配置
    ask_docker_config

    # 询问PPP配置
    ask_ppp_config

    # 询问是否使用 GitHub 镜像加速
    ask_github_mirror
    
    # 询问是否下载 handler
    ask_download_handler
    
    # 询问安装路径
    ask_install_path_config

    # 询问管理员账号配置
    ask_admin_config
    
    # 配置 LAN 网卡
    config_lan_interface
    
    # 显示所有配置供用户检查和修改
    local config_confirmed=false
    while [ "$config_confirmed" = false ]; do
        display_configuration
        
        read -rp "是否需要修改配置? (输入编号修改对应配置, 输入 'done' 完成配置): " config_choice
        case "$config_choice" in
            done)
                config_confirmed=true
                ;;
            *)
                if modify_configuration "$config_choice"; then
                    # 如果修改成功，继续循环
                    continue
                fi
                ;;
        esac
    done
    
    log "用户配置询问完成"
}

# 询问用户是否升级内核
ask_kernel_upgrade() {
    echo "-----------------------------"
    echo "当前内核版本: $KERNEL_VERSION"
    echo "Landscape 在当前内核无法正常使用"
    echo "当前内核存在 bug ，必须升级"
    echo ""
    echo "升级操作由脚本全自动进行"
    read -rp "是否为您升级内核版本? (y/n): " upgrade_response
    
    if [[ ! "$upgrade_response" =~ ^[Nn]$ ]]; then
        UPGRADE_KERNEL=true
        # log "用户选择升级内核版本"
    else
        UPGRADE_KERNEL=false
        # log "用户选择跳过内核升级"
    fi
}

ask_apt_mirror() { 
    # 询问是否换源 (仅对支持的系统进行询问)
    if is_supported_system; then
        USE_CUSTOM_MIRROR=true
        echo "-----------------------------"
        
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
        read -rp "请选择 (0-7, 默认为 1 阿里云 ): " mirror_response
        case "$mirror_response" in
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
    echo "-----------------------------"
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
    echo "-----------------------------"
    echo "请选择 Docker 镜像源:"

    echo "0) 官方源 (国外)"
    echo "1) 阿里云 (默认)"
    echo "2) 清华大学"
    echo "3) 上海交通大学"
    echo "4) 浙江大学"
    echo "5) 中国科学技术大学"
    echo "6) 南京大学"
    echo "7) 哈尔滨工业大学"
    echo "8) Azure 中国云"
    read -rp "请选择 (0-8, 默认为 1 阿里云): " docker_mirror_response
    case "$docker_mirror_response" in
        0) DOCKER_MIRROR="official" ;;
        2) DOCKER_MIRROR="tsinghua" ;;
        3) DOCKER_MIRROR="sjtu" ;;
        4) DOCKER_MIRROR="zju" ;;
        5) DOCKER_MIRROR="ustc" ;;
        6) DOCKER_MIRROR="nju" ;;
        7) DOCKER_MIRROR="hit" ;;
        8) DOCKER_MIRROR="azure" ;;
        *) DOCKER_MIRROR="aliyun" ;;
    esac
}

ask_github_mirror() { 
    echo "-----------------------------"
    echo "请选择 GitHub 镜像加速地址 (默认启用 https://ghfast.top):"
    echo "0) 不使用加速"
    echo "1) https://ghfast.top (默认)"
    echo "2) 自定义地址"
    read -rp "请选择 (0-2, 默认为 1 ): " github_mirror_response
    case "$github_mirror_response" in
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
    echo "-----------------------------"
    echo ""
    echo "redirect_pkg_handler 是 分流到 Docker 容器 功能不可缺少该组件"
    echo ""
    read -rp "是否下载 redirect_pkg_handler 相关文件? (y/n): " handler_response
    if [[ ! "$handler_response" =~ ^[Nn]$ ]]; then
        DOWNLOAD_HANDLER=true
        
        # 确保系统信息已初始化
        if [ "$SYSTEM_INFO_INITIALIZED" = false ]; then
            init_system_info
        fi
        
        echo "-----------------------------"
        echo "请选择要下载的 redirect_pkg_handler 版本 (可多选，用空格分隔):"
        # 根据系统架构提供相应的选项
        case "$SYSTEM_ARCH" in
            x86_64)
                echo "1) musl 版（适用于 Alpine 等构建的镜像）(常见)"
                echo "2) Glibc 版（适用于 Debian 等构建的镜像）"
                echo "3) 全选"
                read -rp "请输入选项 (默认为 3): " handler_choice
                
                # 默认选择 x86_64
                if [ -z "$handler_choice" ]; then
                    handler_choice="3"
                fi
                
                # 根据选择设置要下载的架构
                HANDLER_ARCHITECTURES=()
                if [[ "$handler_choice" == *3* ]]; then
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
                if [[ "$handler_choice" == *3* ]]; then
                    HANDLER_ARCHITECTURES=("aarch64")
                else
                    [[ "$handler_choice" =~ 1 ]] && HANDLER_ARCHITECTURES+=("aarch64-musl")
                    [[ "$handler_choice" =~ 2 ]] && HANDLER_ARCHITECTURES+=("aarch64")
                fi
                ;;
            *)
                echo "检测到不常见的系统架构: $SYSTEM_ARCH"
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

# 获取可用网络接口
get_available_interfaces() {
    ip link show | awk -F': ' '/^[0-9]+: [a-zA-Z]/ {print $2}' | grep -v lo
}

# 显示网络接口信息
display_interface_info() {
    local interfaces="$1"
    echo "-----------------------------"
    echo "可用网络接口信息: "
    local i=1
    for iface in $interfaces; do
        echo "$i) $iface"
        # 显示IP地址信息
        local ip_info=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d'/' -f1)
        if [ -n "$ip_info" ]; then
            echo "   IP地址: $ip_info"
        fi
        # 显示MAC地址
        local mac_info=$(ip addr show $iface | grep "link/ether" | awk '{print $2}')
        echo "   MAC地址: $mac_info"
        i=$((i+1))
    done
    echo ""
}

# 验证IP地址格式
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

# 选择绑定到网桥的物理网卡
select_interfaces() {
    local interfaces="$1"
    local bridge_name="$2"
    local -n selected_interfaces_ref=$3
    
    selected_interfaces_ref=()
    local valid_input=false
    
    while [ "$valid_input" = false ]; do
        echo "请输入要绑定到 $bridge_name 网桥的网卡编号 (多个编号用空格分隔):"
        read -r choice
        
        # 检查输入格式有效性
        if ! [[ "$choice" =~ ^[0-9\ ]+$ ]]; then
            echo "输入无效, 只能包含数字和空格"
            continue
        fi
        
        # 计算接口总数
        local interface_count=0
        for iface in $interfaces; do
            interface_count=$((interface_count+1))
        done
        
        # 检查每个编号的有效性
        valid_input=true
        
        for c in $choice; do
            if [ "$c" -lt 1 ] || [ "$c" -gt "$interface_count" ]; then
                echo "编号 $c 超出范围, 请输入 1 到 $interface_count 的数字"
                valid_input=false
                break
            fi
        done
        
        # 检查是否有重复选择
        local unique_check=()
        for c in $choice; do
            local found=false
            for existing in "${unique_check[@]}"; do
                if [[ "$existing" == "$c" ]]; then
                    found=true
                    break
                fi
            done
            if [[ "$found" == true ]]; then
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
        selected_interfaces_ref+=("$selected_iface")
        echo "- $selected_iface"
    done
}

# 输入并验证IP地址
input_and_validate_ip() {
    local prompt="$1"
    local default_value="$2"
    local ip_value=""
    
    while true; do
        read -rp "$prompt (默认为 $default_value): " ip_value
        if [ -z "$ip_value" ]; then
            ip_value="$default_value"
            break
        fi
        
        if valid_ip "$ip_value"; then
            break
        else
            echo "输入的 IP 地址无效, 请输入有效的 IP 地址 (例如: $default_value) "
        fi
    done
    
    echo "$ip_value"
}

# 输入并验证DHCP范围
input_and_validate_dhcp_range() {
    local dhcp_start
    local dhcp_end
    
    # 输入 DHCP 起始地址
    dhcp_start=$(input_and_validate_ip "请输入 DHCP IP 范围起始地址" "192.168.88.100")
    
    # 输入 DHCP 结束地址
    while true; do
        dhcp_end=$(input_and_validate_ip "请输入 DHCP IP 范围结束地址" "192.168.88.200")
        
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
    done
    
    echo "$dhcp_start|$dhcp_end"
}

# 输入并验证网络掩码
input_and_validate_netmask() {
    local network_mask
    
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
    
    echo "$network_mask"
}

# 配置 LAN 网卡
config_lan_interface() {
    echo "-----------------------------"
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
    interfaces=$(get_available_interfaces)
    
    # 显示网卡详细信息
    display_interface_info "$interfaces"
    
    # 选择绑定到网桥的物理网卡
    local selected_interfaces=()
    select_interfaces "$interfaces" "$bridge_name" selected_interfaces
    
    echo "-----------------------------"
    # 询问 LAN IP
    local lan_ip
    lan_ip=$(input_and_validate_ip "请输入 LAN 网桥的 IP 地址" "192.168.88.1")
    
    # 询问 DHCP 范围
    local dhcp_range
    dhcp_range=$(input_and_validate_dhcp_range)
    local dhcp_start=$(echo "$dhcp_range" | cut -d'|' -f1)
    local dhcp_end=$(echo "$dhcp_range" | cut -d'|' -f2)
    
    # 询问网络掩码
    local network_mask
    network_mask=$(input_and_validate_netmask)
    
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
    
    # 3. 配置 NTP 客户端
    configure_ntp_client
    
    # 4. 关闭 swap
    if [ "$SWAP_DISABLED" = true ]; then
        disable_swap
    fi
    
    # 5. 换源
    if [ "$USE_CUSTOM_MIRROR" = true ]; then
        change_apt_mirror
    fi
    
    # 5.1. 升级内核（如果需要）
    if [ "$UPGRADE_KERNEL" = true ]; then
        upgrade_kernel
    fi
    
    # 6. 下载并安装 Landscape Router
    install_landscape_router

    # 7. 下载 handler
    if [ "$DOWNLOAD_HANDLER" = true ]; then
        download_handlers
    fi

    # 8. 创建 systemd 服务
    create_systemd_service
    
    # 9. 检查并安装 webserver
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
    
    # 10. 安装 Docker
    if [ "$DOCKER_INSTALLED" = true ]; then
        install_docker
        configure_docker
    fi
    
    
    # 11. 安装 ppp
    if [ "$INSTALL_PPP" = true ]; then
        install_ppp
    fi
    
    # 12. 配置网络接口
    configure_network_interfaces
    
    # 13. 创建管理员账号密码配置文件
    # 认证配置已合并到 landscape_init.toml 中，不再需要单独调用
    
    # 14. 关闭本机 DNS 服务
    disable_local_dns
    
    log "安装执行完成"
}

# 升级内核函数
upgrade_kernel() {
    if [ "$UPGRADE_KERNEL" = false ]; then
        log "用户选择不升级内核，跳过升级操作"
        return 0
    fi
    
    log "开始升级内核版本"
    
    # 确保系统信息已初始化
    if [ "$SYSTEM_INFO_INITIALIZED" = false ]; then
        init_system_info
    fi
    
    case "$SYSTEM_TYPE" in
        "debian")
            case "$SYSTEM_VERSION" in
                "13")
                    log "检测到 Debian 13，准备升级到指定内核版本"
                    apt_update
                    # 这个会安装最新的版本，也许不是好办法，因为最新的 6.16 可能再次引入bug
                    # 但是随着时间的推移，使用 debian13.2.0 ISO 的用户减少，其他版本用户不会触发升级内核，大概率不是问题
                    if apt_install "linux-image-6.16.*+deb13-amd64"; then
                        log "Debian 13 内核升级成功"
                        update-grub
                        return 0
                    else
                        log "错误: Debian 13 内核升级失败"
                        return 1
                    fi
                    ;;
                *)
                    log "当前 Debian 版本 $SYSTEM_VERSION 不支持自动内核升级"
                    log "请手动升级内核到稳定版本"
                    return 1
                    ;;
            esac
            ;;
        *)
            log "不支持的系统类型: $SYSTEM_TYPE"
            return 1
            ;;
    esac
}

# 设置时区
setup_timezone() {
    log "设置系统时区为亚洲/上海"
    timedatectl set-timezone Asia/Shanghai
    log "时区设置完成"
}

# 检测所有可用的 NTP 客户端类型
detect_ntp_client() {
    # 将日志信息输出到日志文件，而不是标准输出，避免混入返回值
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] 检测系统所有可用的 NTP 客户端类型" >> "$INSTALL_LOG"
    
    local detected_clients=()
    
    # 检查 systemd-timesyncd
    if systemctl is-enabled systemd-timesyncd >/dev/null 2>&1 || command -v timedatectl >/dev/null 2>&1 && timedatectl status | grep -q "NTP service: active"; then
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] 检测到 systemd-timesyncd 客户端" >> "$INSTALL_LOG"
        detected_clients+=("systemd-timesyncd")
    fi
    
    # 检查 chrony
    if command -v chronyd >/dev/null 2>&1 || command -v chronyc >/dev/null 2>&1 || dpkg -l | grep -q "chrony"; then
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] 检测到 chrony 客户端" >> "$INSTALL_LOG"
        detected_clients+=("chrony")
    fi
    
    # 检查 ntpd (ntp)
    if command -v ntpd >/dev/null 2>&1 || command -v ntpq >/dev/null 2>&1 || dpkg -l | grep -q "ntp"; then
        timestamp=$(date +"%Y-%m-%d %H:%M:%S")
        echo "[$timestamp] 检测到 ntpd 客户端" >> "$INSTALL_LOG"
        detected_clients+=("ntpd")
    fi
    
    # 返回所有检测到的客户端类型，用空格分隔
    # 如果没有检测到任何 NTP 客户端，返回空字符串
    echo "${detected_clients[@]}"
    return 0
}

# 获取 NTP 服务器列表
get_ntp_servers() {
    local server_choice="$1"
    
    case "$server_choice" in
        "aliyun")
            echo "ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com ntp4.aliyun.com ntp5.aliyun.com ntp6.aliyun.com ntp7.aliyun.com"
            ;;
        "tencent")
            echo "ntp.tencent.com ntp2.tencent.com ntp3.tencent.com ntp4.tencent.com ntp5.tencent.com"
            ;;
        "ntsc")
            echo "ntp.ntsc.ac.cn ntp1.ntsc.ac.cn ntp2.ntsc.ac.cn ntp3.ntsc.ac.cn"
            ;;
        "edu")
            echo "ntp.sjtu.edu.cn ntp1.sjtu.edu.cn ntp2.sjtu.edu.cn ntp3.sjtu.edu.cn ntp4.sjtu.edu.cn"
            ;;
        "custom")
            echo "$NTP_SERVERS_CONFIGURED"
            ;;
        *)
            echo "ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com ntp4.aliyun.com ntp5.aliyun.com ntp6.aliyun.com ntp7.aliyun.com"
            ;;
    esac
}

# 配置 systemd-timesyncd 客户端
configure_systemd_timesyncd() {
    log "配置 systemd-timesyncd 客户端"
    
    # 检查 systemd-timesyncd 是否已安装
    if ! dpkg -l | grep -q "systemd-timesyncd"; then
        log "警告: systemd-timesyncd 未安装，跳过配置"
        log "请手动安装 systemd-timesyncd 后再运行此脚本"
        return 1
    fi
    
    # 获取 NTP 服务器列表
    local ntp_servers
    ntp_servers=$(get_ntp_servers "$NTP_PRIMARY_SERVER")
    
    # 分离主服务器和fallback服务器
    local primary_server=""
    local fallback_servers=""
    
    # 获取第一个服务器作为主服务器
    primary_server=$(echo "$ntp_servers" | awk '{print $1}')
    
    # 获取剩余服务器作为fallback服务器
    fallback_servers=$(echo "$ntp_servers" | cut -d' ' -f2-)
    
    log "主 NTP 服务器: $primary_server"
    log "Fallback NTP 服务器: $fallback_servers"
    
    # 备份原始配置文件
    local config_file="/etc/systemd/timesyncd.conf"
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.bak.$(date +%Y%m%d%H%M%S)"
        log "已备份原始配置文件到 ${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 创建配置目录（如果不存在）
    mkdir -p "$(dirname "$config_file")"
    
    # 写入新的配置
    cat > "$config_file" << EOF
# This file is part of systemd.
#
# systemd is free software; you can redistribute it and/or modify it
# under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation; either version 2.1 of the License, or
# (at your option) any later version.

[Time]
NTP=$primary_server
FallbackNTP=$fallback_servers

# Root distance max is the maximum allowed distance in seconds to the
# nearest synchronization source. Setting this to a larger value will allow
# longer distance between the local system and the synchronization source.
#RootDistanceMaxSec=5

# PollIntervalMinSec and PollIntervalMaxSec specify the minimum and maximum
# intervals for polling the time source. The intervals are specified in
# seconds. The default values are 64 seconds and 1024 seconds respectively.
#PollIntervalMinSec=64
#PollIntervalMaxSec=1024
EOF
    
    # 启用并启动 systemd-timesyncd 服务
    log "启用并启动 systemd-timesyncd 服务"
    systemctl enable systemd-timesyncd
    systemctl restart systemd-timesyncd
    
    # 等待服务启动
    sleep 2
    
    # 检查服务状态
    if systemctl is-active systemd-timesyncd >/dev/null 2>&1; then
        log "systemd-timesyncd 服务已成功启动"
        
        # 显示同步状态
        log "NTP 同步状态:"
        timedatectl status | grep -E "(NTP service|NTP synchronized)"
    else
        log "警告: systemd-timesyncd 服务启动失败"
    fi
    
    log "systemd-timesyncd 配置完成"
}

# 配置 chrony 客户端
configure_chrony() {
    log "配置 chrony 客户端"
    
    # 检查 chrony 是否已安装
    if ! dpkg -l | grep -q "chrony"; then
        log "警告: chrony 未安装，跳过配置"
        log "请手动安装 chrony 后再运行此脚本"
        return 1
    fi
    
    # 获取 NTP 服务器列表
    local ntp_servers
    ntp_servers=$(get_ntp_servers "$NTP_PRIMARY_SERVER")
    
    # 分离主服务器和备用服务器
    local primary_server=""
    local backup_servers=""
    
    # 获取第一个服务器作为主服务器
    primary_server=$(echo "$ntp_servers" | awk '{print $1}')
    
    # 获取剩余服务器作为备用服务器
    backup_servers=$(echo "$ntp_servers" | cut -d' ' -f2-)
    
    log "主 NTP 服务器: $primary_server"
    log "备用 NTP 服务器: $backup_servers"
    
    # 备份原始配置文件
    local config_file="/etc/chrony/chrony.conf"
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.bak.$(date +%Y%m%d%H%M%S)"
        log "已备份原始配置文件到 ${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 创建配置目录（如果不存在）
    mkdir -p "$(dirname "$config_file")"
    
    # 写入新的配置
    cat > "$config_file" << EOF
# Welcome to the chrony configuration file. See chrony.conf(5) for more
# information about usable directives.

# 使用主服务器
server $primary_server iburst

# 使用时间源来自 DHCP/SLAAC
sourcedir /run/chrony-dhcp

# 记录接收到的 NTP 数据包的速率和源地址
driftfile /var/lib/chrony/chrony.drift

# 允许 chronyd 在需要时调整系统时钟的速度
# 这对于大多数系统来说是一个很好的设置
rtcsync

# 启用内核时间同步
# 这可以提高时钟的准确性
makestep 1.0 3

# 允许特定网络访问 chronyd
# 如果您想允许其他网络访问，请取消注释并修改
#allow 192.168.0.0/16

# 如果您想从特定网络接收 NTP 请求，请取消注释
#bindaddress 127.0.0.1
#bindaddress ::1

# 日志文件位置
logdir /var/log/chrony

# 选择要记录的信息
log measurements statistics tracking
EOF
    
    # 启用并启动 chrony 服务
    log "启用并启动 chrony 服务"
    systemctl enable chrony
    systemctl restart chrony
    
    # 等待服务启动
    sleep 2
    
    # 检查服务状态
    if systemctl is-active chrony >/dev/null 2>&1; then
        log "chrony 服务已成功启动"
        
        # 显示同步状态
        log "NTP 同步状态:"
        chronyc tracking | head -n 5
    else
        log "警告: chrony 服务启动失败"
    fi
    
    log "chrony 配置完成"
}

# 配置 ntpd 客户端
configure_ntpd() {
    log "配置 ntpd 客户端"
    
    # 检查 ntp 是否已安装
    if ! dpkg -l | grep -q "ntp"; then
        log "警告: ntp 未安装，跳过配置"
        log "请手动安装 ntp 后再运行此脚本"
        return 1
    fi
    
    # 获取 NTP 服务器列表
    local ntp_servers
    ntp_servers=$(get_ntp_servers "$NTP_PRIMARY_SERVER")
    
    # 分离主服务器和备用服务器
    local primary_server=""
    local backup_servers=""
    
    # 获取第一个服务器作为主服务器
    primary_server=$(echo "$ntp_servers" | awk '{print $1}')
    
    # 获取剩余服务器作为备用服务器
    backup_servers=$(echo "$ntp_servers" | cut -d' ' -f2-)
    
    log "主 NTP 服务器: $primary_server"
    log "备用 NTP 服务器: $backup_servers"
    
    # 备份原始配置文件
    local config_file="/etc/ntp.conf"
    if [ -f "$config_file" ]; then
        cp "$config_file" "${config_file}.bak.$(date +%Y%m%d%H%M%S)"
        log "已备份原始配置文件到 ${config_file}.bak.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 写入新的配置
    cat > "$config_file" << EOF
# /etc/ntp.conf, configuration for ntpd; see ntp.conf(5) for help

driftfile /var/lib/ntp/ntp.drift

# 启用日志记录
logfile /var/log/ntp.log

# 访问控制限制
# 默认限制，不允许修改
restrict default nomodify notrap nopeer noquery

# 允许本地主机所有访问
restrict 127.0.0.1
restrict ::1

# 如果您想允许特定网络访问，请取消注释
#restrict 192.168.0.0 mask 255.255.255.0 nomodify notrap

# 使用主服务器
server $primary_server iburst prefer

# 使用备用服务器
EOF
    
    # 添加备用服务器到配置文件
    for server in $backup_servers; do
        echo "server $server iburst" >> "$config_file"
    done
    
    cat >> "$config_file" << EOF

# 使用本地时钟作为备用时间源，以防外部服务器不可用
server 127.127.1.0
fudge  127.127.1.0 stratum 10

# 包含来自 /etc/ntpconf.d 的配置文件
includefile /etc/ntpconf.d

# 启用内核时间同步
# 这可以提高时钟的准确性
tos minclock 4 minsane 3
EOF
    
    # 启用并启动 ntp 服务
    log "启用并启动 ntp 服务"
    systemctl enable ntp
    systemctl restart ntp
    
    # 等待服务启动
    sleep 5  # ntpd 需要更多时间来启动
    
    # 检查服务状态
    if systemctl is-active ntp >/dev/null 2>&1; then
        log "ntp 服务已成功启动"
        
        # 显示同步状态
        log "NTP 同步状态:"
        ntpq -p | head -n 10
    else
        log "警告: ntp 服务启动失败"
    fi
    
    log "ntpd 配置完成"
}

# 配置 NTP 客户端
configure_ntp_client() {
    if [ "$CONFIGURE_NTP" = false ]; then
        log "用户选择不配置 NTP 服务器，跳过 NTP 配置"
        return 0
    fi
    
    log "开始配置 NTP 客户端"
    
    # 检测所有可用的 NTP 客户端类型
    local detected_clients
    detected_clients=$(detect_ntp_client)
    
    log "检测到的所有 NTP 客户端类型: $detected_clients"
    
    # 检查是否检测到任何 NTP 客户端
    if [ -z "$detected_clients" ]; then
        log "未检测到任何已安装的 NTP 客户端，跳过 NTP 配置"
        log "注意: 本脚本不提供 NTP 客户端安装功能，请手动安装所需的 NTP 客户端"
        return 0
    fi
    
    # 将检测到的客户端类型转换为数组
    local client_array=($detected_clients)
    local total_clients=${#client_array[@]}
    
    log "将配置 $total_clients 个 NTP 客户端"
    
    # 遍历所有检测到的客户端类型并进行配置
    for client in "${client_array[@]}"; do
        log "正在配置 NTP 客户端: $client"
        
        # 根据客户端类型调用相应的配置函数
        case "$client" in
            "systemd-timesyncd")
                configure_systemd_timesyncd
                ;;
            "chrony")
                configure_chrony
                ;;
            "ntpd"|"ntp")
                configure_ntpd
                ;;
            *)
                log "未知的 NTP 客户端类型: $client"
                log "跳过配置未知的 NTP 客户端类型: $client"
                ;;
        esac
        
        log "NTP 客户端 $client 配置完成"
    done
    
    log "所有 NTP 客户端配置完成"
}

# 关闭 swap
disable_swap() {
    log "禁用 swap (虚拟内存)"
    
    # 注释掉 fstab 中的 swap 条目
    sed -i 's/^[^#].*swap.*/#&/' /etc/fstab
    
    log "swap (虚拟内存) 已禁用，系统重启后生效"
}

# 处理Debian/Armbian/Raspbian类型的源
handle_debian_sources() {
    local mirror_url="$1"
    local version_codename="$2"
    local system_type="$3"
    local mirror_source="$4"
    
    # 如果无法获取版本代号，则使用通用代号
    if [ -z "$version_codename" ]; then
        version_codename="stable"
    fi
    
    # 针对不同镜像源，Debian/Armbian/Raspbian 安全更新使用专门的URL
    local security_mirror_url="$mirror_url"
    case "$mirror_source" in
        "ustc")
            # 中国科学技术大学镜像站
            security_mirror_url="https://mirrors.ustc.edu.cn/debian-security/"
            ;;
        "tsinghua")
            # 清华大学镜像站
            security_mirror_url="https://mirrors.tuna.tsinghua.edu.cn/debian-security/"
            ;;
        "aliyun")
            # 阿里云镜像站
            security_mirror_url="https://mirrors.aliyun.com/debian-security/"
            ;;
        "sjtu")
            # 上海交通大学镜像站
            security_mirror_url="https://mirror.sjtu.edu.cn/debian-security/"
            ;;
        "zju")
            # 浙江大学镜像站
            security_mirror_url="https://mirrors.zju.edu.cn/debian-security/"
            ;;
        "nju")
            # 南京大学镜像站
            security_mirror_url="https://mirrors.nju.edu.cn/debian-security/"
            ;;
        "hit")
            # 哈尔滨工业大学镜像站
            security_mirror_url="https://mirrors.hit.edu.cn/debian-security/"
            ;;
        *)
            # 默认使用镜像站的debian-security子路径
            security_mirror_url="${mirror_url}debian-security/"
            ;;
    esac
    
    # 对于所有版本，使用用户选择的镜像源而不是固定的 security.debian.org
    # 这样确保所有安全更新都通过用户选择的镜像源获取
    
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
}

# 处理Ubuntu/LinuxMint类型的源
handle_ubuntu_sources() {
    local mirror_url="$1"
    local version_codename="$2"
    local mirror_source="$3"
    
    # 如果无法获取版本代号，则使用通用代号
    if [ -z "$version_codename" ]; then
        version_codename="focal"  # 默认使用 focal
    fi
    
    # 针对不同镜像源，Ubuntu/Linux Mint 安全更新使用专门的URL
    local ubuntu_security_mirror_url="$mirror_url"
    case "$mirror_source" in
        "ustc")
            # 中国科学技术大学镜像站
            ubuntu_security_mirror_url="https://mirrors.ustc.edu.cn/ubuntu-security/"
            ;;
        "tsinghua")
            # 清华大学镜像站
            ubuntu_security_mirror_url="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-security/"
            ;;
        "aliyun")
            # 阿里云镜像站
            ubuntu_security_mirror_url="https://mirrors.aliyun.com/ubuntu-security/"
            ;;
        "sjtu")
            # 上海交通大学镜像站
            ubuntu_security_mirror_url="https://mirror.sjtu.edu.cn/ubuntu-security/"
            ;;
        "zju")
            # 浙江大学镜像站
            ubuntu_security_mirror_url="https://mirrors.zju.edu.cn/ubuntu-security/"
            ;;
        "nju")
            # 南京大学镜像站
            ubuntu_security_mirror_url="https://mirrors.nju.edu.cn/ubuntu-security/"
            ;;
        "hit")
            # 哈尔滨工业大学镜像站
            ubuntu_security_mirror_url="https://mirrors.hit.edu.cn/ubuntu-security/"
            ;;
        *)
            # 默认使用镜像站的ubuntu-security子路径
            ubuntu_security_mirror_url="${mirror_url}ubuntu-security/"
            ;;
    esac
    
    # 对于所有版本，使用用户选择的镜像源而不是固定的 security.ubuntu.com
    # 这样确保所有安全更新都通过用户选择的镜像源获取
    
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
}

# 换源
change_apt_mirror() {
    log "更换 apt 软件源"
    
    # 检查是否为支持的系统类型
    if ! is_supported_system; then
        log "警告: 不支持的系统类型，仅支持 Debian、Ubuntu、Linux Mint、Armbian 和 Raspbian"
        log "提示: 不支持小众发行版换源，建议小众发行版自行换源"
        return 0
    fi
    
    # 检测系统类型
    local system_info
    system_info=$(detect_system_type)
    local system_type=$(echo "$system_info" | cut -d'|' -f1)
    local system_version=$(echo "$system_info" | cut -d'|' -f2)
    local version_codename=$(echo "$system_info" | cut -d'|' -f3)
    
    # 确定使用的镜像源URL
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
            handle_debian_sources "$mirror_url" "$version_codename" "$system_type" "$MIRROR_SOURCE"
            ;;
        "ubuntu"|"linuxmint")
            handle_ubuntu_sources "$mirror_url" "$version_codename" "$MIRROR_SOURCE"
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
    
    local retry=0
    local max_retry=3
    local user_choice=""
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在安装 Docker(含compose) (尝试 $((retry+1))/$max_retry)"
            
            # 检测系统类型
            local system_info
            system_info=$(detect_system_type)
            local system_type=$(echo "$system_info" | cut -d'|' -f1)
            local version_codename=$(echo "$system_info" | cut -d'|' -f3)
            
            log "系统类型: $system_type"
            log "版本代号: $version_codename"
            
            # 安装必要的依赖包
            log "安装 Docker 必要的依赖包"
            if ! apt_update; then
                log "错误: apt update 失败"
                retry=$((retry+1))
                continue
            fi
            
            if ! apt_install "ca-certificates wget curl gnupg lsb-release"; then
                log "错误: 安装 Docker 依赖包失败"
                retry=$((retry+1))
                continue
            fi
            
            # 添加 Docker 官方 GPG 密钥
            log "添加 Docker 官方 GPG 密钥"
            if ! install_docker_gpg_key; then
                log "错误: 添加 Docker GPG 密钥失败"
                retry=$((retry+1))
                continue
            fi
            
            # 添加 Docker 仓库
            log "添加 Docker 仓库"
            if ! add_docker_repository_global; then
                log "错误: 添加 Docker 仓库失败"
                retry=$((retry+1))
                continue
            fi
            
            # 强制更新 apt 包索引
            log "更新包索引以包含 Docker 仓库"
            if ! apt_update --force; then
                log "错误: 更新包索引失败"
                retry=$((retry+1))
                continue
            fi
            
            # 安装 Docker 及相关组件
            log "安装 Docker 及相关组件"
            if ! apt_install "docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"; then
                log "错误: 安装 Docker 组件失败"
                retry=$((retry+1))
                continue
            fi
            
            # 启动并启用 Docker 服务
            log "启动并启用 Docker 服务"
            if ! systemctl enable docker; then
                log "警告: 启用 Docker 服务失败"
            fi
            
            if ! systemctl start docker; then
                log "警告: 启动 Docker 服务失败"
            fi
            
            # 验证 Docker 安装
            if command -v docker >/dev/null 2>&1; then
                local docker_version
                docker_version=$(docker --version)
                log "Docker 安装成功: $docker_version"
                
                # 验证 Docker Compose 安装
                if docker compose version >/dev/null 2>&1; then
                    local compose_version
                    compose_version=$(docker compose version)
                    log "Docker Compose 安装成功: $compose_version"
                else
                    log "警告: Docker Compose 安装可能有问题"
                fi
                
                log "Docker(含compose) 安装成功"
                return 0
            else
                log "错误: Docker 安装失败"
                retry=$((retry+1))
                continue
            fi
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

# 安装 Docker GPG 密钥
install_docker_gpg_key() {
    local retry=0
    local max_retry=3
    local user_choice=""
    local download_tool=""  # 选择的下载工具 (wget 或 curl)
    
    # 使用全局变量获取下载工具
    if [ -n "$PREFERRED_DOWNLOAD_TOOL" ]; then
        download_tool="$PREFERRED_DOWNLOAD_TOOL"
        log "使用 $download_tool 作为下载工具"
    else
        log "错误: 系统中未找到可用的下载工具，无法下载 GPG 密钥"
        return 1
    fi
    
    while [ "$user_choice" != "n" ]; do
        retry=0
        while [ $retry -lt $max_retry ]; do
            log "正在添加 Docker GPG 密钥 (尝试 $((retry+1))/$max_retry)，使用工具: $download_tool"
            
            # 创建 keyrings 目录
            if ! install -m 0755 -d /etc/apt/keyrings; then
                log "错误: 创建 keyrings 目录失败"
                retry=$((retry+1))
                continue
            fi
            
            # 根据镜像源选择 GPG 密钥 URL
            local gpg_key_url=""
            case "$DOCKER_MIRROR" in
                "aliyun")
                    gpg_key_url="https://mirrors.aliyun.com/docker-ce/linux/debian/gpg"
                    ;;
                "azure")
                    gpg_key_url="https://mirrors.azure.cn/docker-ce/linux/debian/gpg"
                    ;;
                "tsinghua")
                    gpg_key_url="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian/gpg"
                    ;;
                "sjtu")
                    gpg_key_url="https://mirror.sjtu.edu.cn/docker-ce/linux/debian/gpg"
                    ;;
                "zju")
                    gpg_key_url="https://mirrors.zju.edu.cn/docker-ce/linux/debian/gpg"
                    ;;
                "ustc")
                    gpg_key_url="https://mirrors.ustc.edu.cn/docker-ce/linux/debian/gpg"
                    ;;
                "nju")
                    gpg_key_url="https://mirrors.nju.edu.cn/docker-ce/linux/debian/gpg"
                    ;;
                "hit")
                    gpg_key_url="https://mirrors.hit.edu.cn/docker-ce/linux/debian/gpg"
                    ;;
                *)
                    # 默认使用官方 GPG 密钥
                    gpg_key_url="https://download.docker.com/linux/debian/gpg"
                    ;;
            esac
            
            log "使用 GPG 密钥 URL: $gpg_key_url"
            
            # 使用选定的下载工具下载并添加 GPG 密钥
            local gpg_key_downloaded=false
            
            case "$download_tool" in
                "wget")
                    log "使用 wget 下载 Docker GPG 密钥"
                    if $(get_download_command "wget") /tmp/docker.gpg "$gpg_key_url"; then
                        # 使用 wget 下载成功，处理密钥
                        if gpg --dearmor < /tmp/docker.gpg > /etc/apt/keyrings/docker.gpg; then
                            chmod a+r /etc/apt/keyrings/docker.gpg
                            rm -f /tmp/docker.gpg
                            gpg_key_downloaded=true
                            log "Docker GPG 密钥添加成功 (使用 wget)"
                        else
                            log "错误: GPG 密钥处理失败"
                            rm -f /tmp/docker.gpg
                        fi
                    else
                        log "wget 下载 GPG 密钥失败"
                    fi
                    ;;
                "curl")
                    log "使用 curl 下载 Docker GPG 密钥"
                    if $(get_download_command "curl") /tmp/docker.gpg "$gpg_key_url"; then
                        # 使用 curl 下载成功，处理密钥
                        if gpg --dearmor < /tmp/docker.gpg > /etc/apt/keyrings/docker.gpg; then
                            chmod a+r /etc/apt/keyrings/docker.gpg
                            rm -f /tmp/docker.gpg
                            gpg_key_downloaded=true
                            log "Docker GPG 密钥添加成功 (使用 curl)"
                        else
                            log "错误: GPG 密钥处理失败"
                            rm -f /tmp/docker.gpg
                        fi
                    else
                        log "curl 下载 GPG 密钥失败"
                    fi
                    ;;
            esac
            
            if [ "$gpg_key_downloaded" = true ]; then
                return 0
            else
                log "错误: 下载或添加 GPG 密钥失败"
                retry=$((retry+1))
                if [ $retry -lt $max_retry ]; then
                    log "等待 5 秒后重试..."
                    sleep 5
                fi
                continue
            fi
        done
        
        if [ $retry -eq $max_retry ]; then
            echo "Docker GPG 密钥添加失败, 已尝试 $max_retry 次，请选择操作:"
            echo "  r) 重试一次 (使用 $download_tool)"
            echo "  m) 重新选择镜像源再试"
            echo "  n) 退出安装"
            read -rp "请输入选项 (r/m/n): " user_choice
            user_choice=$(echo "$user_choice" | tr '[:upper:]' '[:lower:]')
            
            case "$user_choice" in
                "r")
                    # 重试，保持当前镜像源和下载工具
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
    
    log "错误: Docker GPG 密钥添加失败"
    return 1
}

# 添加 Docker 仓库
add_docker_repository() {
    local system_type="$1"
    local version_codename="$2"
    
    # 根据镜像源和系统类型确定仓库 URL
    local repo_url=""
    case "$DOCKER_MIRROR" in
        "aliyun")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirrors.aliyun.com/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        "azure")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirrors.azure.cn/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirrors.azure.cn/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        "tsinghua")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        "sjtu")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirror.sjtu.edu.cn/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirror.sjtu.edu.cn/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        "zju")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirrors.zju.edu.cn/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirrors.zju.edu.cn/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        "ustc")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirrors.ustc.edu.cn/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        "nju")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirrors.nju.edu.cn/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirrors.nju.edu.cn/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        "hit")
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://mirrors.hit.edu.cn/docker-ce/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://mirrors.hit.edu.cn/docker-ce/linux/ubuntu"
                    ;;
            esac
            ;;
        *)
            # 默认使用官方仓库
            case "$system_type" in
                "debian"|"armbian"|"raspbian")
                    repo_url="https://download.docker.com/linux/debian"
                    ;;
                "ubuntu"|"linuxmint")
                    repo_url="https://download.docker.com/linux/ubuntu"
                    ;;
            esac
            ;;
    esac
    
    # 如果无法确定仓库 URL，使用默认的官方仓库
    if [ -z "$repo_url" ]; then
        log "警告: 无法确定适合的 Docker 仓库 URL，使用官方仓库"
        case "$system_type" in
            "debian"|"armbian"|"raspbian")
                repo_url="https://download.docker.com/linux/debian"
                ;;
            "ubuntu"|"linuxmint")
                repo_url="https://download.docker.com/linux/ubuntu"
                ;;
        esac
    fi
    
    # 添加 Docker 仓库
    log "添加 Docker 仓库: $repo_url"
    
    # 创建仓库配置文件
    local repo_file="/etc/apt/sources.list.d/docker.list"
    
    # 备份现有的仓库文件（如果存在）
    if [ -f "$repo_file" ]; then
        cp "$repo_file" "${repo_file}.bak.$(date +%Y%m%d%H%M%S)"
        log "已备份现有 Docker 仓库文件"
    fi
    
    # 写入新的仓库配置
    if echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url \
      $version_codename stable" | \
      tee "$repo_file" > /dev/null; then
        log "Docker 仓库添加完成"
        return 0
    else
        log "错误: 添加 Docker 仓库失败"
        return 1
    fi
}

# 添加 Docker 仓库（基于全局变量版本）
add_docker_repository_global() {
    # 确保系统信息已初始化
    if [ "$SYSTEM_INFO_INITIALIZED" = false ]; then
        log "系统信息未初始化，正在初始化..."
        init_system_info
    fi
    
    # 使用全局变量调用原始函数
    add_docker_repository "$SYSTEM_TYPE" "$SYSTEM_CODENAME"
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
    local force_update=false
    
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --force)
                force_update=true
                shift
                ;;
            *)
                log "警告: apt_update 未知参数 $1"
                shift
                ;;
        esac
    done
    
    # 检查是否需要强制更新或从未更新过
    if [ "$force_update" = true ] || [ "$APT_UPDATED" = false ]; then
        if [ "$force_update" = true ]; then
            log "强制执行 apt update"
        else
            log "执行 apt update"
        fi
        
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

# 下载Landscape Router二进制文件
download_landscape_binary() {
    local binary_filename
    binary_filename=$(get_binary_filename)
    
    # 构建下载URL
    local binary_url
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        binary_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_filename"
    else
        binary_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_filename"
    fi
    
    # 使用统一的下载函数
    if ! download_with_retry "$binary_url" "$LANDSCAPE_DIR/$binary_filename" "$binary_filename"; then
        log "错误: 下载 $binary_filename 失败"
        exit 1
    fi
    
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
}

# 下载和解压static文件
download_and_extract_static() {
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
    
    # 使用统一的下载函数
    if ! download_with_retry "$static_url" "/tmp/static.zip" "static.zip"; then
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
}

# 安装 Landscape Router
install_landscape_router() {
    log "下载并安装 Landscape Router"
    
    # 确保下载工具已安装
    ensure_download_tool_installed
    
    # 下载二进制文件
    download_landscape_binary
    
    # 下载和解压static文件
    download_and_extract_static
    
    log "Landscape Router 部署完成"
}

# 下载 handler 文件
download_handlers() {
    log "开始下载 redirect_pkg_handler 文件"
    
    # 不再创建单独的 handler 目录，直接使用 LANDSCAPE_DIR
    
    # 确保下载工具已安装
    ensure_download_tool_installed
    
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
    
    # 使用统一的下载函数
    if ! download_with_retry "$handler_script_url" "$LANDSCAPE_DIR/redirect_pkg_handler.sh" "redirect_pkg_handler.sh"; then
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
        
        # 使用统一的下载函数
        if ! download_with_retry "$handler_url" "$LANDSCAPE_DIR/$handler_filename" "$handler_filename"; then
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
    local binary_filename
    binary_filename=$(get_binary_filename)
    
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
    all_interfaces=$(get_available_interfaces)
    
    # 处理所有网卡，将物理网卡设置为manual模式（排除虚拟网卡）
    for iface in $all_interfaces; do
        # 跳过虚拟网卡 (docker、veth、br、tap、tun等开头的接口)
        # 定义虚拟网卡前缀数组，提高可读性和性能
        local virtual_prefixes=(
            "docker" "veth" "br" "tap" "tun" "vboxnet" "vmnet" "macvtap" "ip6tnl" "sit"
            "gre" "gretap" "erspan" "ipip" "ip6gre" "ip6gretap" "ip6erspan" "vti" "vti6"
            "nlmon" "nflog" "nfqueue" "vcan" "vxcan" "mpls" "rwl" "wwan" "ppp" "sl"
            "isdn" "hdlc" "arc" "appletalk" "rose" "netrom" "ax25" "dccp" "sctp"
            "llc" "ieee802154" "caif" "caif6" "caif2" "caif4" "caif5" "caif7" "caif8"
            "caif9" "caif10" "caif11" "caif12" "caif13" "caif14" "caif15" "caif16"
            "caif17" "caif18" "caif19" "caif20"
        )
        
        # 检查是否为虚拟网卡
        local is_virtual=false
        for prefix in "${virtual_prefixes[@]}"; do
            if [[ "$iface" == "$prefix"* ]]; then
                is_virtual=true
                break
            fi
        done
        
        if [[ "$is_virtual" == true ]]; then
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
# ==== 管理员账号配置 ====
# ==== Administrator account configuration ====
[config.auth]
# 管理员 用户名 和 密码
# Administrator username and password
admin_user = "$ADMIN_USER"
admin_pass = "$ADMIN_PASS"

# ==== 创建 $bridge_name 网桥 ====
# ==== Create $bridge_name bridge ====
[[ifaces]]
name = "$bridge_name"
create_dev_type = "bridge"
zone_type = "lan"
enable_in_boot = true
wifi_mode = "undefined"

# 为 $bridge_name 开启 ebpf 路由
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
    local lan_ip
    lan_ip=$(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)
    echo ""
    echo "网络配置即将生效"
    echo "正在启动 Landscape Router 服务..."
    # 重启网络服务 并 启动 Landscape Router 服务
    # echo "安装完成, 脚本退出"
    echo ""
    echo "=============================="
    echo "     o(≧▽≦)o 安装完成!"
    echo "=============================="
    echo ""
    echo "接下来 SSH 连接可能会中断"
    echo "请通过 $lan_ip 连接 SSH 服务"
    echo ""
    echo "请通过浏览器, 访问以下地址管理您的 Landscape Router :"
    echo ""
    echo "http://$lan_ip:6300"
    echo ""
    echo "管理员用户名: $ADMIN_USER"
    echo "管理员密码: $ADMIN_PASS"
    echo ""
    echo "=============================="

    # 根据是否升级了内核选择重启方式
    if [ "$UPGRADE_KERNEL" = true ]; then
        echo ""
        echo "检测到内核已升级，即将重启系统以应用新的内核版本"
        echo "系统重启后，Landscape Router 服务将自动启动"
        echo ""
        
        log "用户选择升级内核，正在重启系统以应用新内核"
        
        # 延迟5秒后重启，给用户时间看到消息
        echo "5 秒后系统将重启...  ctrl + C 取消可重启"
        sleep 5
        
        # 重启系统
        reboot
    else
        # 正常的网络服务重启和启动 landscape 服务
        systemctl restart networking && systemctl start landscape-router.service
    fi

    log "安装完成"
}

# 调用主函数启动脚本执行
main "$@"
