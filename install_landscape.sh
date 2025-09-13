#!/bin/bash

# Landscape Router 交互式安装脚本
# 适用于 Debian 13 x86_64 架构 和 Armbian aarch64 架构（需要内核版本 >= 6.9）

# 全局变量
INSTALL_LOG=""
LANDSCAPE_DIR=""
WEB_SERVER_INSTALLED=false
TIMEZONE_SHANGHAI=false
SWAP_DISABLED=false
USE_CUSTOM_MIRROR=false
DOCKER_INSTALLED=false
DOCKER_MIRROR="aliyun"
DOCKER_ENABLE_IPV6=false
MODIFY_APACHE_PORT=false
APACHE_PORT="8080"
WAN_CONFIG=""
LAN_CONFIG=""
GITHUB_MIRROR=""
USE_GITHUB_MIRROR=false
MAX_RETRY=10
IS_ARMBIAN=false

# 主逻辑
main() {
    # 初始化日志
    init_log
    
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

# 初始化日志
init_log() {
    local log_dir=""
    log_dir="$(pwd)/landscape/script-log"
    mkdir -p "$log_dir"
    
    local timestamp
    timestamp=$(date +"%Y_%m_%d-%H_%M_%S-%3N")
    INSTALL_LOG="$log_dir/install-$timestamp.log"
    
    # 创建空日志文件
    touch "$INSTALL_LOG"
    
    echo "安装日志将保存到: $INSTALL_LOG"
    log "安装日志初始化完成"
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
    
    # 检查是否为 Debian 13 或 Armbian
    if ! grep -q "Debian GNU/Linux 13" /etc/os-release && ! grep -q "Armbian" /etc/os-release; then
        log "警告: 此脚本专为 Debian 13 或 Armbian 设计，当前系统可能不兼容"
    fi
    
    # 检查是否为 Armbian 系统
    if grep -q "Armbian" /etc/os-release; then
        IS_ARMBIAN=true
    else
        IS_ARMBIAN=false
    fi
    
    # 检查架构
    local arch
    arch=$(uname -m)
    if [ "$arch" != "x86_64" ] && [ "$arch" != "aarch64" ]; then
        log "错误: 此脚本仅适用于 x86_64 或 aarch64 架构，当前架构为 $arch"
        exit 1
    fi
    
    # 检查是否以 root 权限运行
    if [ "$EUID" -ne 0 ]; then
        log "错误: 此脚本需要 root 权限运行"
        exit 1
    fi
    
    # 检查内核版本（需要 >= 6.9）
    local kernel_version
    kernel_version=$(uname -r | cut -d'-' -f1)
    local major_version
    local minor_version
    major_version=$(echo "$kernel_version" | cut -d'.' -f1)
    minor_version=$(echo "$kernel_version" | cut -d'.' -f2)
    
    if [ "$major_version" -lt 6 ] || { [ "$major_version" -eq 6 ] && [ "$minor_version" -lt 9 ]; }; then
        log "错误: 内核版本过低，需要 6.9 或更高版本，当前版本为 $kernel_version"
        log "请先升级内核版本后再运行此脚本"
        exit 1
    fi
    
    log "系统环境检查完成"
}

# 询问用户配置
ask_user_config() {
    log "开始询问用户配置"
    
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
    
    # 更新日志路径
    local log_dir="$LANDSCAPE_DIR/script-log"
    mkdir -p "$log_dir"
    local log_filename
    log_filename=$(basename "$INSTALL_LOG")
    mv "$INSTALL_LOG" "$log_dir/$log_filename" 2>/dev/null || true
    INSTALL_LOG="$log_dir/$log_filename"
    log "更新日志路径到: $INSTALL_LOG"
    
    # 询问是否修改时区为中国上海
    read -rp "是否将系统时区修改为亚洲/上海? (y/N): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        TIMEZONE_SHANGHAI=true
    fi
    
    # 询问是否关闭 swap
    read -rp "是否关闭 swap? (y/N): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        SWAP_DISABLED=true
    fi
    
    # 询问是否换源 (Armbian 系统不提供此功能)
    if [ "$IS_ARMBIAN" = false ]; then
        read -rp "是否更换 apt 软件源为 USTC（中科大）? (y/N): " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            USE_CUSTOM_MIRROR=true
        fi
    else
        log "Armbian 系统不提供换源功能"
    fi
    
    # 询问是否安装 webserver 环境
    if ! dpkg -l | grep -q apache2; then
        read -rp "检测到系统未安装 webserver 环境，是否安装 Apache2? (Y/n): " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            WEB_SERVER_INSTALLED=true
        fi
    else
        log "检测到系统已安装 webserver 环境"
    fi
    
    # 询问是否安装 Docker
    read -rp "是否安装 Docker? (y/N): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
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
        read -rp "是否为 Docker 开启 IPv6 支持? (y/N): " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            DOCKER_ENABLE_IPV6=true
        fi
    fi
    
    # 询问是否修改 Apache 端口
    read -rp "是否修改 Apache 端口以避免与其他反向代理软件冲突? (y/N): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        MODIFY_APACHE_PORT=true
        read -rp "请输入新的 Apache 端口 (默认为 8080): " answer
        if [[ -n "$answer" ]] && [[ "$answer" =~ ^[0-9]+$ ]]; then
            APACHE_PORT="$answer"
        fi
    fi
    
    # 询问是否使用 GitHub 镜像加速
    read -rp "是否使用 GitHub 镜像加速下载 Landscape Router 文件? (y/N): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        USE_GITHUB_MIRROR=true
        echo "可选的 GitHub 镜像加速地址:"
        echo "1) https://ghfast.top (默认)"
        echo "2) 自定义地址"
        read -rp "请选择 (1-2, 默认为1): " answer
        case "$answer" in
            2)
                read -rp "请输入 GitHub 镜像加速地址: " GITHUB_MIRROR
                ;;
            *)
                GITHUB_MIRROR="https://ghfast.top"
                ;;
        esac
    fi
    
    # 配置 WAN 网卡
    config_wan_interface
    
    # 配置 LAN 网卡
    config_lan_interface
    
    log "用户配置询问完成"
}


