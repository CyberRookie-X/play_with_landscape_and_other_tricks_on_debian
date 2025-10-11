#!/bin/sh

# 本脚本初次运行时，可能需要访问互联网
# 本脚本支持基于 debian/ubuntu/centos/rocky/alma 和 alpine 打包的镜像

# 环境变量说明：
# 环境变量只对 需要换源、安装依赖的 alpine 系镜像有效
# 不使用环境变量时，脚本从 互联网 API 获取必要信息，通常可以正常运行。
# 如需部署大量容器（例如大于100个），建议添加通过环境变量添加私有镜像仓库。
# 两个环境变量同时存在时，MIRROR 生效，REGION 失效。
#
# 1. REDIRECT_PKG_HANDLER_WRAPPER_REGION    
# 填入非 CN/cn 值时，跳过 IP 归属地检测 和 换源; 填入 CN/cn 会跳过 IP 归属地检测，从 中科大/清华/阿里/腾讯/华为/上交大/浙大/华科大/南大/哈工大 中随机选取一个可以成功 update 的源
# 2. REDIRECT_PKG_HANDLER_WRAPPER_MIRROR   
# 填入 alpine 镜像源地址，如 西北农林大学镜像源  REDIRECT_PKG_HANDLER_WRAPPER_MIRROR=mirrors.nwafu.edu.cn
# 3. ORIGINAL_ENTRYPOINT_CMD
# 用于传入镜像原始的 entrypoint 或 CMD，当这个环境变量不为空时会被采用 ORIGINAL_ENTRYPOINT_CMD=/docker-entrypoint.sh nginx -g daemon off;  # 原始镜像的 ENTRYPOINT 和 CMD

# 脚本逻辑说明
# 1、检查 容器系统 是否属于 debian/ubuntu/centos/rocky/alma，在此范围之外的系统暂不支持
# 2、对于 debian/ubuntu/centos/rocky/alma，配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD
# 3、对于 alpine，具有 libelf 和 libgcc支持的，则配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD
# 4、对于 alpine，没有 libelf 和 libgcc 支持
# 4.1 确定 是否处于 无法访问 alpine 官方源 的地区。通过 环境变量 REDIRECT_PKG_HANDLER_WRAPPER_REGION 或 本机 IP 归属地查询，确定 是否处于 无法访问 alpine 官方源 的地区
# 4.2 对于 alpine 源不可用的 国家/地区，如中国，进行换源操作
# 4.3 采用 环境变量 REDIRECT_PKG_HANDLER_WRAPPER_MIRROR 给出的源 或者 从 中科大/清华/阿里/腾讯/华为/上交大/浙大/华科大/南大/哈工大 中随机选一个 能成功 apk update 的源
# 4.4 安装 libelf 和 libgcc，配置防火墙，启动 redirect_pkg_handler ，等待 0.2 s，最后执行原始镜像的 ENTRYPOINT 和 CMD

# 使用方式:
# 1、从 dockerfile 或 docker inspect 找到 镜像原始的 ENTRYPOINT 和 CMD
# 2、下载 redirect_pkg_handler-XXXXXXXX （从github下载后，无需修改该其文件名） 和 redirect_pkg_handler.sh 到 landscape Router 所在主机中，赋予可执行权限
# 3、在 docker run、docker-compose.yml 或 Dockerfile 中将本脚本设置为 ENTRYPOINT，并将原始镜像的 ENTRYPOINT和 CMD 作为参数传递
# 4、将 redirect_pkg_handler-XXXXXXXX （从github下载后，无需修改该其文件名） 和 redirect_pkg_handler.sh 挂载到 容器 /landscape 或 /land 目录下（支持两种路径）

# 例如: ENTRYPOINT ["/landscape/redirect_pkg_handler.sh", "/original/entrypoint", "original", "cmd", "args"]
# 或者: ENTRYPOINT ["/land/redirect_pkg_handler.sh", "/original/entrypoint", "original", "cmd", "args"]

