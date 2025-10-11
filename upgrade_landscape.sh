#!/bin/bash

# Landscape Router 升级脚本 (优化版)

# 用法: ./upgrade_landscape_optimized.sh [--stable|--beta] [--cn] [--reboot] [--backup[=N]] [--rollback]
# 参数:
#   --stable       - 升级到最新稳定版（默认）
#   --beta         - 升级到最新 Beta 版
#   --cn           - 使用中国镜像加速（仅限 stable 版本，beta 版本不支持）
#   --reboot       - 升级完成后自动重启（可选）
#   --backup       - 升级前进行备份
#   --stopdocker   - 替换 handler 时，停止 Docker 服务（可能缩短升级时间）
#   --backup=N     - 升级前进行备份，并指定保留N个备份（默认stable保留1个，beta保留3个）
#   --rollback     - 回滚到之前的备份版本（交互式）
#   -h, --help     - 显示此帮助信息

# 示例:
#   ./upgrade_landscape_optimized.sh                    # 升级到最新稳定版
#   ./upgrade_landscape_optimized.sh --stable           # 升级到最新稳定版
#   ./upgrade_landscape_optimized.sh --beta             # 升级到最新 Beta 版
#   ./upgrade_landscape_optimized.sh --stable --cn      # 使用中国镜像升级到最新稳定版
#   ./upgrade_landscape_optimized.sh --stable --reboot  # 升级到最新稳定版并自动重启
#   ./upgrade_landscape_optimized.sh --backup           # 升级前进行备份
#   ./upgrade_landscape_optimized.sh --backup=5         # 升级前进行备份，保留最近5个备份
#   ./upgrade_landscape_optimized.sh --rollback         # 回滚到之前的备份版本
#   ./upgrade_landscape_optimized.sh -h                 # 显示帮助信息
#
# 注意:
#   - Beta 版本从 GitHub Actions 下载，不支持 --cn 镜像加速参数
#   - Stable 版本从 GitHub Releases 下载，支持 --cn 镜像加速参数

# ========== 配置常量 ==========
# readonly SCRIPT_NAME="$(basename "$0")"
# readonly SCRIPT_VERSION="2.0-optimized"
readonly DEFAULT_MAX_LOGS=16
readonly DEFAULT_STABLE_BACKUPS=1
readonly DEFAULT_BETA_BACKUPS=3
readonly MAX_API_RETRIES=3
readonly MAX_DOWNLOAD_RETRIES=3
readonly MAX_FILE_REPLACE_RETRIES=5
readonly API_BASE_URL="https://api.github.com/repos/ThisSeanZhang/landscape"
readonly CN_MIRROR_BASE_URL="https://ghfast.top/https://github.com/ThisSeanZhang/landscape"
readonly REDIRECT_PKG_HANDLER_BASE_URL="https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main"

# ========== 全局变量 ==========
USE_CN_MIRROR=false
SHOW_HELP=false
AUTO_REBOOT=false
ACTION="stable"  # 默认动作
SYSTEM_ARCH=""
INIT_SYSTEM=""
USE_MUSL=false
CREATE_BACKUP=false
BACKUP_COUNT=0  # 0 表示使用默认值
ROLLBACK=false
UPGRADE_LOG=""  # 升级日志文件路径
LANDSCAPE_DIR=""  # Landscape安装目录全局变量
CURRENT_VERSION=""  # 当前版本号全局变量
GITHUB_TOKEN=""  # GitHub Token全局变量
DOCKER_STOPPED_BY_SCRIPT=false  # 跟踪脚本是否停止了Docker服务，也用于标记 Docker 的状态
STOP_DOCKER=false

# API响应缓存变量
CACHED_WORKFLOW_DATA=""  # 缓存的工作流列表响应
CACHED_WORKFLOW_RUN_ID=""  # 缓存的工作流运行ID
CACHED_ARTIFACTS_DATA=""  # 缓存的artifacts响应

# 临时文件跟踪
declare -a TEMP_FILES_TO_CLEAN=()
declare -a TEMP_DIRS_TO_CLEAN=()

# ========== 错误处理和清理函数 ==========

# 错误处理函数
handle_error() {
    local exit_code=$?
    local line_number=$1
    local error_message="$2"
    
    log "错误发生在第 $line_number 行: $error_message (退出码: $exit_code)"
    log "正在清理临时文件和目录..."
    
    cleanup_temp_resources
    
    # 如果Docker服务被脚本停止，尝试重启它
    if [ "$DOCKER_STOPPED_BY_SCRIPT" = true ]; then
        log "尝试重启Docker服务..."
        control_docker_service "start" || log "警告: 无法重启Docker服务"
    fi
    
    exit $exit_code
}

# 注册临时文件以供清理
register_temp_file() {
    TEMP_FILES_TO_CLEAN+=("$1")
}

# 注册临时目录以供清理
register_temp_dir() {
    TEMP_DIRS_TO_CLEAN+=("$1")
}

# 清理临时资源
cleanup_temp_resources() {
    # 清理临时文件
    for file in "${TEMP_FILES_TO_CLEAN[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file" 2>/dev/null || log "警告: 无法删除临时文件 $file"
        fi
    done
    
    # 清理临时目录
    for dir in "${TEMP_DIRS_TO_CLEAN[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir" 2>/dev/null || log "警告: 无法删除临时目录 $dir"
        fi
    done
    
    # 清空数组
    TEMP_FILES_TO_CLEAN=()
    TEMP_DIRS_TO_CLEAN=()
}

# 设置错误陷阱
set_error_trap() {
    set -E
    trap 'handle_error ${LINENO} "脚本执行过程中发生错误"' ERR
    trap 'cleanup_temp_resources; exit 130' INT
    trap 'cleanup_temp_resources; exit 143' TERM
}

# ========== 主函数 ==========

main() {
    # 设置错误处理
    set_error_trap
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 如果请求帮助，则显示帮助信息并退出
    if [ "$SHOW_HELP" = true ]; then
        show_help
        exit 0
    fi
    
    # 执行系统环境检查（包括架构、初始化系统和依赖项）
    check_system_environment
    
    # 获取安装路径
    LANDSCAPE_DIR=$(get_landscape_dir) || exit 1
    
    # 获取当前版本号
    get_current_version

    # 处理回滚操作
    if [ "$ROLLBACK" = true ]; then
        handle_rollback_operation
        exit 0
    fi
    
    # 初始化日志
    init_log
    
    log "Landscape Router 升级脚本开始执行 (优化版 v$SCRIPT_VERSION)"
    log "检测到 Landscape Router 安装目录: $LANDSCAPE_DIR"
    log "当前版本: $CURRENT_VERSION"
    
    # 根据参数执行相应功能
    case "$ACTION" in
        "stable")
            upgrade_stable "$LANDSCAPE_DIR"
            ;;
        "beta")
            upgrade_beta "$LANDSCAPE_DIR"
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
    
    # 清理临时资源
    cleanup_temp_resources
}

# ========== 日志函数 ==========

# 初始化日志
init_log() {
    local timestamp
    timestamp=$(date +"%Y%m%d%H%M%S")
    
    # 使用全局变量中的 landscape_dir
    local landscape_dir="$LANDSCAPE_DIR"
    
    # 创建日志文件路径
    if [ -n "$landscape_dir" ] && mkdir -p "$landscape_dir/script_logs" 2>/dev/null; then
        # 设置日志文件路径
        if [ "$ROLLBACK" = true ]; then
            UPGRADE_LOG="$landscape_dir/script_logs/rollback-from-${CURRENT_VERSION}-${timestamp}.log"
        else
            UPGRADE_LOG="$landscape_dir/script_logs/upgrade-from-${CURRENT_VERSION}-${timestamp}.log"
        fi
        
        # 清理旧的日志文件，最多保留16个
        cleanup_old_logs "$landscape_dir/script_logs"
    else
        # 如果无法获取安装目录或创建日志目录，则使用临时目录
        if [ "$ROLLBACK" = true ]; then
            UPGRADE_LOG="/tmp/rollback-from-${CURRENT_VERSION}-$timestamp.log"
        else
            UPGRADE_LOG="/tmp/upgrade-from-${CURRENT_VERSION}-$timestamp.log"
        fi
    fi
    
    # 创建日志文件
    touch "$UPGRADE_LOG" 2>/dev/null || true
}

# 记录日志消息
log() {
    local message="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    # 输出到控制台
    echo "[$timestamp] $message"
    
    # 输出到日志文件（如果可用）
    if [ -n "$UPGRADE_LOG" ] && [ -f "$UPGRADE_LOG" ]; then
        echo "[$timestamp] $message" >> "$UPGRADE_LOG"
    fi
}

# 优化后的日志清理函数
cleanup_old_logs() {
    local log_dir="$1"
    local max_logs=${2:-$DEFAULT_MAX_LOGS}
    
    log "正在清理旧的日志文件（最多保留 $max_logs 个）..."
    log "日志目录路径: $log_dir"
    
    # 检查日志目录是否存在且非空
    if [ ! -d "$log_dir" ]; then
        log "日志目录不存在: $log_dir"
        return 0
    fi
    
    if [ ! "$(ls -A "$log_dir" 2>/dev/null)" ]; then
        log "日志目录为空，无需清理"
        return 0
    fi
    
    # 使用find命令直接按时间排序并删除旧文件
    local deleted_count=0
    local log_count=0
    
    # 计算总日志文件数
    log_count=$(find "$log_dir" -maxdepth 1 -type f | wc -l)
    
    if [ "$log_count" -gt "$max_logs" ]; then
        local to_remove=$((log_count - max_logs))
        log "找到 $log_count 个日志文件，需要删除 $to_remove 个旧日志"
        
        # 使用find命令按时间排序，删除旧文件
        while IFS= read -r -d '' file; do
            if rm -f "$file"; then
                deleted_count=$((deleted_count + 1))
                log "删除旧日志: $(basename "$file")"
            fi
        done < <(find "$log_dir" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | \
                sort -z -n | \
                cut -z -d' ' -f2- | \
                head -z -n "$to_remove" | \
                tr '\0' '\n')
        
        log "日志清理完成，已保留 $max_logs 个最新日志，删除了 $deleted_count 个旧日志"
    else
        log "日志数量未超过限制，无需清理"
    fi
}

# ========== 系统环境检查函数 ==========