# 配置 WAN 网卡
config_wan_interface() {
    echo "开始配置 WAN 网卡"
    
    # 获取可用网卡列表
    local interfaces
    interfaces=$(ip link show | awk -F': ' '/^[0-9]+: [a-zA-Z]/ {print $2}' | grep -v lo)
    
    echo "可用的网络接口:"
    local i=1
    for iface in $interfaces; do
        echo "$i) $iface"
        i=$((i+1))
    done
    
    # 选择 WAN 网卡
    while true; do
        read -rp "请选择作为 WAN 的网卡编号 (1-$((i-1))): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local selected_iface
            selected_iface=$(echo "$interfaces" | sed -n "${choice}p")
            WAN_CONFIG="iface_name = \"$selected_iface\""
            echo "已选择 $selected_iface 作为 WAN 网卡"
            break
        else
            echo "无效选择，请重新输入"
        fi
    done
    
    # 选择 WAN 配置模式
    echo "请选择 WAN 网卡配置模式:"
    echo "1) DHCP 客户端 (默认)"
    echo "2) 静态 IP"
    read -rp "请选择 (1-2, 默认为1): " choice
    
    case "$choice" in
        2)
            # 静态 IP 配置
            read -rp "请输入静态 IP 地址 (例如: 192.168.1.100): " static_ip
            read -rp "请输入子网掩码 (例如: 24): " static_mask
            read -rp "请输入网关 IP (例如: 192.168.1.1): " gateway_ip
            
            WAN_CONFIG+="
enable = true

[wan_config.ip_model]
t = \"static\"
default_router_ip = \"$gateway_ip\"
default_router = true
ipv4 = \"$static_ip\"
ipv4_mask = $static_mask"
            ;;
        *)
            # DHCP 客户端配置
            WAN_CONFIG+="
enable = true
update_at = $(date +%s)000.0

[wan_config.ip_model]
t = \"dhcpclient\"
default_router = true
custome_opts = []"
            ;;
    esac
}