# 示例1
# version: '3.8'
# services:
#   my-service:
#     image: some-image:latest
#     entrypoint: ["/landscape/redirect_pkg_handler.sh", "/original/entrypoint", "original", "cmd", "args"]
#     # 其他配置...

# 示例1a（使用 /land 目录）
# version: '3.8'
# services:
#   my-service:
#     image: some-image:latest
#     entrypoint: ["/land/redirect_pkg_handler.sh", "/original/entrypoint", "original", "cmd", "args"]
#     # 其他配置...

# 示例2
# version: '3.8'
# services:
#   my-service:
#     image: some-image:latest
#     entrypoint:
#       - "/landscape/redirect_pkg_handler.sh"
#       - "/docker-entrypoint.sh"  # 原始镜像的 ENTRYPOINT
#       - "nginx"                  # 原始镜像的 CMD
#       - "-g"                     # 原始镜像的 CMD 参数
#       - "daemon off;"            # 原始镜像的 CMD 参数

# 示例2a（使用 /land 目录）
# version: '3.8'
# services:
#   my-service:
#     image: some-image:latest
#     entrypoint:
#       - "/land/redirect_pkg_handler.sh"
#       - "/docker-entrypoint.sh"  # 原始镜像的 ENTRYPOINT
#       - "nginx"                  # 原始镜像的 CMD
#       - "-g"                     # 原始镜像的 CMD 参数
#       - "daemon off;"            # 原始镜像的 CMD 参数

# 示例3（使用 ORIGINAL_ENTRYPOINT_CMD 环境变量）
# version: '3.8'
# services:
#   my-service:
#     image: some-image:latest
#     environment:
#       - ORIGINAL_ENTRYPOINT_CMD=/docker-entrypoint.sh nginx -g daemon off;  # 原始镜像的 ENTRYPOINT 和 CMD
#     entrypoint: ["/landscape/redirect_pkg_handler.sh"]
#     # 其他配置...

# 示例3a（使用 ORIGINAL_ENTRYPOINT_CMD 环境变量和 /land 目录）
# version: '3.8'
# services:
#   my-service:
#     image: some-image:latest
#     environment:
#       - ORIGINAL_ENTRYPOINT_CMD=/docker-entrypoint.sh nginx -g daemon off;  # 原始镜像的 ENTRYPOINT 和 CMD
#     entrypoint: ["/land/redirect_pkg_handler.sh"]
#     # 其他配置...

# ==================== 常量定义 ====================

# 系统检测相关
readonly DEBIAN_VERSION_FILE="/etc/debian_version"
readonly OS_RELEASE_FILE="/etc/os-release"
readonly REDHAT_RELEASE_FILE="/etc/redhat-release"

# 目录路径
readonly HANDLER_DIR_LANDSCAPE="/landscape"
readonly HANDLER_DIR_LAND="/land"
readonly ALPINE_REPOSITORIES_FILE="/etc/apk/repositories"
readonly ALPINE_REPOSITORIES_BACKUP="/etc/apk/repositories.bak"

# 网络和超时
readonly DEFAULT_TIMEOUT=1
readonly MAX_RETRY=3
readonly IP_CHECK_TIMEOUT=4
readonly INSTALL_TIMEOUT=15
readonly HANDLER_DELAY=0.2

# 路由和防火墙
readonly FIREWALL_MARK=0x1
readonly ROUTE_TABLE_ID=100

# 国家/地区
readonly CHINA_CODE="CN"
readonly CHINA_NAME="中国"

# 架构
readonly ARCH_X86_64="x86_64"
readonly ARCH_AARCH64="aarch64"

# Alpine 依赖包
readonly ALPINE_PACKAGES="libelf libgcc"

# 镜像源列表
readonly MIRRORS="mirrors.ustc.edu.cn mirrors.aliyun.com mirrors.tuna.tsinghua.edu.cn mirrors.cloud.tencent.com repo.huaweicloud.com mirrors.sjtug.sjtu.edu.cn mirrors.zju.edu.cn mirrors.hust.edu.cn mirrors.nju.edu.cn mirrors.hit.edu.cn"