# 系统环境检查（包括架构、初始化系统和依赖项）
check_system_environment() {
    # 检查系统架构
    SYSTEM_ARCH=$(uname -m)
    if [ "$SYSTEM_ARCH" != "x86_64" ] && [ "$SYSTEM_ARCH" != "aarch64" ]; then
        echo "不支持的系统架构: $SYSTEM_ARCH" >&2
        exit 1
    fi
    
    # 检查是否使用 musl libc
    if ldd --version 2>&1 | grep -q musl; then
        USE_MUSL=true
    fi
    
    # 检查系统使用的初始化系统
    if command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        INIT_SYSTEM="openrc"
    else
        printf "错误: 不支持的初始化系统，需要 systemd 或 OpenRC\n" >&2
        exit 1
    fi
    
    # 检查依赖项
    check_dependencies
}

# 检查依赖项
check_dependencies() {
    local missing_deps=()
    
    # 检查 unzip
    if ! command -v unzip >/dev/null 2>&1; then
        missing_deps+=("unzip")
    fi
    
    # 检查 wget 或 curl
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("wget 或 curl")
    fi
    
    # 检查服务管理工具
    if [ "$INIT_SYSTEM" = "systemd" ]; then
        if ! command -v systemctl >/dev/null 2>&1; then
            missing_deps+=("systemctl")
        fi
    elif [ "$INIT_SYSTEM" = "openrc" ]; then
        if ! command -v rc-service >/dev/null 2>&1; then
            missing_deps+=("rc-service")
        fi
        if ! command -v openrc >/dev/null 2>&1; then
            missing_deps+=("openrc")
        fi
    fi
    
    # 如果有缺失的依赖，报告并退出
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "错误: 缺少以下依赖项:" >&2
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep" >&2
        done
        echo "请安装缺少的依赖项后再运行此脚本。" >&2
        exit 1
    fi
}

# ========== 参数解析和帮助函数 ==========

# 解析命令行参数
parse_arguments() {
    ACTION="stable"  # 默认动作
    local i=0
    local args=($@)
    while [ $i -lt $# ]; do
        arg="${args[$i]}"
        case "$arg" in
            "--stable"|"--beta")
                local version_action="${arg#--}"
                ACTION="$version_action"
                echo "设置动作: $ACTION" >&2
                ;;
            "--cn")
                # 检查是否为beta版本，如果是则禁止使用中国镜像加速
                if [ "$ACTION" = "beta" ]; then
                    echo "错误: Beta 版本不支持 --cn 参数（GitHub 镜像加速）" >&2
                    echo "Beta 版本从 GitHub Actions 下载，不需要也不支持镜像加速" >&2
                    exit 1
                fi
                USE_CN_MIRROR=true
                echo "启用中国镜像加速" >&2
                ;;
            "--reboot")
                AUTO_REBOOT=true
                echo "启用自动重启" >&2
                ;;
            "--stopdocker")
                STOP_DOCKER=true
                echo "替换 handler 时，停止 Docker 服务" >&2
                ;;
            "--backup")
                CREATE_BACKUP=true
                echo "启用备份功能" >&2
                ;;
            --backup=*)
                local count="${arg#--backup=}"
                CREATE_BACKUP=true
                BACKUP_COUNT="$count"
                
                # 验证 BACKUP_COUNT 是数字
                if ! [[ "$BACKUP_COUNT" =~ ^[0-9]+$ ]] || [ "$BACKUP_COUNT" -lt 1 ]; then
                    echo "错误: --backup 参数必须是正整数" >&2
                    exit 1
                fi
                echo "启用备份功能，保留 $BACKUP_COUNT 个备份" >&2
                ;;
            "--rollback")
                ROLLBACK=true
                echo "启用回滚功能" >&2
                ;;
            "-h"|"--help")
                SHOW_HELP=true
                ;;
            *)
                echo "忽略未知参数: $arg" >&2
                ;;
        esac
        i=$((i+1))
    done
}

# 显示帮助信息
show_help() {
    echo "Landscape Router 升级脚本 (优化版 v$SCRIPT_VERSION)"
    echo "用法: ./$SCRIPT_NAME [--stable|--beta] [--cn] [--reboot] [--backup[=N]] [--rollback]"
    echo "参数:"
    echo "  --stable       - 升级到最新稳定版（默认）"
    echo "  --beta         - 升级到最新 Beta 版"
    echo "  --cn           - 使用中国镜像加速（仅限 stable 版本，beta 版本不支持）"
    echo "  --reboot       - 升级完成后自动重启（可选）"
    echo "  --stopdocker   - 替换 handler 时，停止 Docker 服务（可能缩短升级时间）"
    echo "  --backup       - 升级前进行备份"
    echo "  --backup=N     - 升级前进行备份，并指定保留N个备份（默认stable保留1个，beta保留3个）"
    echo "  --rollback     - 回滚到之前的备份版本（交互式）"
    echo "  -h, --help     - 显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  ./$SCRIPT_NAME                    # 升级到最新稳定版"
    echo "  ./$SCRIPT_NAME --stable           # 升级到最新稳定版"
    echo "  ./$SCRIPT_NAME --beta             # 升级到最新 Beta 版"
    echo "  ./$SCRIPT_NAME --stable --cn      # 使用中国镜像升级到最新稳定版"
    echo "  ./$SCRIPT_NAME --stable --reboot  # 升级到最新稳定版并自动重启"
    echo "  ./$SCRIPT_NAME --backup           # 升级前进行备份"
    echo "  ./$SCRIPT_NAME --backup=5         # 升级前进行备份，保留最近5个备份"
    echo "  ./$SCRIPT_NAME --rollback         # 回滚到之前的备份版本"
    echo "  ./$SCRIPT_NAME -h                 # 显示帮助信息"
    echo ""
    echo "注意:"
    echo "  - Beta 版本从 GitHub Actions 下载，不支持 --cn 镜像加速参数"
    echo "  - Stable 版本从 GitHub Releases 下载，支持 --cn 镜像加速参数"
    echo ""
    echo "当前系统初始化系统: $INIT_SYSTEM"
    echo "当前系统架构: $SYSTEM_ARCH"
    if [ "$USE_MUSL" = true ]; then
        echo "系统类型: musl"
    else
        echo "系统类型: glibc"
    fi
}

# ========== 路径和版本获取函数 ==========

# 获取 Landscape Router 安装路径
get_landscape_dir() {
    if [ "$INIT_SYSTEM" = "systemd" ] && [ -f "/etc/systemd/system/landscape-router.service" ]; then
        # 从systemd服务文件获取安装路径
        local landscape_dir
        landscape_dir=$(grep -oP 'ExecStart=\K.*(?=/landscape-webserver-)' /etc/systemd/system/landscape-router.service 2>/dev/null) || true
        if [ -z "$landscape_dir" ]; then
            echo "错误: 无法从 landscape-router.service 中提取安装路径，升级终止" >&2
            return 1
        fi
        echo "$landscape_dir"
    elif [ "$INIT_SYSTEM" = "openrc" ] && [ -f "/etc/init.d/landscape-router" ]; then
        # 从OpenRC启动脚本获取安装路径
        local landscape_dir
        landscape_dir=$(grep -oP 'command=\K.*(?=/landscape-webserver-)' /etc/init.d/landscape-router 2>/dev/null) || true
        if [ -z "$landscape_dir" ]; then
            echo "错误: 无法从 landscape-router 启动脚本中提取安装路径，升级终止" >&2
            return 1
        fi
        echo "$landscape_dir"
    else
        # 处理缺失的服务文件
        if [ "$INIT_SYSTEM" = "systemd" ]; then
            echo "错误: 未找到 landscape-router.service 文件" >&2
        else
            echo "错误: 未找到 landscape-router 启动脚本" >&2
        fi
        return 1
    fi
}

# 获取当前版本号
get_current_version() {
    local current_filename="landscape-webserver-$SYSTEM_ARCH"
    if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
        current_filename="landscape-webserver-x86_64-musl"
    fi
    
    if [ -f "$LANDSCAPE_DIR/$current_filename" ]; then
        CURRENT_VERSION=$("$LANDSCAPE_DIR/$current_filename" --version 2>/dev/null)
    fi
    
    # 如果无法获取版本号，则使用 unknown
    if [ -z "$CURRENT_VERSION" ]; then
        CURRENT_VERSION="unknown"
    fi
}

# ========== 服务控制函数 ==========

# 控制Landscape服务的函数
control_landscape_service() {
    local action="$1"
    case "$action" in
        "start")
            log "正在启动 Landscape Router 服务..."
            # 如果脚本之前停止了Docker服务，则在启动Landscape服务时也启动Docker服务
            if [ "$DOCKER_STOPPED_BY_SCRIPT" = true ]; then
                log "检测到脚本之前停止了Docker服务，正在同时启动Docker服务..."
                control_docker_service "start"
            fi
            
            if [ "$INIT_SYSTEM" = "systemd" ]; then
                systemctl start landscape-router
            else
                rc-service landscape-router start
            fi
            ;;
        "stop")
            log "正在停止 Landscape Router 服务..."
            if [ "$INIT_SYSTEM" = "systemd" ]; then
                systemctl stop landscape-router
            else
                rc-service landscape-router stop
            fi
            ;;
        "restart")
            log "正在重启 Landscape Router 服务..."
            # 如果脚本之前停止了Docker服务，则在重启Landscape服务时也启动Docker服务
            if [ "$DOCKER_STOPPED_BY_SCRIPT" = true ]; then
                log "检测到脚本之前停止了Docker服务，正在同时启动Docker服务..."
                control_docker_service "start"
            fi
            
            if [ "$INIT_SYSTEM" = "systemd" ]; then
                systemctl restart landscape-router
            else
                rc-service landscape-router restart
            fi
            ;;
        *)
            log "未知的服务操作: $action"
            return 1
            ;;
    esac
}