# 配置 LAN 网卡
config_lan_interface() {
    echo "开始配置 LAN 网卡"
    
    # 获取可用网卡列表
    local interfaces
    interfaces=$(ip link show | awk -F': ' '/^[0-9]+: [a-zA-Z]/ {print $2}' | grep -v lo)
    
    # 询问网桥名称
    read -rp "请输入要创建的网桥名称 (默认为 lan1): " bridge_name
    if [ -z "$bridge_name" ]; then
        bridge_name="lan1"
    fi
    
    # 选择绑定到网桥的物理网卡
    echo "可用的网络接口 (请选择要绑定到 $bridge_name 网桥的网卡):"
    local i=1
    for iface in $interfaces; do
        echo "$i) $iface"
        i=$((i+1))
    done
    
    local selected_interfaces=()
    while true; do
        read -rp "请选择网卡编号 (输入编号后按回车，输入 'done' 完成选择): " choice
        if [ "$choice" = "done" ]; then
            if [ ${#selected_interfaces[@]} -eq 0 ]; then
                echo "至少需要选择一个网卡"
                continue
            fi
            break
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local selected_iface
            selected_iface=$(echo "$interfaces" | sed -n "${choice}p")
            
            # 检查是否已选择
            local already_selected=false
            for iface in "${selected_interfaces[@]}"; do
                if [ "$iface" = "$selected_iface" ]; then
                    already_selected=true
                    break
                fi
            done
            
            if [ "$already_selected" = true ]; then
                echo "网卡 $selected_iface 已选择，请选择其他网卡"
            else
                selected_interfaces+=("$selected_iface")
                echo "已选择网卡: $selected_iface"
            fi
        else
            echo "无效选择，请重新输入"
        fi
    done
    
    # 询问 LAN IP 和 DHCP 范围
    read -rp "请输入 LAN 网桥的 IP 地址 (默认为 192.168.88.1): " lan_ip
    if [ -z "$lan_ip" ]; then
        lan_ip="192.168.88.1"
    fi
    
    read -rp "请输入 DHCP IP 范围起始地址 (默认为 192.168.88.100): " dhcp_start
    if [ -z "$dhcp_start" ]; then
        dhcp_start="192.168.88.100"
    fi
    
    read -rp "请输入 DHCP IP 范围结束地址 (默认为 192.168.88.200): " dhcp_end
    if [ -z "$dhcp_end" ]; then
        dhcp_end="192.168.88.200"
    fi
    
    # 构建 LAN 配置
    LAN_CONFIG="bridge_name = \"$bridge_name\"
lan_ip = \"$lan_ip\"
dhcp_start = \"$dhcp_start\"
dhcp_end = \"$dhcp_end\"
interfaces = ($(printf '"%s", ' "${selected_interfaces[@]}" | sed 's/, $//'))"
}

# 执行安装
perform_installation() {
    log "开始执行安装"
    
    # 1. 修改时区
    if [ "$TIMEZONE_SHANGHAI" = true ]; then
        setup_timezone
    fi
    
    # 2. 关闭 swap
    if [ "$SWAP_DISABLED" = true ]; then
        disable_swap
    fi
    
    # 3. 换源
    if [ "$USE_CUSTOM_MIRROR" = true ]; then
        change_apt_mirror
    fi
    
    # 4. 安装 webserver
    if [ "$WEB_SERVER_INSTALLED" = true ]; then
        install_webserver
    fi
    
    # 5. 安装 Docker
    if [ "$DOCKER_INSTALLED" = true ]; then
        install_docker
        configure_docker
    fi
    
    # 6. 修改 Apache 端口
    if [ "$MODIFY_APACHE_PORT" = true ]; then
        modify_apache_port
    fi
    
    # 7. 创建 Landscape 目录
    create_landscape_dir
    
    # 8. 下载并安装 Landscape Router
    install_landscape_router
    
    # 9. 创建 systemd 服务
    create_systemd_service
    
    # 10. 配置网络接口
    configure_network_interfaces
    
    # 11. 关闭本机 DNS 服务
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
    log "关闭 swap"
    
    # 注释掉 fstab 中的 swap 条目
    sed -i 's/^[^#].*swap.*/#&/' /etc/fstab
    
    log "swap 关闭完成"
}

# 换源
change_apt_mirror() {
    log "更换 apt 软件源为 ustc 源"
    
    # 备份原源
    cp /etc/apt/sources.list /etc/apt/sources.list.bak
    
    # 写入新源
    cat > /etc/apt/sources.list << EOF
deb http://mirrors.ustc.edu.cn/debian/ trixie main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ trixie main contrib non-free non-free-firmware

deb http://mirrors.ustc.edu.cn/debian/ trixie-updates main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ trixie-updates main contrib non-free non-free-firmware

deb http://mirrors.ustc.edu.cn/debian/ trixie-backports main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian/ trixie-backports main contrib non-free non-free-firmware

# 安全更新源
deb http://mirrors.ustc.edu.cn/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://mirrors.ustc.edu.cn/debian-security trixie-security main contrib non-free non-free-firmware
EOF
    
    # 更新包索引
    apt update
    
    log "apt 软件源更换完成"
}


# 安装 webserver
install_webserver() {
    log "安装 Apache2"
    apt install apache2 -y
    log "Apache2 安装完成"
}

# 安装 Docker
install_docker() {
    log "安装 Docker"
    
    # 检查 curl 是否已安装，未安装则安装
    if ! command -v curl &> /dev/null; then
        log "未检测到 curl，正在安装..."
        apt update
        apt install curl -y
    else
        log "curl 已安装"
    fi
    
    # 根据选择的镜像源安装 Docker
    case "$DOCKER_MIRROR" in
        "aliyun")
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
            ;;
        "azure")
            curl -fsSL https://get.docker.com | bash -s docker --mirror AzureChinaCloud
            ;;
        *)
            curl -fsSL https://get.docker.com | bash
            ;;
    esac
    
    log "Docker 安装完成"
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