# API 端点
readonly APIS="https://myip.ipip.net/ http://ip-api.com/json/ https://ip.sb/ http://ipwho.is/ http://ipinfo.io/country"

# 用户代理
readonly USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

# ==================== 全局变量 ====================

# 资源清理相关
TEMP_FILES=""
BACKGROUND_PIDS=""
CLEANUP_DONE=false

# 信号处理函数
cleanup_on_exit() {
    [ "$CLEANUP_DONE" = "true" ] && return
    
    # 终止后台进程
    for pid in $BACKGROUND_PIDS; do
        kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null
    done
    
    # 清理临时文件
    for temp_file in $TEMP_FILES; do
        rm -f "$temp_file" 2>/dev/null
    done
    
    CLEANUP_DONE=true
}

# 注册信号处理
trap 'cleanup_on_exit' EXIT TERM INT

# 保存原始的ENTRYPOINT和CMD
if [ -n "$ORIGINAL_ENTRYPOINT_CMD" ]; then
    # 验证ORIGINAL_ENTRYPOINT_CMD
    if echo "$ORIGINAL_ENTRYPOINT_CMD" | grep -q '[^a-zA-Z0-9/._\[:space:];-]'; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [redirect_pkg_handler_wrapper] ERROR: Invalid characters in ORIGINAL_ENTRYPOINT_CMD" >&2
        exit 1
    fi
else
    ORIGINAL_ENTRYPOINT_CMD="$@"
fi

# 获取CPU架构
ARCH=$(uname -m)

# ==================== 主函数 ====================

main() {
    # 检测系统类型并处理
    if is_debian_based || is_redhat_based; then
        simple_system_handler
    elif is_alpine; then
        alpine_system_handler
    else
        log_error "Unsupported OS distribution"
        exit 1
    fi

    # 等待 handler 启动完成
    sleep "$HANDLER_DELAY"

    # 执行原始的ENTRYPOINT和CMD
    execute_original_entrypoint
}

# ==================== 系统检测函数 ====================

is_debian_based() {
    [ -f "$DEBIAN_VERSION_FILE" ] || grep -qi ubuntu "$OS_RELEASE_FILE" 2>/dev/null
}

is_redhat_based() {
    [ -f "$REDHAT_RELEASE_FILE" ] || grep -qi "centos\|rocky\|alma" "$OS_RELEASE_FILE" 2>/dev/null
}

is_alpine() {
    grep -qi alpine "$OS_RELEASE_FILE" 2>/dev/null
}

# ==================== 日志和工具函数 ====================

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [redirect_pkg_handler_wrapper] INFO: $1"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [redirect_pkg_handler_wrapper] ERROR: $1" >&2
}

# 兼容性延时函数
compat_sleep() {
    local delay_ms="$1"
    if command -v usleep >/dev/null 2>&1; then
        usleep "$delay_ms"000 2>/dev/null
    else
        sleep "$(echo "$delay_ms" | awk '{print $1/1000}')"
    fi
}

# 随机数生成
srand() {
    if [ -r "/dev/urandom" ] && command -v od >/dev/null 2>&1; then
        RANDOM_SEED=$(od -vAn -N4 -tu4 < /dev/urandom | tr -d ' ')
    else
        # 尝试使用纳秒级时间戳，如果不支持则回退到秒级
        if date +%s%N >/dev/null 2>&1; then
            RANDOM_SEED=$(date +%s%N)$$
        else
            RANDOM_SEED=$(date +%s)$$
        fi
        RANDOM_SEED=$((RANDOM_SEED * 1103515245 + 12345))
    fi
    RANDOM_SEED=$((RANDOM_SEED * 1103515245 + 12345))
    echo $((RANDOM_SEED >> 16))
}

