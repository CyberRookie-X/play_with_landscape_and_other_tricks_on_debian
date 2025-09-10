#!/bin/sh

# 本脚本初次运行时，可能需要访问互联网
# 本脚本支持基于 debian、ubuntu 和 alpine 打包的镜像

# 使用方式: 
# 1、下载 redirect_pkg_handler-XXXXXXXX （从github下载后，无需修改该其文件名） 和 redirect_pkg_handler.sh 到 landscape Router 所在主机中，赋予可执行权限
# 2、在 docker run、docker-compose.yaml 或 Dockerfile 中将本脚本设置为 ENTRYPOINT，并将原始镜像的 ENTRYPOINT和 CMD 作为参数传递
# 3、将 redirect_pkg_handler-XXXXXXXX （从github下载后，无需修改该其文件名） 和 redirect_pkg_handler.sh 挂载到 容器 /land 目录下

# 例如: ENTRYPOINT ["/land/redirect_pkg_handler.sh", "/original/entrypoint", "original", "cmd", "args"]

# 示例1
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
#       - "/land/redirect_pkg_handler.sh"
#       - "/docker-entrypoint.sh"  # 原始镜像的 ENTRYPOINT
#       - "nginx"                  # 原始镜像的 CMD
#       - "-g"                     # 原始镜像的 CMD 参数
#       - "daemon off;"            # 原始镜像的 CMD 参数

# 脚本逻辑说明
# 1、检查 容器是debian/ubuntu还是alpine
# 2、对于 debian/ubuntu，配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD
# 3、对于 alpine，具有 libelf 和 libgcc支持的，则配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD
# 4、对于 alpine，没有 libelf 和 libgcc 支持
# 4.1 通过 本机 IP 归属地查询，确定 alpine 源的可用性
# 4.2 对于 alpine 源不可用的 国家/地区，如中国，进行换源操作
# 4.3 安装 libelf 和 libgcc，配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD


# 保存原始的ENTRYPOINT和CMD
ORIGINAL_ENTRYPOINT_CMD="$@"

# 日志函数，确保日志格式符合Docker规范，不依赖echo命令
log() {
    printf "%s %s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "[redirect_pkg_handler]" "$1"
}

# 获取CPU架构
ARCH=$(uname -m)

# 检查容器是debian/ubuntu还是alpine
if [ -f /etc/debian_version ] || grep -qi ubuntu /etc/os-release 2>/dev/null; then
    # Debian/Ubuntu处理
    log "Detected Debian/Ubuntu system"
    
    # 添加路由规则
    ip rule add fwmark 0x1/0x1 lookup 100
    ip route add local default dev lo table 100
    
    # 根据架构运行对应程序
    if [ "$ARCH" = "x86_64" ]; then
        log "Starting x86_64 handler in background"
        /land/redirect_pkg_handler-x86_64 &
    elif [ "$ARCH" = "aarch64" ]; then
        log "Starting aarch64 handler in background"
        /land/redirect_pkg_handler-aarch64 &
    else
        log "Unsupported architecture: $ARCH"
    fi
    