# 优化后的Docker服务控制函数，修复竞态条件
control_docker_service() {
    local action="$1"
    local max_wait_time=30  # 最大等待时间（秒）
    local wait_interval=2   # 检查间隔（秒）
    
    case "$action" in
        "start")
            log "正在启动 Docker 服务..."
            if [ "$INIT_SYSTEM" = "systemd" ]; then
                systemctl start docker
            else
                rc-service docker start
            fi
            
            # 等待Docker服务完全启动
            local wait_time=0
            while [ $wait_time -lt $max_wait_time ]; do
                if [ "$INIT_SYSTEM" = "systemd" ]; then
                    if systemctl is-active --quiet docker 2>/dev/null; then
                        break
                    fi
                else
                    if rc-service docker status 2>/dev/null | grep -q "started"; then
                        break
                    fi
                fi
                
                sleep $wait_interval
                wait_time=$((wait_time + wait_interval))
                log "等待 Docker 服务启动... (${wait_time}/${max_wait_time}秒)"
            done
            
            if [ $wait_time -ge $max_wait_time ]; then
                log "警告: Docker 服务启动超时，但继续执行"
            else
                log "Docker 服务已启动"
            fi
            
            # 取消 Docker 标记，表示 Docker 已启动
            DOCKER_STOPPED_BY_SCRIPT=false
            ;;
        "stop")
            log "正在停止 Docker 服务..."
            
            # 检查Docker服务是否正在运行
            local docker_running=false
            if [ "$INIT_SYSTEM" = "systemd" ]; then
                if systemctl is-active --quiet docker 2>/dev/null; then
                    docker_running=true
                fi
            else
                if rc-service docker status 2>/dev/null | grep -q "started"; then
                    docker_running=true
                fi
            fi
            
            if [ "$docker_running" = false ]; then
                log "Docker 服务未运行，无需停止"
                return 0
            fi
            
            # 停止Docker服务
            if [ "$INIT_SYSTEM" = "systemd" ]; then
                systemctl stop docker
            else
                rc-service docker stop
            fi
            
            # 等待Docker服务完全停止
            local wait_time=0
            while [ $wait_time -lt $max_wait_time ]; do
                if [ "$INIT_SYSTEM" = "systemd" ]; then
                    if ! systemctl is-active --quiet docker 2>/dev/null; then
                        break
                    fi
                else
                    if ! rc-service docker status 2>/dev/null | grep -q "started"; then
                        break
                    fi
                fi
                
                sleep $wait_interval
                wait_time=$((wait_time + wait_interval))
                log "等待 Docker 服务停止... (${wait_time}/${max_wait_time}秒)"
            done
            
            if [ $wait_time -ge $max_wait_time ]; then
                log "警告: Docker 服务停止超时，但继续执行"
            else
                log "Docker 服务已停止"
            fi
            
            # 记录脚本停止了Docker服务
            DOCKER_STOPPED_BY_SCRIPT=true
            ;;
        "restart")
            log "正在重启 Docker 服务..."
            control_docker_service "stop"
            sleep 2
            control_docker_service "start"
            ;;
        *)
            log "未知的 Docker 服务操作: $action"
            return 1
            ;;
    esac
}

# ========== 下载和URL处理函数 ==========

# 获取下载URL和文件名
get_download_info() {
    local version_type="$1"
    local filename="landscape-webserver-$SYSTEM_ARCH"
    if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
        filename="landscape-webserver-x86_64-musl"
    fi
    
    local download_url=""
    
    # 根据是否使用中国镜像设置下载URL
    case "$version_type" in
        "stable")
            if [ "$USE_CN_MIRROR" = true ]; then
                download_url="${CN_MIRROR_BASE_URL}/releases/latest/download/$filename"
            else
                download_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/$filename"
            fi
            ;;
        "beta")
            # Beta版本从GitHub Actions下载
            download_url="github_actions"
            ;;
    esac
    
    echo "$download_url|$filename"
}

# 获取static.zip下载URL
get_static_download_url() {
    local version_type="$1"
    
    local download_url=""
    
    # 根据是否使用中国镜像设置下载URL
    case "$version_type" in
        "stable")
            if [ "$USE_CN_MIRROR" = true ]; then
                download_url="${CN_MIRROR_BASE_URL}/releases/latest/download/static.zip"
            else
                download_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
            fi
            ;;
        "beta")
            # Beta版本从GitHub Actions下载
            download_url="github_actions"
            ;;
    esac
    
    echo "$download_url"
}

# 获取redirect_pkg_handler相关文件下载URL
get_redirect_pkg_handler_url() {
    local version_type="$1"
    local file_type="$2"  # script 或 binary
    local binary_name="$3"  # 二进制文件名，仅在 file_type 为 binary 时使用
    
    local download_url=""
    
    if [ "$file_type" = "script" ]; then
        # redirect_pkg_handler.sh从相同地址下载，支持中国镜像加速，不需要GitHub token
        if [ "$USE_CN_MIRROR" = true ]; then
            download_url="${CN_MIRROR_BASE_URL}/${REDIRECT_PKG_HANDLER_BASE_URL}/redirect_pkg_handler.sh"
        else
            download_url="${REDIRECT_PKG_HANDLER_BASE_URL}/redirect_pkg_handler.sh"
        fi
    elif [ "$file_type" = "binary" ]; then
        # 根据版本类型和是否使用中国镜像设置下载URL
        case "$version_type" in
            "stable")
                if [ "$USE_CN_MIRROR" = true ]; then
                    download_url="${CN_MIRROR_BASE_URL}/releases/latest/download/$binary_name"
                else
                    download_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/$binary_name"
                fi
                ;;
            "beta")
                # Beta版本从GitHub Actions下载
                download_url="github_actions"
                ;;
        esac
    fi
    
    echo "$download_url"
}

# 优化后的通用下载函数，支持wget和curl，优先使用wget，并支持重试3次
download_with_retry() {
    local url="$1"
    local output_file="$2"
    local use_token="$3"  # 可选参数，指示是否使用GitHub Token
    local max_retries=${4:-$MAX_DOWNLOAD_RETRIES}
    local retry_count=0
    local download_tool=""
    
    log "开始下载函数 download_with_retry"
    log "参数: url=[$url]"
    log "参数: output_file=[$output_file]"
    log "参数: use_token=[$use_token]"
    
    # 检查是否有wget或curl
    if command -v wget >/dev/null 2>&1; then
        download_tool="wget"
    elif command -v curl >/dev/null 2>&1; then
        download_tool="curl"
    else
        log "错误: 系统中未找到 wget 或 curl 命令，请安装其中一个再继续"
        return 1
    fi
    
    log "使用下载工具: $download_tool"
    
    # 处理GitHub Actions下载
    if [ "$url" = "github_actions" ]; then
        log "检测到 GitHub Actions 下载，调用 download_from_github_actions"
        download_from_github_actions "$output_file"
        return $?
    fi
    
    # 准备认证头
    local auth_header=""
    if [ "$use_token" = "true" ] && [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: Bearer $GITHUB_TOKEN"
        log "使用 GitHub Token 加速下载"
    fi
    
    # 执行下载重试循环
    while [ $retry_count -lt $max_retries ]; do
        log "尝试下载，第 $((retry_count + 1)) 次尝试 (URL: $url)"
        
        case "$download_tool" in
            "wget")
                if [ -n "$auth_header" ]; then
                    log "使用 wget 带认证头下载"
                    if wget -O "$output_file" --header="$auth_header" "$url"; then
                        log "wget 下载成功"
                        return 0
                    else
                        log "wget 下载失败，退出码: $?"
                    fi
                else
                    log "使用 wget 下载"
                    if wget -O "$output_file" "$url"; then
                        log "wget 下载成功"
                        return 0
                    else
                        log "wget 下载失败，退出码: $?"
                    fi
                fi
                ;;
            "curl")
                if [ -n "$auth_header" ]; then
                    log "使用 curl 带认证头下载"
                    if curl -L -H "$auth_header" -o "$output_file" "$url"; then
                        log "curl 下载成功"
                        return 0
                    else
                        log "curl 下载失败，退出码: $?"
                    fi
                else
                    log "使用 curl 下载"
                    if curl -L -o "$output_file" "$url"; then
                        log "curl 下载成功"
                        return 0
                    else
                        log "curl 下载失败，退出码: $?"
                    fi
                fi
                ;;
        esac
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            local wait_time=$((retry_count * 2))
            log "下载失败，等待 ${wait_time}s 后重试..."
            sleep $wait_time
        fi
    done
    
    log "下载失败，已重试 $max_retries 次"
    return 1
}

# 优化后的API请求函数，减少重复代码
make_api_request() {
    local url="$1"
    local auth_header="$2"
    local max_retries=${3:-$MAX_API_RETRIES}
    local retry_count=0
    local response=""
    local api_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$api_success" = false ]; do
        log "尝试获取API数据，第 $((retry_count + 1)) 次尝试"
        
        if command -v curl >/dev/null 2>&1; then
            if [ -n "$auth_header" ]; then
                response=$(curl -s -H "Accept: application/vnd.github.v3+json" -H "$auth_header" "$url")
            else
                response=$(curl -s -H "Accept: application/vnd.github.v3+json" "$url")
            fi
        elif command -v wget >/dev/null 2>&1; then
            if [ -n "$auth_header" ]; then
                response=$(wget -qO- --header="Accept: application/vnd.github.v3+json" --header="$auth_header" "$url")
            else
                response=$(wget -qO- --header="Accept: application/vnd.github.v3+json" "$url")
            fi
        else
            log "错误: 系统中未找到 curl 或 wget 命令"
            return 1
        fi
        
        # 检查API响应是否有效
        if [ -n "$response" ]; then
            api_success=true
            log "API请求成功"
        else
            log "API请求失败或响应为空"
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                local wait_time=$((retry_count * 2))
                log "等待 ${wait_time}s 后重试..."
                sleep $wait_time
            fi
        fi
    done
    
    if [ "$api_success" = false ]; then
        log "错误: API请求失败，已重试 $max_retries 次"
        return 1
    fi
    
    echo "$response"
    return 0
}

# 重构后的GitHub Actions下载函数，拆分为多个小函数
# 从GitHub Actions下载Beta版本文件
download_from_github_actions() {
    local output_file="$1"
    local file_name=$(basename "$output_file")
    
    # 读取GitHub Token
    if [ -f "$LANDSCAPE_DIR/github_token" ]; then
        GITHUB_TOKEN=$(cat "$LANDSCAPE_DIR/github_token")
        log "已读取GitHub Token"
    else
        log "警告: 未找到GitHub Token文件，可能无法下载Beta版本"
    fi
    
    # 处理特殊文件 redirect_pkg_handler.sh
    if [ "$file_name" = "redirect_pkg_handler.sh" ]; then
        download_redirect_pkg_handler_script "$output_file"
        return $?
    fi
    
    # 获取工作流数据
    if ! get_workflow_data; then
        return 1
    fi
    
    # 下载并处理artifact
    download_and_extract_artifact "$output_file" "$file_name"
}