# 检测 handler 目录
detect_handler_directory() {
    if [ -d "$HANDLER_DIR_LANDSCAPE" ]; then
        HANDLER_DIR="$HANDLER_DIR_LANDSCAPE"
    elif [ -d "$HANDLER_DIR_LAND" ]; then
        HANDLER_DIR="$HANDLER_DIR_LAND"
    else
        log_error "Neither $HANDLER_DIR_LANDSCAPE nor $HANDLER_DIR_LAND directory found"
        return 1
    fi
    return 0
}

# 执行原始入口点
execute_original_entrypoint() {
    if [ -n "$ORIGINAL_ENTRYPOINT_CMD" ]; then
        log_info "Executing original entrypoint: $ORIGINAL_ENTRYPOINT_CMD"
        
        # 安全检查
        first_arg=$(echo "$ORIGINAL_ENTRYPOINT_CMD" | awk '{print $1}')
        if [ -n "$first_arg" ] && [ "${first_arg#/}" != "$first_arg" ] && [ ! -x "$first_arg" ]; then
            log_error "Original entrypoint not executable: $first_arg"
            exit 1
        fi
        
        exec "$ORIGINAL_ENTRYPOINT_CMD"
    else
        log_info "No original entrypoint found, exiting"
        exit 0
    fi
}

# ==================== 通用函数 ====================

# HTTP请求函数
make_http_request() {
    local url="$1"
    
    if command -v wget >/dev/null 2>&1; then
        for i in $(seq 1 $MAX_RETRY); do
            if wget -qO- --header="User-Agent: $USER_AGENT" --timeout="$DEFAULT_TIMEOUT" "$url" 2>/dev/null; then
                return 0
            fi
        done
    elif command -v curl >/dev/null 2>&1; then
        for i in $(seq 1 $MAX_RETRY); do
            if curl -s --connect-timeout "$DEFAULT_TIMEOUT" --max-time "$DEFAULT_TIMEOUT" -H "User-Agent: $USER_AGENT" "$url" 2>/dev/null; then
                return 0
            fi
        done
    else
        log_error "Neither wget nor curl is available for HTTP requests"
    fi
}

# 设置路由规则
setup_routing_rules() {
    if ! command -v ip >/dev/null 2>&1; then
        log_error "ip command not found"
        return 1
    fi
    
    if ! ip rule add fwmark "$FIREWALL_MARK" lookup "$ROUTE_TABLE_ID" 2>/dev/null; then
        log_error "Failed to add ip rule"
        return 1
    fi
    
    if ! ip route add local default dev lo table "$ROUTE_TABLE_ID" 2>/dev/null; then
        log_error "Failed to add ip route"
        return 1
    fi
    
    return 0
}

# 启动处理程序
start_handler() {
    if ! detect_handler_directory; then
        exit 1
    fi
    
    if ! setup_routing_rules; then
        log_error "Failed to setup routing rules"
        exit 1
    fi
    
    local handler_suffix=""
    if is_alpine; then
        handler_suffix="-musl"
    fi
    
    case "$ARCH" in
        "$ARCH_X86_64")
            handler_path="$HANDLER_DIR/redirect_pkg_handler-x86_64$handler_suffix"
            ;;
        "$ARCH_AARCH64")
            handler_path="$HANDLER_DIR/redirect_pkg_handler-aarch64$handler_suffix"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            return 1
            ;;
    esac
    
    if [ ! -x "$handler_path" ]; then
        log_error "Handler not found or not executable: $handler_path"
        return 1
    fi
    
    log_info "Starting handler for $ARCH in background"
    "$handler_path" &
    BACKGROUND_PIDS="$BACKGROUND_PIDS $!"
}

# ==================== 非 Alpine 系统处理 ====================

simple_system_handler() {
    log_info "Detected Debian/Ubuntu/CentOS/Rocky Linux/AlmaLinux system"
    start_handler
}

# ==================== Alpine 系统处理 ====================

# 检查依赖
check_dependencies() {
    for package in $ALPINE_PACKAGES; do
        if ! apk info "$package" >/dev/null 2>&1; then
            return 1  # 需要安装依赖
        fi
    done
    return 0  # 依赖已安装
}

