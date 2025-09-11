#!/bin/sh

# 本脚本初次运行时，可能需要访问互联网
# 本脚本支持基于 debian/ubuntu/centos/rocky/alma 和 alpine 打包的镜像

# 使用方式: 
# 1、从 dockerfile 或 docker inspect 找到 镜像原始的 ENTRYPOINT 和 CMD
# 2、下载 redirect_pkg_handler-XXXXXXXX （从github下载后，无需修改该其文件名） 和 redirect_pkg_handler.sh 到 landscape Router 所在主机中，赋予可执行权限
# 3、在 docker run、docker-compose.yml 或 Dockerfile 中将本脚本设置为 ENTRYPOINT，并将原始镜像的 ENTRYPOINT和 CMD 作为参数传递
# 4、将 redirect_pkg_handler-XXXXXXXX （从github下载后，无需修改该其文件名） 和 redirect_pkg_handler.sh 挂载到 容器 /land 目录下

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
# 1、检查 容器系统 是否属于 debian/ubuntu/centos/rocky/alma/debian/alpine ，在此范围之外的系统暂不支持
# 2、对于 debian/ubuntu/centos/rocky/alma，配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD
# 3、对于 alpine，具有 libelf 和 libgcc支持的，则配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD
# 4、对于 alpine，没有 libelf 和 libgcc 支持
# 4.1 通过 本机 IP 归属地查询，确定 alpine 源的可用性
# 4.2 对于 alpine 源不可用的 国家/地区，如中国，进行换源操作（从 中科大/清华/阿里/网易 中随机选一个 能成功 apk update 的源）
# 4.3 安装 libelf 和 libgcc，配置防火墙，并运行 redirect_pkg_handler ，最后执行原始镜像的 ENTRYPOINT 和 CMD

# ==================== 全局变量定义 ====================

# 保存原始的ENTRYPOINT和CMD
ORIGINAL_ENTRYPOINT_CMD="$@"

# 获取CPU架构
ARCH=$(uname -m)

# 定义可用的镜像源列表
MIRRORS="mirrors.ustc.edu.cn mirrors.aliyun.com mirrors.163.com mirrors.tuna.tsinghua.edu.cn"

# ==================== 函数定义 ====================

# 日志函数，确保日志格式符合Docker规范，不依赖echo命令
log() {
    printf "%s %s %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "[redirect_pkg_handler_wrapper_script]" "$1"
}

# 简单系统处理函数（适用于debian/ubuntu/centos/rocky/alma）
simple_system_handler() {
    log "Detected Debian/Ubuntu/CentOS/Rocky Linux/AlmaLinux system"
    
    # 添加路由规则
    ip rule add fwmark 0x1/0x1 lookup 100
    ip route add local default dev lo table 100
    
    # 根据架构运行对应程序
    case "$ARCH" in
        x86_64)
            log "Starting x86_64 handler in background"
            /land/redirect_pkg_handler-x86_64 &
            ;;
        aarch64)
            log "Starting aarch64 handler in background"
            /land/redirect_pkg_handler-aarch64 &
            ;;
        *)
            log "Unsupported architecture: $ARCH"
            ;;
    esac
}