# 下载redirect_pkg_handler.sh脚本
download_redirect_pkg_handler_script() {
    local output_file="$1"
    
    log "下载 redirect_pkg_handler.sh..."
    
    # 无论 stable 还是 beta 版本，脚本文件都从同一个地址下载
    # 使用 get_redirect_pkg_handler_url 函数获取下载URL
    local download_url
    download_url=$(get_redirect_pkg_handler_url "stable" "script")
    
    if [ "$USE_CN_MIRROR" = true ]; then
        log "使用中国镜像加速下载 redirect_pkg_handler.sh"
    fi
    
    log "下载URL: $download_url"
    log "输出文件: $output_file"
    
    # 使用标准下载方式，带重试机制，不使用token
    local retry_count=0
    local max_retries=$MAX_DOWNLOAD_RETRIES
    local download_success=false
    
    while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
        log "尝试下载 redirect_pkg_handler.sh，第 $((retry_count + 1)) 次尝试"
        
        if command -v wget >/dev/null 2>&1; then
            log "使用 wget 下载..."
            # 不隐藏错误信息，直接输出到终端
            if wget -O "$output_file" "$download_url"; then
                download_success=true
                log "使用 wget 下载成功"
            else
                local wget_exit_code=$?
                log "使用 wget 下载失败，退出码: $wget_exit_code"
            fi
        elif command -v curl >/dev/null 2>&1; then
            log "使用 curl 下载..."
            # 不隐藏错误信息，直接输出到终端
            if curl -L -o "$output_file" "$download_url"; then
                download_success=true
                log "使用 curl 下载成功"
            else
                local curl_exit_code=$?
                log "使用 curl 下载失败，退出码: $curl_exit_code"
            fi
        else
            log "错误: 系统中未找到 curl 或 wget 命令"
            return 1
        fi
        
        # 检查文件是否存在且非空
        if [ "$download_success" = true ]; then
            if [ -f "$output_file" ] && [ -s "$output_file" ]; then
                log "文件下载成功且非空"
            else
                log "文件不存在或为空，重新尝试"
                download_success=false
            fi
        fi
        
        if [ "$download_success" = false ]; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                local wait_time=$((retry_count * 2))
                log "下载失败，等待 ${wait_time}s 后重试..."
                sleep $wait_time
            fi
        fi
    done
    
    # 验证下载的文件是否有效
    if [ "$download_success" = true ] && [ -f "$output_file" ] && [ -s "$output_file" ]; then
        local file_size=$(ls -lh "$output_file" 2>/dev/null | awk '{print $5}' || echo '未知')
        log "redirect_pkg_handler.sh 下载成功，文件大小: $file_size"
        
        # 检查文件内容是否为有效的shell脚本
        if head -1 "$output_file" 2>/dev/null | grep -q "^#!/"; then
            log "redirect_pkg_handler.sh 文件格式验证成功"
            return 0
        else
            log "redirect_pkg_handler.sh 文件格式验证失败，不是有效的shell脚本"
            log "文件前几行内容:"
            head -5 "$output_file" 2>/dev/null | while read line; do log "  $line"; done
            rm -f "$output_file" 2>/dev/null
            return 1
        fi
    else
        log "redirect_pkg_handler.sh 下载失败或文件无效"
        log "文件检查结果:"
        log "  文件是否存在: $([ -f "$output_file" ] && echo '是' || echo '否')"
        log "  文件是否非空: $([ -s "$output_file" ] && echo '是' || echo '否')"
        if [ -f "$output_file" ]; then
            log "  文件大小: $(ls -l "$output_file" | awk '{print $5}') 字节"
        fi
        # 清理可能存在的空文件
        rm -f "$output_file" 2>/dev/null
        return 1
    fi
}

# 获取工作流数据
get_workflow_data() {
    # 检查是否有缓存的工作流数据，如果没有则获取
    if [ -z "$CACHED_WORKFLOW_DATA" ] || [ -z "$CACHED_WORKFLOW_RUN_ID" ]; then
        log "获取GitHub Actions工作流信息..."
        
        local api_url="${API_BASE_URL}/actions/runs?status=success&per_page=5"
        local auth_header=""
        
        if [ -n "$GITHUB_TOKEN" ]; then
            auth_header="Authorization: Bearer $GITHUB_TOKEN"
        fi
        
        # 使用GitHub API获取最新的工作流运行，带重试机制
        local response
        if ! response=$(make_api_request "$api_url" "$auth_header"); then
            return 1
        fi
        
        # 解析工作流运行ID
        local temp_ids=$(echo "$response" | grep -A 1000 '"workflow_runs":' | grep '"id":' | head -10 | grep -o '[0-9]\{10,\}')
        
        if [ -z "$temp_ids" ]; then
            log "错误: API响应中未找到任何工作流运行ID"
            return 1
        fi
        
        # 缓存工作流数据
        CACHED_WORKFLOW_DATA="$response"
        
        # 找到包含artifacts的工作流运行
        local target_artifacts_response=""
        local workflow_run_id=""
        
        for run_id in $temp_ids; do
            local artifacts_url="${API_BASE_URL}/actions/runs/$run_id/artifacts"
            local current_artifacts_response=""
            
            # 为artifacts API请求添加重试机制
            if current_artifacts_response=$(make_api_request "$artifacts_url" "$auth_header"); then
                # 检查是否有任何artifacts
                if echo "$current_artifacts_response" | grep -q '"name":'; then
                    target_artifacts_response="$current_artifacts_response"
                    workflow_run_id="$run_id"
                    log "找到包含artifacts的工作流运行ID: $workflow_run_id"
                    break
                fi
            else
                log "警告: run_id $run_id 的 artifacts API请求失败，跳过"
                continue
            fi
        done
        
        if [ -z "$workflow_run_id" ] || [ -z "$target_artifacts_response" ]; then
            log "错误: 未找到包含artifacts的工作流运行"
            return 1
        fi
        
        # 缓存artifacts数据和运行ID
        CACHED_ARTIFACTS_DATA="$target_artifacts_response"
        CACHED_WORKFLOW_RUN_ID="$workflow_run_id"
        log "已缓存工作流数据，运行ID: $workflow_run_id"
    else
        log "使用缓存的工作流数据，运行ID: $CACHED_WORKFLOW_RUN_ID"
    fi
    
    return 0
}