elif grep -qi alpine /etc/os-release 2>/dev/null; then
    # Alpine处理
    log "Detected Alpine system"
    
    # 检查是否具有libelf和libgcc支持
    LIBELF_INSTALLED=false
    LIBGCC_INSTALLED=false
    
    # 简单检查库是否存在
    if ldconfig -p 2>/dev/null | grep -q libelf; then
        LIBELF_INSTALLED=true
    fi
    
    if ldconfig -p 2>/dev/null | grep -q libgcc; then
        LIBGCC_INSTALLED=true
    fi
    
    # 如果libelf或libgcc未安装，则执行以下操作
    if [ "$LIBELF_INSTALLED" = "false" ] || [ "$LIBGCC_INSTALLED" = "false" ]; then
        log "Installing required libraries"
        
        # 获取本机公网IP归属国家
        PUBLIC_IP_COUNTRY=""
        
        # 定义多个API查询函数，设置1秒超时，重试4次
        check_myip_ipip() {
            if command -v wget >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(wget -qO- --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" --timeout=1 https://myip.ipip.net/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '中国' >/dev/null && { printf "中国"; return; }
                done
            elif command -v curl >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(curl -s --connect-timeout 1 --max-time 1 -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" https://myip.ipip.net/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '中国' >/dev/null && { printf "中国"; return; }
                done
            fi
        }
        
        check_ipinfo() {
            if command -v wget >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    wget -qO- --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" --timeout=1 http://ipinfo.io/country 2>/dev/null | tr -d '\n' && return
                done
            elif command -v curl >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    curl -s --connect-timeout 1 --max-time 1 -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" http://ipinfo.io/country 2>/dev/null | tr -d '\n' && return
                done
            fi
        }
        
        check_ip_api() {
            if command -v wget >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(wget -qO- --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" --timeout=1 http://ip-api.com/json/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 && return
                done
            elif command -v curl >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(curl -s --connect-timeout 1 --max-time 1 -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" http://ip-api.com/json/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 && return
                done
            fi
        }
        
        # 并行执行多个API查询，任何一个返回中国大陆就执行换源
        TEMP_FILE="/tmp/ip_country_check.$$"
        rm -f "$TEMP_FILE"
        
        # 后台执行多个检查
        check_myip_ipip > "$TEMP_FILE.ipip" &
        IPIP_PID=$!
        
        check_ipinfo > "$TEMP_FILE.info" &
        INFO_PID=$!
        
        check_ip_api > "$TEMP_FILE.api" &
        API_PID=$!
        
        # 等待最多1秒
        sleep 1
        
        # 检查各个API的返回结果
        if [ -f "$TEMP_FILE.ipip" ]; then
            RESULT=$(cat "$TEMP_FILE.ipip" | tr -d '\n')
            if [ "$RESULT" = "中国" ]; then
                PUBLIC_IP_COUNTRY="CN"
                log "Detected China IP via myip.ipip.net"
            fi
        fi
        
        if [ -z "$PUBLIC_IP_COUNTRY" ] && [ -f "$TEMP_FILE.info" ]; then
            RESULT=$(cat "$TEMP_FILE.info" | tr -d '\n')
            if [ "$RESULT" = "CN" ] || [ "$RESULT" = "China" ] || [ "$RESULT" = "中国" ]; then
                PUBLIC_IP_COUNTRY="$RESULT"
                log "Detected China IP via ipinfo.io"
            fi
        fi
        
        if [ -z "$PUBLIC_IP_COUNTRY" ] && [ -f "$TEMP_FILE.api" ]; then
            RESULT=$(cat "$TEMP_FILE.api" | tr -d '\n')
            if [ "$RESULT" = "CN" ] || [ "$RESULT" = "China" ] || [ "$RESULT" = "中国" ]; then
                PUBLIC_IP_COUNTRY="$RESULT"
                log "Detected China IP via ip-api.com"
            fi
        fi
        
        # 清理临时文件
        rm -f "$TEMP_FILE"*
        
        log "Public IP country: $PUBLIC_IP_COUNTRY"
        
        # 只有当明确检测到中国大陆IP时才执行换源
        if [ "$PUBLIC_IP_COUNTRY" = "CN" ] || [ "$PUBLIC_IP_COUNTRY" = "China" ] || [ "$PUBLIC_IP_COUNTRY" = "中国" ]; then
            log "Changing to USTC mirror"
            # 备份原始源
            cp /etc/apk/repositories /etc/apk/repositories.bak
            # 使用sed命令替换默认源为USTC镜像源
            sed -i 's/dl-cdn.alpinelinux.org/mirrors.ustc.edu.cn/g' /etc/apk/repositories
        else
            log "Not in China or failed to detect IP location, proceeding with default repositories"
        fi
        
        # 安装libelf和libgcc
        apk update
        apk add libelf libgcc
        
        # 添加路由规则
        ip rule add fwmark 0x1/0x1 lookup 100
        ip route add local default dev lo table 100
        
        # 根据架构运行对应程序
        if [ "$ARCH" = "x86_64" ]; then
            log "Starting x86_64 musl handler in background"
            /land/redirect_pkg_handler-x86_64-musl &
        elif [ "$ARCH" = "aarch64" ]; then
            log "Starting aarch64 musl handler in background"
            /land/redirect_pkg_handler-aarch64-musl &
        else
            log "Unsupported architecture: $ARCH"
        fi
    else
        # 库已安装，直接添加路由规则并运行程序
        log "Required libraries already installed"
        
        # 添加路由规则
        ip rule add fwmark 0x1/0x1 lookup 100
        ip route add local default dev lo table 100
        
        # 根据架构运行对应程序
        if [ "$ARCH" = "x86_64" ]; then
            log "Starting x86_64 musl handler in background"
            /land/redirect_pkg_handler-x86_64-musl &
        elif [ "$ARCH" = "aarch64" ]; then
            log "Starting aarch64 musl handler in background"
            /land/redirect_pkg_handler-aarch64-musl &
        else
            log "Unsupported architecture: $ARCH"
        fi
    fi
else
    log "Unsupported OS distribution"
fi

# 等待后台进程启动完成
wait_for_background_processes() {
    local timeout=10  # 最多等待10秒
    local count=0
    
    # 检查是否有后台进程在运行
    while [ $count -lt $timeout ]; do
        # 检查是否有正在运行的后台作业
        if jobs > /dev/null 2>&1; then
            # 有后台作业在运行，等待一小段时间
            sleep 0.5
            count=$((count + 1))
        else
            # 没有后台作业，说明所有后台进程都已完成启动
            break
        fi
    done
    
    if [ $count -ge $timeout ]; then
        log "Warning: Background processes did not start within $timeout seconds"
    else
        log "Background processes started successfully"
    fi
}

# 等待后台进程启动完成
wait_for_background_processes

# 执行原始的ENTRYPOINT和CMD


if [ -n "$ORIGINAL_ENTRYPOINT_CMD" ]; then
    log "Executing original entrypoint: $ORIGINAL_ENTRYPOINT_CMD"
    exec "$ORIGINAL_ENTRYPOINT_CMD"
else
    log "No original entrypoint found, exiting"
    # 如果没有原始入口点，直接退出而不是等待
    exit 0
fi