# 备份源配置
backup_repositories() {
    if [ ! -f "$ALPINE_REPOSITORIES_FILE" ]; then
        log_error "Alpine repositories file not found: $ALPINE_REPOSITORIES_FILE"
        return 1
    fi
    
    if ! cp "$ALPINE_REPOSITORIES_FILE" "$ALPINE_REPOSITORIES_BACKUP" 2>/dev/null; then
        log_error "Failed to backup Alpine repositories file"
        return 1
    fi
    
    return 0
}

# 更新镜像源
update_mirror() {
    local mirror="$1"
    
    if echo "$mirror" | grep -q '[^a-zA-Z0-9._-]'; then
        log_error "Invalid mirror format: $mirror"
        return 1
    fi
    
    if ! sed -i "s/dl-cdn.alpinelinux.org/$mirror/g" "$ALPINE_REPOSITORIES_FILE" 2>/dev/null; then
        log_error "Failed to update Alpine mirror: $mirror"
        return 1
    fi
    
    return 0
}

# 恢复源配置
restore_repositories() {
    if [ -f "$ALPINE_REPOSITORIES_BACKUP" ]; then
        cp "$ALPINE_REPOSITORIES_BACKUP" "$ALPINE_REPOSITORIES_FILE" 2>/dev/null
    fi
    apk update >/dev/null 2>&1
}

# 随机选择镜像源
select_random_mirror() {
    local mirrors="$1"
    local mirror_count=$(echo $mirrors | wc -w)
    local random_index=$(( ( $(srand) % mirror_count ) + 1 ))
    echo $mirrors | cut -d' ' -f$random_index
}