# 下载并处理artifact
download_and_extract_artifact() {
    local output_file="$1"
    local artifact_name="$2"
    
    local artifacts_response="$CACHED_ARTIFACTS_DATA"
    
    log "使用artifact: $artifact_name"
    
    # 解析artifact信息 - 使用精确匹配
    local artifact_block
    artifact_block=$(echo "$artifacts_response" | awk -v name="$artifact_name" '
        BEGIN { in_block=0; block=""; found=0; brace_count=0 }
        /"artifacts"/ { in_artifacts=1 }
        in_artifacts && /{/ {
            if (!in_block) {
                block = $0 "\n"
                brace_count = 1
                in_block = 1
            } else {
                block = block $0 "\n"
                brace_count++
            }
        }
        in_block && /}/ {
            block = block $0 "\n"
            brace_count--
            if (brace_count == 0) {
                # 检查这个块是否包含我们要找的artifact名称（精确匹配）
                if (block ~ "\"name\":[[:space:]]*\"" name "\"") {
                    print block
                    found = 1
                    exit
                }
                block = ""
                in_block = 0
            }
        }
        in_block && !/{/ && !/}/ {
            block = block $0 "\n"
        }
        END { if (!found) print "ARTIFACT_NOT_FOUND" }
    ')
    
    if [ -z "$artifact_block" ] || [ "$artifact_block" = "ARTIFACT_NOT_FOUND" ]; then
        log "错误: 在artifacts响应中未找到 $artifact_name"
        log "可用的artifacts:"
        echo "$artifacts_response" | grep -o '"name":[[:space:]]*"[^"]*"' | sed 's/"name":[[:space:]]*"//;s/"//' | while read -r artifact; do
            log "  - $artifact"
        done
        return 1
    fi
    
    # 从找到的块中提取信息
    local artifact_id=$(echo "$artifact_block" | grep -o '"id": *[0-9]*' | grep -o '[0-9]*')
    local artifact_url=$(echo "$artifact_block" | grep -o '"archive_download_url": *"[^"]*"' | cut -d'"' -f4)
    local artifact_size=$(echo "$artifact_block" | grep -o '"size_in_bytes": *[0-9]*' | grep -o '[0-9]*')
    
    if [ -z "$artifact_id" ] || [ -z "$artifact_url" ]; then
        log "错误: 无法解析artifact信息"
        return 1
    fi
    
    log "开始下载artifact: $artifact_name (ID: $artifact_id)"
    
    # 下载artifact，带重试机制
    local temp_zip="/tmp/${artifact_name}_artifact.zip"
    register_temp_file "$temp_zip"
    
    local auth_header=""
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: Bearer $GITHUB_TOKEN"
    fi
    
    # 执行下载重试循环
    local retry_count=0
    local max_retries=$MAX_DOWNLOAD_RETRIES
    local download_success=false
    
    while [ $retry_count -lt $max_retries ]; do
        log "尝试下载 artifact，第 $((retry_count + 1)) 次尝试"
        
        if command -v curl >/dev/null 2>&1; then
            if curl -L -H "Accept: application/vnd.github.v3+json" -H "$auth_header" -o "$temp_zip" "$artifact_url"; then
                download_success=true
                log "curl 下载 artifact 成功"
            else
                log "curl 下载 artifact 失败，退出码: $?"
            fi
        elif command -v wget >/dev/null 2>&1; then
            if [ -n "$GITHUB_TOKEN" ]; then
                if wget -O "$temp_zip" --header="Accept: application/vnd.github.v3+json" --header="$auth_header" "$artifact_url"; then
                    download_success=true
                    log "wget 下载 artifact 成功"
                else
                    log "wget 下载 artifact 失败，退出码: $?"
                fi
            else
                if wget -O "$temp_zip" --header="Accept: application/vnd.github.v3+json" "$artifact_url"; then
                    download_success=true
                    log "wget 下载 artifact 成功"
                else
                    log "wget 下载 artifact 失败，退出码: $?"
                fi
            fi
        else
            log "错误: 系统中未找到 curl 或 wget 命令"
            return 1
        fi
        
        # 验证下载的文件
        if [ "$download_success" = true ]; then
            if [ -f "$temp_zip" ] && [ -s "$temp_zip" ]; then
                log "artifact 下载成功且文件非空"
                break
            else
                log "artifact 下载文件不存在或为空，重新尝试"
                download_success=false
                rm -f "$temp_zip"
            fi
        fi
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            local wait_time=$((retry_count * 2))
            log "下载失败，等待 ${wait_time}s 后重试..."
            sleep $wait_time
        fi
    done
    
    # 最终检查下载结果
    if [ ! -f "$temp_zip" ] || [ ! -s "$temp_zip" ]; then
        log "错误: artifact 下载失败，已重试 $max_retries 次"
        return 1
    fi
    
    log "下载完成，文件大小: $(ls -lh "$temp_zip" 2>/dev/null | awk '{print $5}' || echo '未知')"
    
    # 解压并处理artifact
    extract_and_process_artifact "$temp_zip" "$artifact_name" "$output_file"
    
    # 清理临时文件
    rm -f "$temp_zip"
    
    log "成功下载并解压 $artifact_name"
    return 0
}

# 解压并处理artifact
extract_and_process_artifact() {
    local temp_zip="$1"
    local artifact_name="$2"
    local output_file="$3"
    
    log "正在解压artifact..."
    local temp_dir="/tmp/${artifact_name}_extract"
    register_temp_dir "$temp_dir"
    
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    if ! unzip -q "$temp_zip" -d "$temp_dir"; then
        log "错误: 解压artifact失败"
        return 1
    fi
    
    # 查找并复制目标文件
    local extracted_file=""
    
    log "正在查找目标文件: $artifact_name"
    log "解压目录内容:"
    ls -la "$temp_dir" 2>/dev/null || log "无法列出目录内容"
    
    # 优先精确匹配文件名
    if [ "$artifact_name" = "static" ]; then
        # 对于static artifact，查找static.zip文件
        extracted_file=$(find "$temp_dir" -name "static.zip" -type f | head -1)
        if [ -z "$extracted_file" ]; then
            # 如果没找到static.zip，查找任何zip文件
            extracted_file=$(find "$temp_dir" -name "*.zip" -type f | head -1)
        fi
    else
        # 对于其他文件，精确匹配文件名
        extracted_file=$(find "$temp_dir" -name "$artifact_name" -type f | head -1)
        
        # 如果精确匹配失败，尝试查找可执行文件
        if [ -z "$extracted_file" ] && [[ "$artifact_name" == landscape-webserver-* ]]; then
            # 查找landscape-webserver开头的可执行文件
            extracted_file=$(find "$temp_dir" -name "landscape-webserver-*" -type f | head -1)
        elif [ -z "$extracted_file" ] && [[ "$artifact_name" == redirect_pkg_handler-* ]]; then
            # 查找redirect_pkg_handler开头的可执行文件
            extracted_file=$(find "$temp_dir" -name "redirect_pkg_handler-*" -type f | head -1)
        fi
    fi
    
    if [ -z "$extracted_file" ] || [ ! -f "$extracted_file" ]; then
        log "错误: 在解压文件中未找到目标文件 $artifact_name"
        log "期望的文件: $artifact_name"
        log "解压目录中的所有文件:"
        find "$temp_dir" -type f -exec ls -la {} \; 2>/dev/null || log "无法列出文件"
        return 1
    fi
    
    log "找到目标文件: $extracted_file"
    
    # 验证文件内容
    if ! validate_downloaded_file "$extracted_file" "$artifact_name"; then
        log "错误: 下载的文件验证失败"
        return 1
    fi
    
    # 复制文件到输出位置
    if ! cp "$extracted_file" "$output_file"; then
        log "错误: 复制文件失败"
        return 1
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
    
    return 0
}

# 验证下载的文件是否正确
validate_downloaded_file() {
    local file_path="$1"
    local expected_name="$2"
    
    log "正在验证文件: $file_path (期望: $expected_name)"
    
    # 检查文件是否存在且非空
    if [ ! -f "$file_path" ] || [ ! -s "$file_path" ]; then
        log "验证失败: 文件不存在或为空"
        return 1
    fi
    
    local file_size=$(ls -lh "$file_path" 2>/dev/null | awk '{print $5}' || echo '未知')
    log "文件大小: $file_size"
    
    # 根据文件类型进行不同的验证
    case "$expected_name" in
        "static")
            # 验证static.zip文件
            if ! file "$file_path" | grep -q "Zip archive"; then
                log "验证失败: static文件不是有效的ZIP文件"
                log "文件类型信息: $(file "$file_path")"
                return 1
            fi
            # 尝试测试zip文件完整性
            if command -v unzip >/dev/null 2>&1; then
                if ! unzip -t "$file_path" >/dev/null 2>&1; then
                    log "验证失败: static.zip文件损坏"
                    return 1
                fi
            fi
            log "static.zip文件验证成功"
            ;;
        landscape-webserver-*)
            # 验证可执行文件
            if ! file "$file_path" | grep -q "executable"; then
                log "验证失败: landscape-webserver文件不是可执行文件"
                log "文件类型信息: $(file "$file_path")"
                return 1
            fi
            # 尝试获取版本信息（如果是有效的landscape程序）
            chmod +x "$file_path" 2>/dev/null
            local version_output
            if version_output=$("$file_path" --version 2>/dev/null); then
                log "landscape版本信息: $version_output"
            else
                log "警告: 无法获取版本信息，但文件格式正确"
            fi
            log "landscape-webserver文件验证成功"
            ;;
        redirect_pkg_handler-*)
            # 验证redirect_pkg_handler二进制文件
            if ! file "$file_path" | grep -q "executable"; then
                log "验证失败: redirect_pkg_handler文件不是可执行文件"
                log "文件类型信息: $(file "$file_path")"
                return 1
            fi
            chmod +x "$file_path" 2>/dev/null
            log "redirect_pkg_handler二进制文件验证成功"
            ;;
        *)
            log "未知文件类型，跳过特殊验证"
            ;;
    esac
    
    log "文件验证完成: $expected_name"
    return 0
}

# ========== 备份函数 ==========

# 创建备份
create_backup() {
    local landscape_dir="$1"
    local version_type="$2"
    
    # 创建 backup 目录
    local backup_dir="$landscape_dir/backup"
    mkdir -p "$backup_dir"
    
    # 确定保留的备份数量
    local max_backups=$DEFAULT_STABLE_BACKUPS
    if [ "$version_type" = "beta" ] && [ "$BACKUP_COUNT" -eq 0 ]; then
        max_backups=$DEFAULT_BETA_BACKUPS
    elif [ "$BACKUP_COUNT" -gt 0 ]; then
        max_backups=$BACKUP_COUNT
    fi
    
    # 获取当前版本号
    local current_version="unknown"
    local current_filename="landscape-webserver-$SYSTEM_ARCH"
    if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
        current_filename="landscape-webserver-x86_64-musl"
    fi
    
    if [ -f "$landscape_dir/$current_filename" ]; then
        current_version=$("$landscape_dir/$current_filename" --version 2>/dev/null)
    fi
    
    # 生成备份文件名 (版本号-时间戳)
    local timestamp=$(date +"%Y%m%d%H%M%S")
    local backup_name="landscape-${current_version}-${timestamp}"
    local backup_file=""
    
    log "正在创建备份: $backup_name"
    
    # 创建临时目录用于打包
    local temp_dir
    temp_dir=$(mktemp -d) || {
        log "错误: 无法创建临时目录"
        return 1
    }
    register_temp_dir "$temp_dir"
    
    # 复制 landscape 目录内容到临时目录，排除 backup 目录
    if command -v pax >/dev/null 2>&1; then
        (cd "$landscape_dir" && find . -name "backup" -prune -o -print0 | pax -0 -rwd "$temp_dir")
    elif command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude="backup" "$landscape_dir/" "$temp_dir/"
    else
        # 使用 cp 作为最后的备用方案
        (cd "$landscape_dir" && find . -name "backup" -prune -o -type f -print0 | while IFS= read -r -d '' file; do
            dir=$(dirname "$file")
            mkdir -p "$temp_dir/$dir" 2>/dev/null
            cp "$file" "$temp_dir/$file" 2>/dev/null
        done)
    fi
    
    # 根据可用工具进行压缩，按 gz、bz2、xz、zip、tar 顺序尝试
    if command -v gzip >/dev/null 2>&1; then
        backup_file="$backup_dir/${backup_name}.tar.gz"
        log "使用压缩工具: gzip"
        (cd "$temp_dir" && tar -cf "${backup_name}.tar" --exclude="${backup_name}.tar" . && gzip -c "${backup_name}.tar" > "$backup_file" && rm -f "${backup_name}.tar")
    elif command -v bzip2 >/dev/null 2>&1; then
        backup_file="$backup_dir/${backup_name}.tar.bz2"
        log "使用压缩工具: bzip2"
        (cd "$temp_dir" && tar -cf "${backup_name}.tar" --exclude="${backup_name}.tar" . && bzip2 -c "${backup_name}.tar" > "$backup_file" && rm -f "${backup_name}.tar")
    elif command -v xz >/dev/null 2>&1; then
        backup_file="$backup_dir/${backup_name}.tar.xz"
        log "使用压缩工具: xz"
        (cd "$temp_dir" && tar -cf "${backup_name}.tar" --exclude="${backup_name}.tar" . && xz -c "${backup_name}.tar" > "$backup_file" && rm -f "${backup_name}.tar")
    elif command -v zip >/dev/null 2>&1; then
        backup_file="$backup_dir/${backup_name}.zip"
        log "使用压缩工具: zip"
        (cd "$temp_dir" && zip -rq "$backup_file" .)
    elif command -v tar >/dev/null 2>&1; then
        backup_file="$backup_dir/${backup_name}.tar"
        log "使用压缩工具: tar"
        (cd "$temp_dir" && tar -cf "$backup_file" --exclude="$(basename "$backup_file")" .)
    else
        log "错误: 系统中未找到支持的压缩工具，请安装 gzip、bzip2、xz、zip 或 tar 中的一种"
        return 1
    fi
    
    # 检查备份是否成功创建
    if [ ! -f "$backup_file" ]; then
        log "错误: 备份创建失败"
        return 1
    fi
    
    log "备份创建成功: $(basename "$backup_file")"
    
    # 清理旧备份，只保留指定数量的最新备份
    cleanup_old_backups "$backup_dir" "$max_backups"
    
    return 0
}