# Alpine系统处理函数
alpine_system_handler() {
    # Alpine处理（复杂处理方式）
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
        
        check_ip_sb() {
            if command -v wget >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(wget -qO- --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" --timeout=1 https://ip.sb/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 && return
                done
            elif command -v curl >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(curl -s --connect-timeout 1 --max-time 1 -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" https://ip.sb/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 && return
                done
            fi
        }
        
        check_ipwhois() {
            if command -v wget >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(wget -qO- --header="User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" --timeout=1 http://ipwho.is/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 && return
                done
            elif command -v curl >/dev/null 2>&1; then
                for i in 1 2 3 4; do
                    RESULT=$(curl -s --connect-timeout 1 --max-time 1 -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36" http://ipwho.is/ 2>/dev/null) || continue
                    printf "%s" "$RESULT" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 && return
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
        
        # 并行执行多个API查询，任何一个返回中国大陆就执行换源
        TEMP_FILE="/tmp/ip_country_check.$$"
        rm -f "$TEMP_FILE"
        
        # 后台执行多个检查，按指定顺序
        check_myip_ipip > "$TEMP_FILE.ipip" &
        IPIP_PID=$!
        
        check_ip_api > "$TEMP_FILE.api" &
        API_PID=$!
        
        check_ip_sb > "$TEMP_FILE.sb" &
        SB_PID=$!
        
        check_ipwhois > "$TEMP_FILE.whois" &
        WHOIS_PID=$!
        
        check_ipinfo > "$TEMP_FILE.info" &
        INFO_PID=$!
        
        # 存储所有后台进程PID
        ALL_PIDS="$IPIP_PID $API_PID $SB_PID $WHOIS_PID $INFO_PID"
        
        # 每间隔100ms检查一次结果，最多检查40次（总共4秒）
        count=0
        detected_country=""
        while [ $count -lt 40 ]; do
            # 检查各个API的返回结果，按指定顺序
            if [ -f "$TEMP_FILE.ipip" ]; then
                RESULT=$(cat "$TEMP_FILE.ipip" | tr -d '\n')
                if [ "$RESULT" = "中国" ]; then
                    detected_country="CN"
                    log "Detected China IP via myip.ipip.net"
                    break
                fi
            fi
            
            if [ -z "$detected_country" ] && [ -f "$TEMP_FILE.api" ]; then
                RESULT=$(cat "$TEMP_FILE.api" | tr -d '\n')
                if [ "$RESULT" = "CN" ] || [ "$RESULT" = "China" ] || [ "$RESULT" = "中国" ]; then
                    detected_country="CN"
                    log "Detected China IP via ip-api.com"
                    break
                fi
            fi
            
            if [ -z "$detected_country" ] && [ -f "$TEMP_FILE.sb" ]; then
                RESULT=$(cat "$TEMP_FILE.sb" | tr -d '\n')
                if [ "$RESULT" = "CN" ] || [ "$RESULT" = "China" ] || [ "$RESULT" = "中国" ]; then
                    detected_country="CN"
                    log "Detected China IP via ip.sb"
                    break
                fi
            fi
            
            if [ -z "$detected_country" ] && [ -f "$TEMP_FILE.whois" ]; then
                RESULT=$(cat "$TEMP_FILE.whois" | tr -d '\n')
                if [ "$RESULT" = "CN" ] || [ "$RESULT" = "China" ] || [ "$RESULT" = "中国" ]; then
                    detected_country="CN"
                    log "Detected China IP via ipwho.is"
                    break
                fi
            fi
            
            if [ -z "$detected_country" ] && [ -f "$TEMP_FILE.info" ]; then
                RESULT=$(cat "$TEMP_FILE.info" | tr -d '\n')
                if [ "$RESULT" = "CN" ] || [ "$RESULT" = "China" ] || [ "$RESULT" = "中国" ]; then
                    detected_country="CN"
                    log "Detected China IP via ipinfo.io"
                    break
                fi
            fi
            
            # 如果还没有结果，等待100ms继续检查
            count=$((count + 1))
            usleep 100000 2>/dev/null || sleep 0.1
        done
        
        # 终止所有仍在运行的后台进程
        for pid in $ALL_PIDS; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
            fi
        done
        
        # 清理临时文件
        rm -f "$TEMP_FILE"*
        
        # 设置最终的PUBLIC_IP_COUNTRY变量
        if [ "$detected_country" = "CN" ]; then
            PUBLIC_IP_COUNTRY="CN"
        fi
        
        log "Public IP country: $PUBLIC_IP_COUNTRY"
        
        # 只有当明确检测到中国大陆IP时才执行换源
        if [ "$PUBLIC_IP_COUNTRY" = "CN" ] || [ "$PUBLIC_IP_COUNTRY" = "China" ] || [ "$PUBLIC_IP_COUNTRY" = "中国" ]; then
            log "Changing to mirror"
            # 备份原始源
            cp /etc/apk/repositories /etc/apk/repositories.bak
            
            # 创建镜像源列表副本用于尝试
            AVAILABLE_MIRRORS="$MIRRORS"
            SELECTED_MIRROR=""
            UPDATE_SUCCESS=false
            
            # 尝试不同的镜像源直到成功或没有更多源可尝试
            while [ "$UPDATE_SUCCESS" = "false" ] && [ -n "$AVAILABLE_MIRRORS" ]; do
                # 随机选择一个镜像源
                MIRROR_COUNT=$(echo $AVAILABLE_MIRRORS | wc -w)
                RANDOM_INDEX=$(awk -v min=1 -v max=$MIRROR_COUNT 'BEGIN{srand(); print int(min+rand()*(max-min+1))}')
                SELECTED_MIRROR=$(echo $AVAILABLE_MIRRORS | cut -d' ' -f$RANDOM_INDEX)
                
                log "Trying mirror: $SELECTED_MIRROR"
                # 使用sed命令替换默认源为选中的镜像源
                sed -i "s/dl-cdn.alpinelinux.org/$SELECTED_MIRROR/g" /etc/apk/repositories
                
                # 尝试更新包列表
                if apk update >/dev/null 2>&1; then
                    UPDATE_SUCCESS=true
                    log "Successfully updated with mirror: $SELECTED_MIRROR"
                else
                    log "Failed to update with mirror: $SELECTED_MIRROR"
                    # 从可用镜像源列表中移除失败的源
                    AVAILABLE_MIRRORS=$(echo $AVAILABLE_MIRRORS | sed "s/$SELECTED_MIRROR//g" | tr -s ' ' | sed 's/^ *//;s/ *$//')
                    # 恢复原始源配置以便重试
                    cp /etc/apk/repositories.bak /etc/apk/repositories
                fi
            done
            
            # 如果所有镜像源都尝试失败，记录错误并恢复原始配置
            if [ "$UPDATE_SUCCESS" = "false" ]; then
                log "Failed to update with all mirrors, restoring original configuration"
                cp /etc/apk/repositories.bak /etc/apk/repositories
                # 恢复原始源后需要更新包索引
                apk update >/dev/null 2>&1
            fi
        else
            log "Not in China or failed to detect IP location, proceeding with default repositories"
            # 即使没有换源，也尝试更新一次以确保包管理器正常工作
            apk update >/dev/null 2>&1
        fi
        
        # 安装libelf和libgcc
        # 注意：这里不再需要执行apk update，因为在上面的换源逻辑中已经执行过了
        apk add --no-cache libelf libgcc
        
        # 清除apk缓存数据
        rm -rf /var/cache/apk/*
        
        # 添加路由规则
        ip rule add fwmark 0x1/0x1 lookup 100
        ip route add local default dev lo table 100
        
        # 根据架构运行对应程序
        case "$ARCH" in
            x86_64)
                log "Starting x86_64 musl handler in background"
                /land/redirect_pkg_handler-x86_64-musl &
                ;;
            aarch64)
                log "Starting aarch64 musl handler in background"
                /land/redirect_pkg_handler-aarch64-musl &
                ;;
            *)
                log "Unsupported architecture: $ARCH"
                ;;
        esac
    else
        # 库已安装，直接添加路由规则并运行程序
        log "Required libraries already installed"
        
        # 添加路由规则
        ip rule add fwmark 0x1/0x1 lookup 100
        ip route add local default dev lo table 100
        
        # 根据架构运行对应程序
        case "$ARCH" in
            x86_64)
                log "Starting x86_64 musl handler in background"
                /land/redirect_pkg_handler-x86_64-musl &
                ;;
            aarch64)
                log "Starting aarch64 musl handler in background"
                /land/redirect_pkg_handler-aarch64-musl &
                ;;
            *)
                log "Unsupported architecture: $ARCH"
                ;;
        esac
    fi
}

# ==================== 主要逻辑 ====================

# 检查容器是debian/ubuntu/centos/rocky/alma还是alpine
if [ -f /etc/debian_version ] || grep -qi ubuntu /etc/os-release 2>/dev/null || [ -f /etc/redhat-release ] || grep -qi "centos\|rocky\|alma" /etc/os-release 2>/dev/null; then
    # Debian/Ubuntu/CentOS/Rocky Linux/AlmaLinux处理（简单处理方式）
    simple_system_handler
    
elif grep -qi alpine /etc/os-release 2>/dev/null; then
    # Alpine处理（复杂处理方式）
    alpine_system_handler
else
    # 不支持的操作系统，报错并退出
    log "Unsupported OS distribution"
    exit 1
fi

# 等待 handler 启动完成
sleep 0.2

# 执行原始的ENTRYPOINT和CMD
# 使用方式: 在docker-compose.yml或Dockerfile中将本脚本设置为ENTRYPOINT，并将原始镜像的ENTRYPOINT和CMD作为参数传递
# 例如: ENTRYPOINT ["/app/redirect_pkg_handler", "/original/entrypoint", "original", "cmd", "args"]
if [ -n "$ORIGINAL_ENTRYPOINT_CMD" ]; then
    log "Executing original entrypoint: $ORIGINAL_ENTRYPOINT_CMD"
    exec "$ORIGINAL_ENTRYPOINT_CMD"
else
    log "No original entrypoint found, exiting"
    # 如果没有原始入口点，直接退出而不是等待
    exit 0
fi