# 移除镜像源
remove_mirror() {
    local mirrors="$1"
    local mirror_to_remove="$2"
    echo "$mirrors" | sed "s/$mirror_to_remove//g" | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

# 处理镜像源
handle_mirrors() {
    local mirror_source="$1"
    local description="$2"
    
    log_info "Changing to mirror ($description)"
    backup_repositories || return 1
    
    # 单一镜像源
    if [ "$(echo "$mirror_source" | wc -w)" -eq 1 ]; then
        log_info "Using specified mirror: $mirror_source"
        update_mirror "$mirror_source" || return 1
        
        if apk update >/dev/null 2>&1; then
            log_info "Successfully updated with specified mirror: $mirror_source"
            return 0
        else
            log_error "Failed to update with specified mirror: $mirror_source"
            restore_repositories
            return 1
        fi
    fi
    
    # 多个镜像源
    local available_mirrors="$mirror_source"
    local update_success=false
    
    while [ "$update_success" = "false" ] && [ -n "$available_mirrors" ]; do
        local selected_mirror=$(select_random_mirror "$available_mirrors")
        
        log_info "Trying mirror: $selected_mirror"
        update_mirror "$selected_mirror" || {
            available_mirrors=$(remove_mirror "$available_mirrors" "$selected_mirror")
            continue
        }
        
        if apk update >/dev/null 2>&1; then
            update_success=true
            log_info "Successfully updated with mirror: $selected_mirror"
        else
            log_error "Failed to update with mirror: $selected_mirror"
            available_mirrors=$(remove_mirror "$available_mirrors" "$selected_mirror")
            restore_repositories
        fi
    done
    
    if [ "$update_success" = "false" ]; then
        log_error "Failed to update with all mirrors, restoring original configuration"
        restore_repositories
        return 1
    fi
    
    return 0
}

# 处理环境变量
handle_env_vars() {
    # 检查镜像源环境变量
    if [ -n "$REDIRECT_PKG_HANDLER_WRAPPER_MIRROR" ]; then
        if echo "$REDIRECT_PKG_HANDLER_WRAPPER_MIRROR" | grep -q '[^a-zA-Z0-9._-]'; then
            log_error "Invalid mirror format in environment variable: $REDIRECT_PKG_HANDLER_WRAPPER_MIRROR"
            return 1
        fi
        
        handle_mirrors "$REDIRECT_PKG_HANDLER_WRAPPER_MIRROR" "from environment variable"
        return 0
    fi
    
    # 检查区域环境变量
    if [ -n "$REDIRECT_PKG_HANDLER_WRAPPER_REGION" ]; then
        if echo "$REDIRECT_PKG_HANDLER_WRAPPER_REGION" | grep -q '[^a-zA-Z]'; then
            log_error "Invalid region format in environment variable: $REDIRECT_PKG_HANDLER_WRAPPER_REGION"
            return 1
        fi
        
        local region_upper=$(echo "$REDIRECT_PKG_HANDLER_WRAPPER_REGION" | tr '[:lower:]' '[:upper:]')
        
        if [ "$region_upper" = "$CHINA_CODE" ]; then
            log_info "Region set to CN, skipping IP detection and using random mirror"
            handle_mirrors "$MIRRORS" "random from predefined list for CN region"
        else
            log_info "Region set to $REDIRECT_PKG_HANDLER_WRAPPER_REGION, skipping IP detection and mirror change"
            apk update >/dev/null 2>&1
        fi
        return 0
    fi
    
    return 1  # 没有设置环境变量
}

# 检测IP归属地
detect_ip_country() {
    PUBLIC_IP_COUNTRY=""
    
    # 创建临时目录
    local temp_dir="/tmp/ip_check_$$"
    mkdir -p "$temp_dir" 2>/dev/null || {
        log_error "Failed to create temporary directory for IP checks"
        return 1
    }
    
    TEMP_FILES="$TEMP_FILES $temp_dir"
    
    # 并行执行多个API查询
    local pids=""
    for api in $APIS; do
        {
            local result=""
            case "$api" in
                *myip.ipip.net*)
                    result=$(make_http_request "$api" | grep -o "$CHINA_NAME")
                    ;;
                *ip-api.com*|*ip.sb*|*ipwho.is*)
                    result=$(make_http_request "$api" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
                    ;;
                *ipinfo.io*)
                    result=$(make_http_request "$api" | tr -d '\n')
                    ;;
            esac
            echo "$result" > "$temp_dir/$(echo $api | tr '/:' '_')"
        } &
        pids="$pids $!"
    done
    
    # 等待结果
    local count=0
    while [ $count -lt 40 ]; do
        for api in $APIS; do
            local file="$temp_dir/$(echo $api | tr '/:' '_')"
            if [ -f "$file" ]; then
                local result=$(cat "$file" 2>/dev/null | tr -d '\n')
                if [ "$result" = "$CHINA_CODE" ] || [ "$result" = "$CHINA_NAME" ]; then
                    PUBLIC_IP_COUNTRY="$CHINA_CODE"
                    log_info "Detected China IP via $api"
                    return 0
                fi
            fi
        done
        
        count=$((count + 1))
        compat_sleep 100
    done
    
    log_info "Public IP country: $PUBLIC_IP_COUNTRY"
}

# 根据IP归属地处理镜像源
handle_mirror_by_ip() {
    if [ "$PUBLIC_IP_COUNTRY" = "$CHINA_CODE" ]; then
        handle_mirrors "$MIRRORS" "based on IP location"
    else
        log_info "Not in China or failed to detect IP location, proceeding with default repositories"
        apk update >/dev/null 2>&1
    fi
}