# 优化后的备份清理函数
cleanup_old_backups() {
    local backup_dir="$1"
    local max_backups="$2"
    
    log "正在清理旧备份文件（保留 $max_backups 个最新备份）..."
    log "备份目录路径: $backup_dir"
    
    # 检查备份目录是否存在且非空
    if [ ! -d "$backup_dir" ]; then
        log "备份目录不存在: $backup_dir"
        return 0
    fi
    
    if [ ! "$(ls -A "$backup_dir" 2>/dev/null)" ]; then
        log "备份目录为空，无需清理"
        return 0
    fi
    
    # 使用find命令直接按时间排序并删除旧文件
    local deleted_count=0
    local backup_count=0
    
    # 计算总备份文件数
    backup_count=$(find "$backup_dir" -maxdepth 1 -type f | wc -l)
    
    if [ "$backup_count" -gt "$max_backups" ]; then
        local to_remove=$((backup_count - max_backups))
        log "找到 $backup_count 个备份文件，需要删除 $to_remove 个旧备份"
        
        # 使用find命令按时间排序，删除旧文件
        while IFS= read -r -d '' file; do
            if rm -f "$file"; then
                deleted_count=$((deleted_count + 1))
                log "删除旧备份: $(basename "$file")"
            fi
        done < <(find "$backup_dir" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | \
                sort -z -n | \
                cut -z -d' ' -f2- | \
                head -z -n "$to_remove" | \
                tr '\0' '\n')
        
        log "备份清理完成，已保留 $max_backups 个最新备份，删除了 $deleted_count 个旧备份"
    else
        log "备份数量未超过限制，无需清理"
    fi
}

# ========== 回滚函数 ==========