# 创建 Landscape 目录
create_landscape_dir() {
    log "创建 Landscape Router 目录: $LANDSCAPE_DIR"
    mkdir -p "$LANDSCAPE_DIR"
    log "Landscape Router 目录创建完成"
}


# 安装 Landscape Router
install_landscape_router() {
    log "下载并安装 Landscape Router"
    
    # 检查 curl 是否已安装，未安装则安装
    if ! command -v curl &> /dev/null; then
        log "未检测到 curl，正在安装..."
        apt update
        apt install curl -y
    else
        log "curl 已安装"
    fi
    
    # 获取最新稳定版本
    local version=""
    local retry=0
    local max_retry=10
    
    while [ $retry -lt $max_retry ]; do
        version=$(curl -s "https://api.github.com/repos/ThisSeanZhang/landscape/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
        if [ -n "$version" ]; then
            log "成功获取 Landscape Router 最新版本: $version"
            break
        else
            retry=$((retry+1))
            log "获取版本信息失败，正在进行第 $retry/$max_retry 次重试"
            sleep 3
        fi
    done
    
    if [ -z "$version" ]; then
        log "错误: 无法获取 Landscape Router 最新版本信息"
        exit 1
    fi
    
    log "检测到最新版本: $version"
    
    # 根据架构确定二进制文件名
    local binary_filename=""
    local system_arch
    system_arch=$(uname -m)
    if [ "$system_arch" = "aarch64" ]; then
        binary_filename="landscape-webserver-aarch64"
    else
        binary_filename="landscape-webserver-x86_64"
    fi
    
    # 下载 landscape-webserver 二进制文件
    local binary_url
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        binary_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/download/$version/$binary_filename"
    else
        binary_url="https://github.com/ThisSeanZhang/landscape/releases/download/$version/$binary_filename"
    fi
    
    local retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        log "正在下载 $binary_filename (尝试 $((retry+1))/$MAX_RETRY)"
        if curl -fsSL -o "$LANDSCAPE_DIR/$binary_filename" "$binary_url"; then
            log "$binary_filename 下载成功"
            break
        else
            retry=$((retry+1))
            log "下载失败，等待 5 秒后重试"
            sleep 5
        fi
    done
    
    if [ $retry -eq $MAX_RETRY ]; then
        log "错误: 下载 $binary_filename 失败"
        exit 1
    fi
    
    # 下载 static.zip
    local static_url
    if [ "$USE_GITHUB_MIRROR" = true ]; then
        static_url="$GITHUB_MIRROR/https://github.com/ThisSeanZhang/landscape/releases/download/$version/static.zip"
    else
        static_url="https://github.com/ThisSeanZhang/landscape/releases/download/$version/static.zip"
    fi
    
    retry=0
    while [ $retry -lt $MAX_RETRY ]; do
        log "正在下载 static.zip (尝试 $((retry+1))/$MAX_RETRY)"
        if curl -fsSL -o "/tmp/static.zip" "$static_url"; then
            log "static.zip 下载成功"
            break
        else
            retry=$((retry+1))
            log "下载失败，等待 5 秒后重试"
            sleep 5
        fi
    done
    
    if [ $retry -eq $MAX_RETRY ]; then
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
    
    log "Landscape Router 安装完成"
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
    log "配置网络接口"
    
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

# WAN interface
auto $(echo "$WAN_CONFIG" | grep "iface_name" | cut -d '"' -f 2)
iface $(echo "$WAN_CONFIG" | grep "iface_name" | cut -d '"' -f 2) inet manual

# LAN bridge
auto $(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2)
iface $(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2) inet static
    address $(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)
    netmask 255.255.255.0

EOF
    
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
    
    # 创建 landscape_init.toml 配置文件
    create_landscape_init_toml
    
    log "网络接口配置完成"
}


# 创建 landscape_init.toml 配置文件
create_landscape_init_toml() {
    log "创建 landscape_init.toml 配置文件"
    
    local wan_iface
    wan_iface=$(echo "$WAN_CONFIG" | grep "iface_name" | cut -d '"' -f 2)
    
    local bridge_name
    bridge_name=$(echo "$LAN_CONFIG" | grep "bridge_name" | cut -d '"' -f 2)
    
    local lan_ip
    lan_ip=$(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)
    
    local dhcp_start
    dhcp_start=$(echo "$LAN_CONFIG" | grep "dhcp_start" | cut -d '"' -f 2)
    
    local dhcp_end
    dhcp_end=$(echo "$LAN_CONFIG" | grep "dhcp_end" | cut -d '"' -f 2)
    
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
network_mask = 24
mac_binding_records = []

# ==== 配置 wan 网卡 ====
[[ifaces]]
name = "$wan_iface"
create_dev_type = "no_need_to_create"
zone_type = "wan"
enable_in_boot = true
wifi_mode = "undefined"

# WAN 网卡配置
[[ipconfigs]]
$(echo "$WAN_CONFIG" | grep -A 100 "enable = true")

# 将 $wan_iface 设为 默认路由
[[route_wans]]
iface_name = "$wan_iface"
enable = true

[[nats]]
iface_name = "$wan_iface"
enable = true

[nats.nat_config.tcp_range]
start = 32768
end = 65535

[nats.nat_config.udp_range]
start = 32768
end = 65535

[nats.nat_config.icmp_in_range]
start = 32768
end = 65535
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
    
    # 重启网络服务
    log "重启网络服务"
    systemctl restart networking
    
    # 启动 Landscape Router 服务
    log "启动 Landscape Router 服务"
    systemctl start landscape-router.service
    
    # 设置开机自启
    systemctl enable landscape-router.service >/dev/null 2>&1
    
    # 显示安装完成信息
    echo ""
    echo "=============================="
    echo "Landscape Router 安装完成!"
    echo "=============================="
    echo "请通过浏览器访问以下地址管理您的路由器:"
    local lan_ip
    lan_ip=$(echo "$LAN_CONFIG" | grep "lan_ip" | cut -d '"' -f 2)
    echo "  http://$lan_ip:6300"
    echo "默认用户名: root"
    echo "默认密码: root"
    echo ""
    echo "日志文件保存在: $INSTALL_LOG"
    echo ""
    echo "升级 Landscape Router 的方法:"
    echo "1. 从 https://github.com/ThisSeanZhang/landscape/releases 下载最新版本"
    echo "2. 停止服务: systemctl stop landscape-router.service"
    echo "3. 替换文件并设置权限"
    echo "4. 启动服务: systemctl start landscape-router.service"
    echo "或者使用项目提供的升级脚本 upgrade_landscape.sh"
    echo ""
    echo "如果遇到主机失联情况，请按以下步骤操作:"
    echo "1. 在物理机上将合适网卡改为 static 并配置 IP/掩码"
    echo "2. 通过配置的 IP 访问 主机 或 Landscape UI"
    echo "=============================="
    
    log "安装完成"
}

# 调用主函数
main "$@"