# 安装依赖
install_dependencies() {
    # 检查是否需要启用重试功能
    local use_retry=false
    if [ -n "$REDIRECT_PKG_HANDLER_WRAPPER_REGION" ] && [ -z "$REDIRECT_PKG_HANDLER_WRAPPER_MIRROR" ]; then
        local region_upper=$(echo "$REDIRECT_PKG_HANDLER_WRAPPER_REGION" | tr '[:lower:]' '[:upper:]')
        [ "$region_upper" = "$CHINA_CODE" ] && use_retry=true
    fi
    
    if [ "$use_retry" = "true" ]; then
        install_with_retry
    else
        install_simple
    fi
    
    # 清除缓存
    rm -rf /var/cache/apk/* 2>/dev/null || true
}

# 带重试的安装
install_with_retry() {
    log_info "Attempting to install dependencies with timeout and mirror retry feature (region: CN)"
    
    # 尝试安装
    local install_success=false
    if command -v timeout >/dev/null 2>&1; then
        if timeout "${INSTALL_TIMEOUT}s" apk add --no-cache $ALPINE_PACKAGES; then
            install_success=true
        fi
    else
        if apk add --no-cache $ALPINE_PACKAGES; then
            install_success=true
        fi
    fi
    
    if [ "$install_success" = "true" ]; then
        log_info "Dependencies installed successfully with current mirror"
        return
    fi
    
    log_info "Installation failed, trying to switch mirror and retry"
    
    # 备份当前源配置
    cp "$ALPINE_REPOSITORIES_FILE" "${ALPINE_REPOSITORIES_FILE}.install.bak" 2>/dev/null
    
    # 尝试不同镜像源
    local available_mirrors="$MIRRORS"
    local retry_success=false
    
    while [ "$retry_success" = "false" ] && [ -n "$available_mirrors" ]; do
        local selected_mirror=$(select_random_mirror "$available_mirrors")
        
        log_info "Retrying with mirror: $selected_mirror"
        
        if update_mirror "$selected_mirror" && apk update >/dev/null 2>&1; then
            log_info "Successfully updated package index with mirror: $selected_mirror"
            
            # 尝试安装
            if command -v timeout >/dev/null 2>&1; then
                if timeout "${INSTALL_TIMEOUT}s" apk add --no-cache $ALPINE_PACKAGES; then
                    log_info "Dependencies installed successfully with mirror: $selected_mirror"
                    retry_success=true
                fi
            else
                if apk add --no-cache $ALPINE_PACKAGES; then
                    log_info "Dependencies installed successfully with mirror: $selected_mirror"
                    retry_success=true
                fi
            fi
        fi
        
        if [ "$retry_success" = "false" ]; then
            available_mirrors=$(remove_mirror "$available_mirrors" "$selected_mirror")
        fi
    done
    
    # 如果所有镜像源都尝试失败，恢复原始配置
    if [ "$retry_success" = "false" ]; then
        log_error "Failed to install dependencies with all mirrors, restoring original configuration"
        cp "${ALPINE_REPOSITORIES_FILE}.install.bak" "$ALPINE_REPOSITORIES_FILE" 2>/dev/null
        apk update >/dev/null 2>&1
        
        # 最后尝试一次安装，即使失败也继续
        if command -v timeout >/dev/null 2>&1; then
            timeout "${INSTALL_TIMEOUT}s" apk add --no-cache $ALPINE_PACKAGES || true
        else
            apk add --no-cache $ALPINE_PACKAGES || true
        fi
    fi
    
    # 清理备份文件
    rm -f "${ALPINE_REPOSITORIES_FILE}.install.bak"
}

# 简单安装
install_simple() {
    log_info "Installing dependencies without timeout and mirror retry feature"
    if ! apk add --no-cache $ALPINE_PACKAGES; then
        log_error "Failed to install dependencies"
        return 1
    fi
    return 0
}

# Alpine系统处理主函数
alpine_system_handler() {
    log_info "Detected Alpine system"
    
    # 检查依赖
    if check_dependencies; then
        log_info "Required libraries already installed"
        start_handler
        return
    fi
    
    # 处理镜像源（环境变量优先）
    if ! handle_env_vars; then
        # 检测公网IP归属地
        detect_ip_country
        # 根据IP归属地处理镜像源
        handle_mirror_by_ip
    fi
    
    # 安装依赖
    if ! install_dependencies; then
        log_error "Failed to install Alpine dependencies"
        exit 1
    fi
    
    # 启动处理程序
    start_handler
}

# 启动主函数
main