# 处理回滚操作
handle_rollback_operation() {
    # 初始化回滚日志
    init_log
    log "Landscape Router 回滚脚本开始执行"
    log "检测到 Landscape Router 安装目录: $LANDSCAPE_DIR"
    log "当前版本: $CURRENT_VERSION"
    
    local backup_dir="$LANDSCAPE_DIR/backup"
    
    # 验证备份目录存在
    if [ ! -d "$backup_dir" ]; then
        log "错误: 未找到备份目录 $backup_dir"
        return 1
    fi
    
    # 查找所有备份文件，按时间排序
    local backup_files=()
    
    # 使用find命令按时间排序
    if find "$backup_dir" -maxdepth 1 -type f -printf '%T@ %p\0' >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            backup_files+=("$file")
        done < <(find "$backup_dir" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | \
                sort -z -rn | \
                cut -z -d' ' -f2- | \
                tr '\0' '\n')
    else
        # 备用方法：获取所有文件并按时间排序
        local temp_files=()
        for file in "$backup_dir"/*; do
            if [ -f "$file" ]; then
                temp_files+=("$file")
            fi
        done
        
        # 如果找到文件，按修改时间排序
        if [ ${#temp_files[@]} -gt 0 ]; then
            while IFS= read -r -d '' file; do
                backup_files+=("$file")
            done < <(for f in "${temp_files[@]}"; do printf '%s\t%s\0' "$(stat -c '%Y' "$f" 2>/dev/null || echo 0)" "$f"; done | sort -z -rn | cut -f2- | tr '\0' '\n')
        fi
    fi
    
    local backup_count=${#backup_files[@]}
    # 检查是否有备份文件
    if [ $backup_count -eq 0 ]; then
        log "错误: 未找到任何备份文件"
        return 1
    fi
    
    # 显示可用备份供用户选择
    log "可用的备份文件:"
    local i
    for ((i=0; i<backup_count; i++)); do
        log "$((i+1)) $(basename "${backup_files[$i]}")"
    done
    
    # 获取用户选择
    local choice
    while true; do
        read -p "请选择要回滚到的备份版本 (1-${backup_count}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $backup_count ]; then
            break
        else
            log "无效选择，请输入 1 到 $backup_count 之间的数字"
        fi
    done
    
    local selected_backup="${backup_files[$((choice-1))]}"
    log "正在回滚到备份: $(basename "$selected_backup")"
    
    # 停止服务
    control_landscape_service "stop"
    # 停止 docker 服务
    control_docker_service "stop"
    DOCKER_STOPPED_BY_SCRIPT=true

    # 创建临时目录
    local temp_dir
    temp_dir=$(mktemp -d) || {
        log "错误: 无法创建临时目录"
        control_landscape_service "start"
        return 1
    }
    register_temp_dir "$temp_dir"
    
    # 解压备份文件
    if [[ "$selected_backup" == *.tar.gz ]]; then
        # 解压 .tar.gz 文件
        (cd "$temp_dir" && tar -xzf "$selected_backup")
    elif [[ "$selected_backup" == *.tar.bz2 ]]; then
        # 解压 .tar.bz2 文件
        (cd "$temp_dir" && tar -xjf "$selected_backup")
    elif [[ "$selected_backup" == *.tar.xz ]]; then
        # 解压 .tar.xz 文件
        (cd "$temp_dir" && tar -xJf "$selected_backup")
    elif [[ "$selected_backup" == *.tar ]]; then
        # 解压 .tar 文件
        (cd "$temp_dir" && tar -xf "$selected_backup")
    elif [[ "$selected_backup" == *.zip ]]; then
        # 解压 .zip 文件
        (cd "$temp_dir" && unzip -q "$selected_backup")
    else
        log "错误: 不支持的备份文件格式"
        return 1
    fi
    
    # 清空 landscape 目录（排除 backup 目录）
    (cd "$LANDSCAPE_DIR" && find . -name "backup" -prune -o -exec rm -rf {} + 2>/dev/null || true)
    
    # 将备份内容复制回 landscape 目录
    if command -v pax >/dev/null 2>&1; then
        (cd "$temp_dir" && find . -print0 | pax -0 -rwd "$LANDSCAPE_DIR")
    elif command -v rsync >/dev/null 2>&1; then
        rsync -a "$temp_dir/" "$LANDSCAPE_DIR/"
    else
        # 使用 cp 作为最后的备用方案
        (cd "$temp_dir" && find . -type f -print0 | while IFS= read -r -d '' file; do
            dir=$(dirname "$file")
            mkdir -p "$LANDSCAPE_DIR/$dir" 2>/dev/null
            cp "$file" "$LANDSCAPE_DIR/$file" 2>/dev/null
        done)
    fi
    
    log "回滚完成"
    
    # 处理重启
    read -p "是否立即重启系统以应用回滚？(y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "正在重启系统以应用回滚..."
        reboot
    else
        log "正在启动 Landscape Router 服务..."
        control_landscape_service "start"
        control_docker_service "start"
        log "回滚操作已成功完成，但系统尚未重启。"
        log "注意：Landscape Router 的某些功能可能无法正常工作。"
        log "重要提示：请在方便的时候尽快手动执行重启，以确保回滚完全生效。"
    fi
}

# ========== 串行下载函数 ==========

# 解析下载任务信息
parse_download_task() {
    local task="$1"
    local -n desc_ref=$2
    local -n url_ref=$3
    local -n path_ref=$4
    
    # 提取文件描述（第一个冒号之前的部分）
    desc_ref="${task%%:*}"
    
    # 提取文件路径（最后一个冒号之后的部分）
    path_ref="${task##*:}"
    
    # 提取URL（中间部分）
    local temp="${task#*:}"
    url_ref="${temp%:*}"
}

# 串行下载多个文件
download_files_serially() {
    local temp_dir="$1"
    local version_type="$2"
    local landscape_dir="$3"
    local executable_filename="$4"
    
    log "正在串行下载所需文件..."
    
    # 准备下载信息
    local download_info
    download_info=$(get_download_info "$version_type")
    # 修复URL解析方式，确保正确处理包含多个冒号的URL
    local download_url=""
    local temp_filename=""
    IFS='|' read -r download_url temp_filename <<< "$download_info"
    
    # 如果解析出来的文件名不为空，则使用解析出来的文件名
    if [ -n "$temp_filename" ]; then
        executable_filename="$temp_filename"
    fi
    
    local static_download_url
    static_download_url=$(get_static_download_url "$version_type")

    local redirect_pkg_handler_script_url
    log "正在获取 redirect_pkg_handler.sh 下载URL..."
    # 对于 redirect_pkg_handler.sh，无论什么版本都使用 github_actions
    # 让 download_from_github_actions 函数特殊处理
    redirect_pkg_handler_script_url="github_actions"
    log "redirect_pkg_handler.sh 下载URL: $redirect_pkg_handler_script_url"
    
    # 创建下载任务列表
    local download_tasks=()
    
    # 必需文件
    download_tasks+=("可执行文件:$download_url:$temp_dir/$executable_filename")
    download_tasks+=("static.zip:$static_download_url:$temp_dir/static.zip")
    download_tasks+=("redirect_pkg_handler.sh:$redirect_pkg_handler_script_url:$temp_dir/redirect_pkg_handler.sh")
    
    # 根据架构添加redirect_pkg_handler二进制文件
    case "$SYSTEM_ARCH" in
        "x86_64")
            if [ -f "$landscape_dir/redirect_pkg_handler-x86_64" ]; then
                local redirect_pkg_handler_x86_64_url
                redirect_pkg_handler_x86_64_url=$(get_redirect_pkg_handler_url "$version_type" "binary" "redirect_pkg_handler-x86_64")
                download_tasks+=("redirect_pkg_handler-x86_64:$redirect_pkg_handler_x86_64_url:$temp_dir/redirect_pkg_handler-x86_64")
            fi
            
            if [ -f "$landscape_dir/redirect_pkg_handler-x86_64-musl" ]; then
                local redirect_pkg_handler_x86_64_musl_url
                redirect_pkg_handler_x86_64_musl_url=$(get_redirect_pkg_handler_url "$version_type" "binary" "redirect_pkg_handler-x86_64-musl")
                download_tasks+=("redirect_pkg_handler-x86_64-musl:$redirect_pkg_handler_x86_64_musl_url:$temp_dir/redirect_pkg_handler-x86_64-musl")
            fi
            ;;
        "aarch64")
            if [ -f "$landscape_dir/redirect_pkg_handler-aarch64" ]; then
                local redirect_pkg_handler_aarch64_url
                redirect_pkg_handler_aarch64_url=$(get_redirect_pkg_handler_url "$version_type" "binary" "redirect_pkg_handler-aarch64")
                download_tasks+=("redirect_pkg_handler-aarch64:$redirect_pkg_handler_aarch64_url:$temp_dir/redirect_pkg_handler-aarch64")
            fi
            
            if [ -f "$landscape_dir/redirect_pkg_handler-aarch64-musl" ]; then
                local redirect_pkg_handler_aarch64_musl_url
                redirect_pkg_handler_aarch64_musl_url=$(get_redirect_pkg_handler_url "$version_type" "binary" "redirect_pkg_handler-aarch64-musl")
                download_tasks+=("redirect_pkg_handler-aarch64-musl:$redirect_pkg_handler_aarch64_musl_url:$temp_dir/redirect_pkg_handler-aarch64-musl")
            fi
            ;;
    esac
    
    # 执行串行下载
    local total_files=${#download_tasks[@]}
    local current_file=0
    
    for task in "${download_tasks[@]}"; do
        current_file=$((current_file + 1))
        # 使用自定义函数解析任务信息，避免URL中的冒号导致解析错误
        local file_desc=""
        local file_url=""
        local file_path=""
        parse_download_task "$task" file_desc file_url file_path
        
        log "[$current_file/$total_files] 正在下载 $file_desc..."
        
        # 对于Beta版本，使用GitHub Token加速下载（但redirect_pkg_handler.sh除外）
        local use_token="false"
        if [ "$version_type" = "beta" ] && [ "$file_desc" != "redirect_pkg_handler.sh" ]; then
            use_token="true"
        fi
        
        if ! download_with_retry "$file_url" "$file_path" "$use_token"; then
            log "错误: $file_desc 下载失败"
            return 1
        fi
        
        # 验证文件是否下载成功且内容正确
        if [ ! -f "$file_path" ] || [ ! -s "$file_path" ]; then
            log "错误: $file_desc 下载文件无效或为空"
            return 1
        fi
        
        # 根据文件类型进行额外验证
        case "$file_desc" in
            "static.zip")
                # 验证ZIP文件
                if ! file "$file_path" | grep -q "Zip archive"; then
                    log "错误: $file_desc 不是有效的ZIP文件"
                    log "文件类型信息: $(file "$file_path")"
                    rm -f "$file_path"  # 删除无效文件
                    return 1
                fi
                if command -v unzip >/dev/null 2>&1; then
                    if ! unzip -t "$file_path" >/dev/null 2>&1; then
                        log "错误: $file_desc ZIP文件损坏"
                        rm -f "$file_path"  # 删除损坏文件
                        return 1
                    fi
                fi
                ;;
            "可执行文件")
                # 验证可执行文件
                if ! file "$file_path" | grep -q "executable"; then
                    log "错误: $file_desc 不是有效的可执行文件"
                    log "文件类型信息: $(file "$file_path")"
                    rm -f "$file_path"  # 删除无效文件
                    return 1
                fi
                chmod +x "$file_path" 2>/dev/null
                ;;
            redirect_pkg_handler-*)
                # 验证redirect_pkg_handler二进制文件
                if ! file "$file_path" | grep -q "executable"; then
                    log "错误: $file_desc 不是有效的可执行文件"
                    log "文件类型信息: $(file "$file_path")"
                    rm -f "$file_path"  # 删除无效文件
                    return 1
                fi
                chmod +x "$file_path" 2>/dev/null
                ;;
            "redirect_pkg_handler.sh")
                # 验证shell脚本
                if [ ! -s "$file_path" ]; then
                    log "错误: $file_desc 文件为空"
                    rm -f "$file_path"  # 删除空文件
                    return 1
                fi
                if ! head -1 "$file_path" 2>/dev/null | grep -q "^#!/"; then
                    log "错误: $file_desc 不是有效的shell脚本"
                    log "文件前几行内容:"
                    head -5 "$file_path" 2>/dev/null | while read -r line; do log "  $line"; done
                    rm -f "$file_path"  # 删除无效文件
                    return 1
                fi
                chmod +x "$file_path" 2>/dev/null
                ;;
        esac
        
        log "✓ $file_desc 下载并验证成功"
    done
    
    log "所有文件串行下载完成"
    return 0
}

# ========== 升级函数 ==========

upgrade_landscape_version() {
    local version_type="$1"  # stable, beta
    local display_name="$2"  # 显示名称
    local landscape_dir="$3" # 安装目录
    
    # 显示升级开始消息
    if [ "$USE_CN_MIRROR" = true ]; then
        log "正在使用中国镜像加速升级 Landscape Router 到最新 $display_name..."
    else
        log "正在升级 Landscape Router 到最新 $display_name..."
    fi
    
    # 检查是否已安装
    local filename="landscape-webserver-$SYSTEM_ARCH"
    if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
        filename="landscape-webserver-x86_64-musl"
    fi
    
    if [ ! -f "$landscape_dir/$filename" ]; then
        log "错误: 未检测到已安装的 Landscape Router"
        exit 1
    fi
    
    # 创建临时目录
    local temp_dir
    temp_dir=$(mktemp -d) || {
        log "错误: 无法创建临时目录"
        exit 1
    }
    register_temp_dir "$temp_dir"
    
    log "下载文件到临时目录: $temp_dir"
    
    # 确保下载目录存在
    mkdir -p "$temp_dir"
    
    # 使用串行下载所有文件
    if ! download_files_serially "$temp_dir" "$version_type" "$landscape_dir" "$filename"; then
        log "文件下载失败"
        exit 1
    fi
    
    # 所有文件下载成功后，如果需要创建备份
    if [ "$CREATE_BACKUP" = true ]; then
        log "正在创建备份..."
        create_backup "$landscape_dir" "$version_type" || {
            log "备份创建失败"
            exit 1
        }
    fi
    
    # 解压static.zip
    log "正在解压 static.zip..."
    mkdir -p "$temp_dir/statictmp"
    if ! unzip "$temp_dir/static.zip" -d "$temp_dir/statictmp"; then
        log "static.zip 解压失败"
        exit 1
    fi
    
    # 对于稳定版，检查版本是否相同
    if [ "$version_type" = "stable" ]; then
        # 为新下载的文件添加执行权限以获取版本信息
        chmod +x "$temp_dir/$filename"
        
        # 获取当前版本信息
        local current_version=""
        if [ -f "$landscape_dir/$filename" ]; then
            current_version=$("$landscape_dir/$filename" --version 2>/dev/null)
        fi
        
        # 获取新版本信息
        local new_version=""
        new_version=$("$temp_dir/$filename" --version 2>/dev/null)
        log "最新版本: $new_version"
        
        # 比较版本，如果版本相同则提示无需升级
        if [ -n "$current_version" ] && [ "$current_version" = "$new_version" ]; then
            log "当前已是最新稳定版，无需升级"
            exit 1
        fi
    fi
    
    # 停止服务并执行升级
    control_landscape_service "stop"
    
    # 设置下载文件的执行权限
    chmod +x "$temp_dir/$filename"
    chmod +x "$temp_dir/redirect_pkg_handler.sh"
    
    # 根据架构为对应的redirect_pkg_handler二进制文件添加执行权限
    case "$SYSTEM_ARCH" in
        "x86_64")
            # 为存在的文件添加执行权限
            if [ -f "$temp_dir/redirect_pkg_handler-x86_64" ]; then
                chmod +x "$temp_dir/redirect_pkg_handler-x86_64"
            fi
            
            if [ -f "$temp_dir/redirect_pkg_handler-x86_64-musl" ]; then
                chmod +x "$temp_dir/redirect_pkg_handler-x86_64-musl"
            fi
            ;;
        "aarch64")
            # 为存在的文件添加执行权限
            if [ -f "$temp_dir/redirect_pkg_handler-aarch64" ]; then
                chmod +x "$temp_dir/redirect_pkg_handler-aarch64"
            fi
            
            if [ -f "$temp_dir/redirect_pkg_handler-aarch64-musl" ]; then
                chmod +x "$temp_dir/redirect_pkg_handler-aarch64-musl"
            fi
            ;;
    esac
    
    # 使用新的文件替换函数，带有重试和回滚机制
    if ! replace_files_with_rollback "$temp_dir" "$landscape_dir" "$filename"; then
        log "文件替换失败，已执行回滚操作"
        log "正在启动 Landscape Router 服务..."
        control_landscape_service "start"
        exit 1
    fi
    
    log "Landscape Router $display_name 升级完成"
    
    # 将当前脚本复制到Landscape安装目录，以备rollback时使用
    # 复制当前脚本到Landscape安装目录
    if cp "$0" "$landscape_dir/$SCRIPT_NAME"; then
        # 设置执行权限
        chmod +x "$landscape_dir/$SCRIPT_NAME"
        log "成功将 $SCRIPT_NAME 复制到 $landscape_dir 目录，以备rollback时使用"
    else
        log "警告: 无法将 $SCRIPT_NAME 复制到 $landscape_dir 目录"
    fi
    
    # 处理重启
    if [ "$AUTO_REBOOT" = true ]; then
        log "正在重启系统以应用更新..."
        echo ""
        echo "================================"
        echo "o(≧▽≦)o 升级完成，请等待系统重启"
        echo "================================"
        echo ""
        reboot
    else
        control_landscape_service "start"
        log "升级已完成，但系统尚未重启。"
        log "Landscape Router已启动，但部分功能可能无法正常使用。"
        log "建议您在适当的时候手动重启系统。"
        echo ""
        echo "================================"
        echo "o(≧▽≦)o 升级完成，请等待软件启动"
        echo "================================"
        echo ""
    fi
}

# 优化后的文件替换函数，带重试和回滚机制，修复竞态条件
replace_files_with_rollback() {
    local temp_dir="$1"
    local landscape_dir="$2"
    local filename="$3"
    local max_retries=$MAX_FILE_REPLACE_RETRIES
    
    log "开始文件替换操作..."
    
    # 创建备份目录保存原文件（临时备份）
    local backup_temp_dir="$temp_dir/backup_for_rollback"
    mkdir -p "$backup_temp_dir"
    
    # 定义需要替换的文件列表
    local replace_tasks=()
    
    # 主可执行文件
    if [ -f "$temp_dir/$filename" ]; then
        replace_tasks+=("executable:$landscape_dir/$filename:$temp_dir/$filename")
    fi
    
    # 静态文件
    if [ -d "$temp_dir/statictmp" ]; then
        replace_tasks+=("static:$landscape_dir/static:$temp_dir/statictmp")
    fi
    
    # redirect_pkg_handler.sh
    if [ -f "$temp_dir/redirect_pkg_handler.sh" ]; then
        replace_tasks+=("script:$landscape_dir/redirect_pkg_handler.sh:$temp_dir/redirect_pkg_handler.sh")
    fi
    
    # 架构相关的二进制文件
    case "$SYSTEM_ARCH" in
        "x86_64")
            if [ -f "$temp_dir/redirect_pkg_handler-x86_64" ]; then
                replace_tasks+=("binary_x86_64:$landscape_dir/redirect_pkg_handler-x86_64:$temp_dir/redirect_pkg_handler-x86_64")
            fi
            if [ -f "$temp_dir/redirect_pkg_handler-x86_64-musl" ]; then
                replace_tasks+=("binary_x86_64_musl:$landscape_dir/redirect_pkg_handler-x86_64-musl:$temp_dir/redirect_pkg_handler-x86_64-musl")
            fi
            ;;
        "aarch64")
            if [ -f "$temp_dir/redirect_pkg_handler-aarch64" ]; then
                replace_tasks+=("binary_aarch64:$landscape_dir/redirect_pkg_handler-aarch64:$temp_dir/redirect_pkg_handler-aarch64")
            fi
            if [ -f "$temp_dir/redirect_pkg_handler-aarch64-musl" ]; then
                replace_tasks+=("binary_aarch64_musl:$landscape_dir/redirect_pkg_handler-aarch64-musl:$temp_dir/redirect_pkg_handler-aarch64-musl")
            fi
            ;;
    esac
    
    # 记录替换成功的文件列表，用于需要时回滚
    local successfully_replaced=()
    local failed_files=()
    
    # 逐个替换文件，串行处理
    for task in "${replace_tasks[@]}"; do
        local file_type=$(echo "$task" | cut -d':' -f1)
        local target_path=$(echo "$task" | cut -d':' -f2)
        local source_path=$(echo "$task" | cut -d':' -f3)
        
        log "开始替换 $file_type..."
        
        # 单个文件的重试机制
        local file_retry_count=0
        local file_replace_success=false
        local docker_stopped_for_this_file=false
        
        while [ $file_retry_count -lt $max_retries ]; do
            log "替换 $file_type (尝试 $((file_retry_count + 1))/$max_retries)..."
            
            # 对于redirect_pkg_handler相关的二进制文件（除了redirect_pkg_handler.sh），
            # 如果第一次失败，停止Docker服务后再尝试
            # 同时，如果指定了STOP_DOCKER选项，对于所有binary_*类型的文件也停止Docker服务
            if [[ "$file_type" == "binary_"* ]] && [ $file_retry_count -eq 3 ] && [ "$file_replace_success" = false ] || \
               [[ "$file_type" == "binary_"* ]] && [ "$STOP_DOCKER" = true ] && [ $file_retry_count -eq 0 ]; then
                if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet docker 2>/dev/null; then
                    log "将停止Docker服务，以保证成功替换 $file_type"
                    control_docker_service "stop"
                    docker_stopped_for_this_file=true
                    log "Docker服务已停止"
                fi
            fi
            
            # 备份原文件（如果存在）
            local backup_path="$backup_temp_dir/$(basename "$target_path").bak"
            if [ -e "$target_path" ]; then
                if ! cp -r "$target_path" "$backup_path" 2>/dev/null; then
                    log "警告: 无法备份 $file_type"
                else
                    log "已备份 $file_type 到 $backup_path"
                fi
            fi
            
            # 执行替换
            local replace_result=false
            if [ "$file_type" = "static" ]; then
                # 替换静态文件目录
                rm -rf "$target_path" 2>/dev/null || true
                
                # 查找包含index.html的目录
                local static_source_dir=""
                if [ -f "$source_path/index.html" ]; then
                    static_source_dir="$source_path"
                else
                    for dir in "$source_path"/*/; do
                        if [ -d "$dir" ] && [ -f "$dir/index.html" ]; then
                            static_source_dir="$dir"
                            break
                        fi
                    done
                fi
                
                if [ -z "$static_source_dir" ]; then
                    log "错误: 未找到包含 index.html 的目录"
                else
                    if cp -r "$static_source_dir" "$target_path" 2>/dev/null; then
                        replace_result=true
                        log "✓ $file_type 替换成功"
                    else
                        log "错误: 无法替换 $file_type"
                    fi
                fi
            else
                # 替换单个文件
                if cp "$source_path" "$target_path" 2>/dev/null; then
                    replace_result=true
                    
                    # 设置执行权限（如果需要）
                    if [[ "$file_type" == "executable" ]] || [[ "$file_type" == "script" ]] || [[ "$file_type" == binary_* ]]; then
                        chmod +x "$target_path" 2>/dev/null || true
                    fi
                    
                    log "✓ $file_type 替换成功"
                else
                    log "错误: 无法替换 $file_type"
                fi
            fi
            
            # 检查替换结果
            if [ "$replace_result" = true ]; then
                file_replace_success=true
                successfully_replaced+=("$task")
                break
            else
                file_retry_count=$((file_retry_count + 1))
                if [ $file_retry_count -lt $max_retries ]; then
                    local wait_time=$((file_retry_count * 2))
                    log "等待 $wait_time 秒后重试替换 $file_type..."
                    sleep $wait_time
                fi
            fi
        done
        
        # 如果单个文件替换最终失败，记录失败文件
        if [ "$file_replace_success" = false ]; then
            failed_files+=("$file_type")
            log "文件 $file_type 替换最终失败，已重试 $max_retries 次"
        fi
    done
    
    # 检查是否有失败的文件
    if [ ${#failed_files[@]} -gt 0 ]; then
        log "错误: 以下文件替换失败:"
        for failed_file in "${failed_files[@]}"; do
            log "  - $failed_file"
        done
        
        log "正在恢复已备份的文件..."
        
        # 恢复所有已替换的文件
        for task in "${successfully_replaced[@]}"; do
            local file_type=$(echo "$task" | cut -d':' -f1)
            local target_path=$(echo "$task" | cut -d':' -f2)
            local backup_path="$backup_temp_dir/$(basename "$target_path").bak"
            
            if [ -e "$backup_path" ]; then
                rm -rf "$target_path" 2>/dev/null || true
                if cp -r "$backup_path" "$target_path" 2>/dev/null; then
                    log "已恢复: $(basename "$target_path")"
                else
                    log "警告: 无法恢复 $(basename "$target_path")"
                fi
            fi
        done
        
        # 执行完整系统回滚
        log "正在执行完整系统回滚..."
        perform_system_rollback "$landscape_dir"
        
        return 1
    fi
    
    log "所有文件替换成功"
    
    # 根据是否停止了Docker服务以及是否需要重启来决定是否启动Docker服务
    if [ "$DOCKER_STOPPED_BY_SCRIPT" = true ]; then
        if [ "$AUTO_REBOOT" = true ]; then
            log "Docker服务已被停止，将在系统重启后自动启动"
        else
            log "正在启动 Docker 服务..."
            control_docker_service "start"
            log "Docker 服务已启动"
        fi
    fi
    
    # 清理临时备份文件
    rm -rf "$backup_temp_dir"
    
    return 0
}

# 执行完整系统回滚
perform_system_rollback() {
    local landscape_dir="$1"
    local backup_dir="$landscape_dir/backup"
    
    log "正在执行系统回滚..."
    
    # 检查备份目录是否存在
    if [ ! -d "$backup_dir" ]; then
        log "错误: 未找到备份目录，无法进行回滚"
        return 1
    fi
    
    # 查找最新的备份文件
    local latest_backup=""
    
    # 先尝试使用 find 的 -printf 参数（GNU find）
    if find "$backup_dir" -maxdepth 1 -type f -printf '%T@ %p\n' >/dev/null 2>&1; then
        while IFS= read -r -d '' file; do
            latest_backup="$file"
            break
        done < <(find "$backup_dir" -maxdepth 1 -type f -printf '%T@ %p\0' 2>/dev/null | \
                sort -z -rn | \
                cut -z -d' ' -f2- | \
                tr '\0' '\n')
    else
        # 备用方法：使用 stat 命令
        local temp_files=()
        for file in "$backup_dir"/*; do
            if [ -f "$file" ]; then
                temp_files+=("$file")
            fi
        done
        
        if [ ${#temp_files[@]} -gt 0 ]; then
            while IFS= read -r -d '' file; do
                latest_backup="$file"
                break
            done < <(for f in "${temp_files[@]}"; do printf '%s\t%s\0' "$(stat -c '%Y' "$f" 2>/dev/null || echo 0)" "$f"; done | sort -z -rn | cut -f2- | tr '\0' '\n')
        fi
    fi
    
    if [ -z "$latest_backup" ]; then
        log "错误: 未找到任何备份文件"
        return 1
    fi
    
    log "找到最新备份: $(basename "$latest_backup")"
    log "正在执行自动回滚..."
    
    # 创建临时目录
    local temp_dir
    temp_dir=$(mktemp -d) || {
        log "错误: 无法创建临时目录"
        return 1
    }
    register_temp_dir "$temp_dir"
    
    # 解压备份文件
    if [[ "$latest_backup" == *.tar.gz ]]; then
        (cd "$temp_dir" && tar -xzf "$latest_backup") || {
            log "错误: 解压备份文件失败"
            return 1
        }
    elif [[ "$latest_backup" == *.tar.bz2 ]]; then
        (cd "$temp_dir" && tar -xjf "$latest_backup") || {
            log "错误: 解压备份文件失败"
            return 1
        }
    elif [[ "$latest_backup" == *.tar.xz ]]; then
        (cd "$temp_dir" && tar -xJf "$latest_backup") || {
            log "错误: 解压备份文件失败"
            return 1
        }
    elif [[ "$latest_backup" == *.tar ]]; then
        (cd "$temp_dir" && tar -xf "$latest_backup") || {
            log "错误: 解压备份文件失败"
            return 1
        }
    elif [[ "$latest_backup" == *.zip ]]; then
        (cd "$temp_dir" && unzip -q "$latest_backup") || {
            log "错误: 解压备份文件失败"
            return 1
        }
    else
        log "错误: 不支持的备份文件格式"
        return 1
    fi
    
    # 清空 landscape 目录（排除 backup 目录）
    (cd "$landscape_dir" && find . -name "backup" -prune -o -exec rm -rf {} + 2>/dev/null || true)
    
    # 将备份内容复制回 landscape 目录
    if command -v rsync >/dev/null 2>&1; then
        rsync -a "$temp_dir/" "$landscape_dir/" || {
            log "错误: 复制备份文件失败"
            return 1
        }
    else
        # 使用 cp 作为备用方案
        (cd "$temp_dir" && find . -type f -print0 | while IFS= read -r -d '' file; do
            local dir=$(dirname "$file")
            mkdir -p "$landscape_dir/$dir" 2>/dev/null
            cp "$file" "$landscape_dir/$file" 2>/dev/null
        done) || {
            log "错误: 复制备份文件失败"
            return 1
        }
    fi
    
    log "系统回滚完成"
    return 0
}

# 升级 Landscape Router 稳定版
upgrade_stable() {
    upgrade_landscape_version "stable" "稳定版" "$1"
}

# 升级到 Beta 版本
upgrade_beta() {
    upgrade_landscape_version "beta" "beta版" "$1"
}

# 执行主函数
main "$@"
