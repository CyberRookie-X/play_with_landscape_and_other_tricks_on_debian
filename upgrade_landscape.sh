#!/bin/bash

# Landscape Router 升级脚本

# 用法: ./upgrade_landscape.sh [--stable|--beta] [--cn] [--reboot] [--backup[=N]] [--rollback]
# 参数:
#   --stable       - 升级到最新稳定版（默认）
#   --beta         - 升级到最新 Beta 版
#   --cn           - 使用中国镜像加速（可选）
#   --reboot       - 升级完成后自动重启（可选）
#   --backup       - 升级前进行备份
#   --backup=N     - 升级前进行备份，并指定保留N个备份（默认stable保留1个，beta保留3个）
#   --rollback     - 回滚到之前的备份版本（交互式）
#   -h, --help     - 显示此帮助信息

# 示例:
#   ./upgrade_landscape.sh                    # 升级到最新稳定版
#   ./upgrade_landscape.sh --stable           # 升级到最新稳定版
#   ./upgrade_landscape.sh --beta             # 升级到最新 Beta 版
#   ./upgrade_landscape.sh --stable --cn      # 使用中国镜像升级到最新稳定版
#   ./upgrade_landscape.sh --stable --reboot  # 升级到最新稳定版并自动重启
#   ./upgrade_landscape.sh --backup           # 升级前进行备份
#   ./upgrade_landscape.sh --backup=5         # 升级前进行备份，保留最近5个备份
#   ./upgrade_landscape.sh --rollback         # 回滚到之前的备份版本
#   ./upgrade_landscape.sh -h                 # 显示帮助信息

# TODO
# 用户可能对于 可执行文件有不同的命名方式
# 完整的 gitee 仓库，以实现可靠的中国网络镜像加速
# beta版，调整到 release 发布？


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

# ========== 主函数 ==========

main() {
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
  
  log "Landscape Router 升级脚本开始执行"
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
}

# 处理回滚操作
handle_rollback_operation() {
  # 初始化回滚日志
  init_log
  log "Landscape Router 回滚脚本开始执行"
  log "检测到 Landscape Router 安装目录: $LANDSCAPE_DIR"
  log "当前版本: $CURRENT_VERSION"
  rollback_landscape
}

# ========== 日志函数 ==========

# 初始化日志
init_log() {
  local timestamp
  timestamp=$(date +"%Y%m%d%H%M%S")
  
  # 使用全局变量中的 landscape_dir
  local landscape_dir="$LANDSCAPE_DIR"
  
  # 如果无法获取安装目录，则使用临时目录
  if [ -z "$landscape_dir" ]; then
    if [ "$ROLLBACK" = true ]; then
      UPGRADE_LOG="/tmp/rollback-from-${CURRENT_VERSION}-$timestamp.log"
    else
      UPGRADE_LOG="/tmp/upgrade-from-${CURRENT_VERSION}-$timestamp.log"
    fi
    touch "$UPGRADE_LOG" 2>/dev/null || true
    return
  fi
  
  # 创建 script_log 目录
  local log_dir="$landscape_dir/script_log"
  if ! mkdir -p "$log_dir" 2>/dev/null; then
    # 如果创建失败，则使用临时目录
    if [ "$ROLLBACK" = true ]; then
      UPGRADE_LOG="/tmp/rollback-from-${CURRENT_VERSION}-$timestamp.log"
    else
      UPGRADE_LOG="/tmp/upgrade-from-${CURRENT_VERSION}-$timestamp.log"
    fi
    touch "$UPGRADE_LOG" 2>/dev/null || true
    return
  fi
  
  # 设置日志文件路径
  if [ "$ROLLBACK" = true ]; then
    # 回滚日志文件名以 rollback 开头
    UPGRADE_LOG="$log_dir/rollback-from-${CURRENT_VERSION}-${timestamp}.log"
  else
    # 升级日志文件名以 upgrade-from 开头，使用全局变量中的当前版本号
    UPGRADE_LOG="$log_dir/upgrade-from-${CURRENT_VERSION}-${timestamp}.log"
  fi
  
  # 创建日志文件
  touch "$UPGRADE_LOG" 2>/dev/null || true
  
  # 清理旧的日志文件，最多保留16个（仅当使用实际安装目录时才清理）
  if [ -d "$log_dir" ] && [ "$landscape_dir" != "/tmp" ]; then
    cleanup_old_logs "$log_dir"
  fi
}

# 记录日志消息
log() {
  local message="$1"
  local timestamp
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  
  # 输出到控制台
  printf "[%s] %s\n" "$timestamp" "$message"
  
  # 输出到日志文件（如果可用）
  if [ -n "$UPGRADE_LOG" ] && [ -f "$UPGRADE_LOG" ]; then
    printf "[%s] %s\n" "$timestamp" "$message" >> "$UPGRADE_LOG"
  fi
}

# 清理旧的日志文件，最多保留16个
cleanup_old_logs() {
  local log_dir="$1"
  
  # 查找所有升级日志和回滚日志文件，按修改时间排序（最新的在前）
  local log_files=()
  while IFS= read -r -d '' file; do
    log_files+=("$file")
  done < <(find "$log_dir" \( -name "upgrade-from-*.log" -o -name "rollback-*.log" \) -print0 | sort -rz)
  
  # 计算需要删除的文件数量
  local log_count=${#log_files[@]}
  local to_remove=$((log_count - 16))
  
  # 删除旧的日志文件
  if [ $to_remove -gt 0 ]; then
    local i
    for ((i=log_count-1; i>=16; i--)); do
      if [ -f "${log_files[$i]}" ]; then
        rm -f "${log_files[$i]}"
      fi
    done
  fi
}

# ========== 函数定义 ==========

# 系统环境检查（包括架构、初始化系统和依赖项）
check_system_environment() {
  # 检查系统架构
  check_system_architecture
  
  # 检查是否使用 musl libc
  check_musl_usage
  
  # 检查系统使用的初始化系统 (systemd 或 OpenRC)
  detect_init_system
  
  # 检查依赖项
  check_dependencies
}

# 检查系统架构
check_system_architecture() {
  SYSTEM_ARCH=$(uname -m)
  if [ "$SYSTEM_ARCH" != "x86_64" ] && [ "$SYSTEM_ARCH" != "aarch64" ]; then
    printf "不支持的系统架构: %s\n" "$SYSTEM_ARCH" >&2
    exit 1
  fi
}

# 检查是否使用 musl libc
check_musl_usage() {
  if ldd --version 2>&1 | grep -q musl; then
    USE_MUSL=true
  fi
}

# 检查系统使用的初始化系统
detect_init_system() {
  if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
  else
    printf "错误: 不支持的初始化系统，需要 systemd 或 OpenRC\n" >&2
    exit 1
  fi
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
  check_service_management_tools missing_deps
  
  # 如果有缺失的依赖，报告并退出
  if [ ${#missing_deps[@]} -gt 0 ]; then
    report_missing_dependencies "${missing_deps[@]}"
    exit 1
  fi
}

# 检查服务管理工具
check_service_management_tools() {
  local -n deps_ref=$1
  
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    if ! command -v systemctl >/dev/null 2>&1; then
      deps_ref+=("systemctl")
    fi
  elif [ "$INIT_SYSTEM" = "openrc" ]; then
    if ! command -v rc-service >/dev/null 2>&1; then
      deps_ref+=("rc-service")
    fi
    if ! command -v openrc >/dev/null 2>&1; then
      deps_ref+=("openrc")
    fi
  fi
}

# 报告缺失的依赖项
report_missing_dependencies() {
  local deps=("$@")
  printf "错误: 缺少以下依赖项:\n" >&2
  for dep in "${deps[@]}"; do
    printf "  - %s\n" "$dep" >&2
  done
  printf "请安装缺少的依赖项后再运行此脚本。\n" >&2
}

# 解析命令行参数
parse_arguments() {
  ACTION="stable"  # 默认动作
  
  local i=0
  local args=("$@")
  while [ $i -lt $# ]; do
    arg="${args[$i]}"
    case "$arg" in
      "--stable"|"--beta")
        local version_action="${arg#--}"
        ACTION="$version_action"
        printf "设置动作: %s\n" "$ACTION" >&2
        ;;
      "--cn")
        USE_CN_MIRROR=true
        printf "启用中国镜像加速\n" >&2
        ;;
      "--reboot")
        AUTO_REBOOT=true
        printf "启用自动重启\n" >&2
        ;;
      "--backup")
        CREATE_BACKUP=true
        printf "启用备份功能\n" >&2
        ;;
      --backup=*)
        local count="${arg#--backup=}"
        CREATE_BACKUP=true
        BACKUP_COUNT="$count"
        
        # 验证 BACKUP_COUNT 是数字
        if ! [[ "$BACKUP_COUNT" =~ ^[0-9]+$ ]] || [ "$BACKUP_COUNT" -lt 1 ]; then
          printf "错误: --backup 参数必须是正整数\n" >&2
          exit 1
        fi
        printf "启用备份功能，保留 %s 个备份\n" "$BACKUP_COUNT" >&2
        ;;
      "--rollback")
        ROLLBACK=true
        printf "启用回滚功能\n" >&2
        ;;
      "-h"|"--help")
        SHOW_HELP=true
        ;;
      *)
        printf "忽略未知参数: %s\n" "$arg" >&2
        ;;
    esac
    i=$((i+1))
  done
}

# 显示帮助信息
show_help() {
  printf "%s\n" "Landscape Router 升级脚本"
  printf "%s\n" "用法: ./upgrade_landscape.sh [--stable|--beta] [--cn] [--reboot] [--backup[=N]] [--rollback]"
  printf "%s\n" "参数:"
  printf "%s\n" "  --stable       - 升级到最新稳定版（默认）"
  printf "%s\n" "  --beta         - 升级到最新 Beta 版"
  printf "%s\n" "  --cn           - 使用中国镜像加速（可选）"
  printf "%s\n" "  --reboot       - 升级完成后自动重启（可选）"
  printf "%s\n" "  --backup       - 升级前进行备份"
  printf "%s\n" "  --backup=N     - 升级前进行备份，并指定保留N个备份（默认stable保留1个，beta保留3个）"
  printf "%s\n" "  --rollback     - 回滚到之前的备份版本（交互式）"
  printf "%s\n" "  -h, --help     - 显示此帮助信息"
  printf "%s\n" ""
  printf "%s\n" "示例:"
  printf "%s\n" "  ./upgrade_landscape.sh                    # 升级到最新稳定版"
  printf "%s\n" "  ./upgrade_landscape.sh --stable           # 升级到最新稳定版"
  printf "%s\n" "  ./upgrade_landscape.sh --beta             # 升级到最新 Beta 版"
  printf "%s\n" "  ./upgrade_landscape.sh --stable --cn      # 使用中国镜像升级到最新稳定版"
  printf "%s\n" "  ./upgrade_landscape.sh --stable --reboot  # 升级到最新稳定版并自动重启"
  printf "%s\n" "  ./upgrade_landscape.sh --backup           # 升级前进行备份"
  printf "%s\n" "  ./upgrade_landscape.sh --backup=5         # 升级前进行备份，保留最近5个备份"
  printf "%s\n" "  ./upgrade_landscape.sh --rollback         # 回滚到之前的备份版本"
  printf "%s\n" "  ./upgrade_landscape.sh -h                 # 显示帮助信息"
  printf "%s\n" ""
  printf "%s\n" "当前系统初始化系统: $INIT_SYSTEM"
  printf "%s\n" "当前系统架构: $SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ]; then
    printf "%s\n" "系统类型: musl"
  else
    printf "%s\n" "系统类型: glibc"
  fi
}

# ========== 辅助函数 ==========

# 获取 Landscape Router 安装路径
get_landscape_dir() {
  if [ "$INIT_SYSTEM" = "systemd" ] && [ -f "/etc/systemd/system/landscape-router.service" ]; then
    get_landscape_dir_from_systemd
  elif [ "$INIT_SYSTEM" = "openrc" ] && [ -f "/etc/init.d/landscape-router" ]; then
    get_landscape_dir_from_openrc
  else
    handle_missing_service_file
    return 1
  fi
}

# 从systemd服务文件获取安装路径
get_landscape_dir_from_systemd() {
  local landscape_dir
  landscape_dir=$(grep -oP 'ExecStart=\K[^/]*(?=/landscape-webserver-)' /etc/systemd/system/landscape-router.service 2>/dev/null) || true
  if [ -z "$landscape_dir" ]; then
    printf "错误: 无法从 landscape-router.service 中提取安装路径，升级终止\n" >&2
    return 1
  fi
  printf "%s" "$landscape_dir"
}

# 从OpenRC启动脚本获取安装路径
get_landscape_dir_from_openrc() {
  local landscape_dir
  landscape_dir=$(grep -oP 'command=\K[^/]*(?=/landscape-webserver-)' /etc/init.d/landscape-router 2>/dev/null) || true
  if [ -z "$landscape_dir" ]; then
    printf "错误: 无法从 landscape-router 启动脚本中提取安装路径，升级终止\n" >&2
    return 1
  fi
  printf "%s" "$landscape_dir"
}

# 处理缺失的服务文件
handle_missing_service_file() {
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    printf "错误: 未找到 landscape-router.service 文件\n" >&2
  else
    printf "错误: 未找到 landscape-router 启动脚本\n" >&2
  fi
}

# 检查 Landscape Router 是否已安装
check_landscape_installed() {
  local landscape_dir="$1"
  local system_arch="$2"
  local use_musl="$3"
  
  local filename="landscape-webserver-$system_arch"
  if [ "$use_musl" = true ] && [ "$system_arch" = "x86_64" ]; then
    filename="landscape-webserver-x86_64-musl"
  fi
  
  if [ ! -f "$landscape_dir/$filename" ]; then
    log "错误: 未检测到已安装的 Landscape Router"
    return 1
  fi
  return 0
}

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
      setup_stable_download_url download_url "$filename"
      ;;
    "beta")
      # Beta版本从GitHub Actions下载
      download_url="github_actions"
      ;;
  esac
  
  echo "$download_url|$filename"
}

# 设置稳定版下载URL
setup_stable_download_url() {
  local -n url_ref=$1
  local filename="$2"
  
  if [ "$USE_CN_MIRROR" = true ]; then
    url_ref="https://ghfast.top/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$filename"
  else
    url_ref="https://github.com/ThisSeanZhang/landscape/releases/latest/download/$filename"
  fi
}

# 获取static.zip下载URL
get_static_download_url() {
  local version_type="$1"
  
  local download_url=""
  
  # 根据是否使用中国镜像设置下载URL
  case "$version_type" in
    "stable")
      setup_stable_static_download_url download_url
      ;;
    "beta")
      # Beta版本从GitHub Actions下载
      download_url="github_actions"
      ;;
  esac
  
  echo "$download_url"
}

# 设置稳定版static.zip下载URL
setup_stable_static_download_url() {
  local -n url_ref=$1
  
  if [ "$USE_CN_MIRROR" = true ]; then
    url_ref="https://ghfast.top/https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
  else
    url_ref="https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
  fi
}

# 查找包含index.html的目录
find_static_dir() {
  local search_dir="$1"
  
  # 先在当前目录查找
  if [ -f "$search_dir/index.html" ]; then
    echo "$search_dir"
    return 0
  fi
  
  # 在子目录中递归查找
  find_static_dir_recursive "$search_dir"
}

# 递归查找包含index.html的目录
find_static_dir_recursive() {
  local search_dir="$1"
  
  for dir in "$search_dir"/*/; do
    if [ -d "$dir" ]; then
      if [ -f "$dir/index.html" ]; then
        echo "$dir"
        return 0
      else
        # 递归查找子目录
        local result
        result=$(find_static_dir "$dir")
        if [ -n "$result" ]; then
          echo "$result"
          return 0
        fi
      fi
    fi
  done
  
  return 1
}

# 获取redirect_pkg_handler.sh下载URL
get_redirect_pkg_handler_script_url() {
  local version_type="$1"  # 未使用，但保留参数以保持接口一致性
  
  local download_url=""
  
  # redirect_pkg_handler.sh从相同地址下载，支持中国镜像加速，不需要GitHub token
  if [ "$USE_CN_MIRROR" = true ]; then
    download_url="https://ghfast.top/https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh"
  else
    download_url="https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh"
  fi
  
  echo "$download_url"
}

# 获取redirect_pkg_handler二进制文件下载URL
get_redirect_pkg_handler_binary_url() {
  local version_type="$1"
  local binary_name="$2"
  
  local download_url=""
  
  # 根据版本类型和是否使用中国镜像设置下载URL
  case "$version_type" in
    "stable")
      setup_stable_redirect_pkg_handler_download_url download_url "$binary_name"
      ;;
    "beta")
      # Beta版本从GitHub Actions下载
      download_url="github_actions"
      ;;
  esac
  
  echo "$download_url"
}

# 设置稳定版redirect_pkg_handler下载URL
setup_stable_redirect_pkg_handler_download_url() {
  local -n url_ref=$1
  local binary_name="$2"
  
  if [ "$USE_CN_MIRROR" = true ]; then
    url_ref="https://ghfast.top/https://github.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/releases/latest/download/$binary_name"
  else
    url_ref="https://github.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/releases/latest/download/$binary_name"
  fi
}

# 下载redirect_pkg_handler二进制文件
download_redirect_pkg_handler_binaries() {
  local version_type="$1"
  local temp_dir="$2"
  
  case "$SYSTEM_ARCH" in
    "x86_64")
      # 检查是否已存在x86_64版本
      if [ -f "$LANDSCAPE_DIR/redirect_pkg_handler-x86_64" ]; then
        # 获取x86_64版本下载URL
        local redirect_pkg_handler_x86_64_url
        redirect_pkg_handler_x86_64_url=$(get_redirect_pkg_handler_binary_url "$version_type" "redirect_pkg_handler-x86_64")
        # 下载x86_64版本
        if ! download_with_retry "$redirect_pkg_handler_x86_64_url" "$temp_dir/redirect_pkg_handler-x86_64"; then
          log "redirect_pkg_handler-x86_64 下载失败"
          return 1
        fi
      fi
      
      # 检查是否使用musl且已存在musl版本
      if [ "$USE_MUSL" = true ] && [ -f "$LANDSCAPE_DIR/redirect_pkg_handler-x86_64-musl" ]; then
        # 获取x86_64-musl版本下载URL
        local redirect_pkg_handler_x86_64_musl_url
        redirect_pkg_handler_x86_64_musl_url=$(get_redirect_pkg_handler_binary_url "$version_type" "redirect_pkg_handler-x86_64-musl")
        if ! download_with_retry "$redirect_pkg_handler_x86_64_musl_url" "$temp_dir/redirect_pkg_handler-x86_64-musl"; then
          log "redirect_pkg_handler-x86_64-musl 下载失败"
          return 1
        fi
      fi
      ;;
    "aarch64")
      # 检查是否已存在aarch64版本
      if [ -f "$LANDSCAPE_DIR/redirect_pkg_handler-aarch64" ]; then
        # 获取aarch64版本下载URL
        local redirect_pkg_handler_aarch64_url
        redirect_pkg_handler_aarch64_url=$(get_redirect_pkg_handler_binary_url "$version_type" "redirect_pkg_handler-aarch64")
        # 下载aarch64版本
        if ! download_with_retry "$redirect_pkg_handler_aarch64_url" "$temp_dir/redirect_pkg_handler-aarch64"; then
          log "redirect_pkg_handler-aarch64 下载失败"
          return 1
        fi
      fi
      ;;
  esac
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

# ========== 服务控制相关函数 ==========

# 控制Landscape服务的函数
control_landscape_service() {
  local action="$1"
  case "$action" in
    "start")
      start_landscape_service
      ;;
    "stop")
      stop_landscape_service
      ;;
    "restart")
      restart_landscape_service
      ;;
    *)
      log "未知的服务操作: $action"
      return 1
      ;;
  esac
}

# 启动Landscape服务
start_landscape_service() {
  log "正在启动 Landscape Router 服务..."
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl start landscape-router
  else
    rc-service landscape-router start
  fi
}

# 停止Landscape服务
stop_landscape_service() {
  log "正在停止 Landscape Router 服务..."
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl stop landscape-router
  else
    rc-service landscape-router stop
  fi
}

# 重启Landscape服务
restart_landscape_service() {
  log "正在重启 Landscape Router 服务..."
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl restart landscape-router
  else
    rc-service landscape-router restart
  fi
}

# ========== 备份相关函数 ==========

# 创建备份
create_backup() {
  local landscape_dir="$1"
  local version_type="$2"
  
  # 检查可用的压缩工具
  local compress_tool
  compress_tool=$(check_compression_tools "$landscape_dir") || return 1
  
  # 创建 backup 目录
  local backup_dir="$landscape_dir/backup"
  mkdir -p "$backup_dir"
  
  # 确定保留的备份数量
  local max_backups
  max_backups=$(determine_backup_count "$version_type")
  
  # 获取当前版本号
  local current_version
  current_version=$(get_current_version_for_backup "$landscape_dir")
  
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
  
  # 复制 landscape 目录内容到临时目录，排除 backup 目录
  copy_landscape_content_for_backup "$landscape_dir" "$temp_dir"
  
  # 根据可用工具进行压缩
  compress_backup_content "$temp_dir" "$backup_dir" "$backup_name" "$compress_tool" backup_file
  
  # 清理临时目录
  rm -rf "$temp_dir"
  
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

# 确定备份数量
determine_backup_count() {
  local version_type="$1"
  local max_backups=1
  
  if [ "$version_type" = "beta" ] && [ "$BACKUP_COUNT" -eq 0 ]; then
    max_backups=3
  elif [ "$BACKUP_COUNT" -gt 0 ]; then
    max_backups=$BACKUP_COUNT
  fi
  
  echo "$max_backups"
}

# 获取当前版本号用于备份
get_current_version_for_backup() {
  local landscape_dir="$1"
  local current_version=""
  local current_filename="landscape-webserver-$SYSTEM_ARCH"
  
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    current_filename="landscape-webserver-x86_64-musl"
  fi
  
  if [ -f "$landscape_dir/$current_filename" ]; then
    current_version=$("$landscape_dir/$current_filename" --version 2>/dev/null)
  fi
  
  # 如果无法获取版本号，则使用 unknown
  if [ -z "$current_version" ]; then
    current_version="unknown"
  fi
  
  echo "$current_version"
}

# 复制Landscape内容用于备份
copy_landscape_content_for_backup() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  # 复制 landscape 目录内容到临时目录，排除 backup 目录
  (cd "$landscape_dir" && find . -name "backup" -prune -o -print0 | pax -0 -rwd "$temp_dir")
}

# 压缩备份内容
compress_backup_content() {
  local temp_dir="$1"
  local backup_dir="$2"
  local backup_name="$3"
  local compress_tool="$4"
  local -n backup_file_ref=$5
  
  # 根据可用工具进行压缩
  case "$compress_tool" in
    "tar.gz")
      # 使用 tar + gzip 创建 .tar.gz 备份
      backup_file_ref="$backup_dir/${backup_name}.tar.gz"
      (cd "$temp_dir" && tar -czf "$backup_file_ref" .)
      ;;
    "tar.bz2")
      # 使用 tar + bzip2 创建 .tar.bz2 备份
      backup_file_ref="$backup_dir/${backup_name}.tar.bz2"
      (cd "$temp_dir" && tar -cjf "$backup_file_ref" .)
      ;;
    "tar.xz")
      # 使用 tar + xz 创建 .tar.xz 备份
      backup_file_ref="$backup_dir/${backup_name}.tar.xz"
      (cd "$temp_dir" && tar -cJf "$backup_file_ref" .)
      ;;
    "tar")
      # 使用单独的 tar 创建 .tar 备份
      backup_file_ref="$backup_dir/${backup_name}.tar"
      (cd "$temp_dir" && tar -cf "$backup_file_ref" .)
      ;;
    "gz")
      # 使用单独的 gzip 创建 .gz 备份
      backup_file_ref="$backup_dir/${backup_name}.tar.gz"
      (cd "$temp_dir" && tar -cf - . | gzip > "$backup_file_ref")
      ;;
    "bz2")
      # 使用单独的 bzip2 创建 .bz2 备份
      backup_file_ref="$backup_dir/${backup_name}.tar.bz2"
      (cd "$temp_dir" && tar -cf - . | bzip2 > "$backup_file_ref")
      ;;
    "xz")
      # 使用单独的 xz 创建 .xz 备份
      backup_file_ref="$backup_dir/${backup_name}.tar.xz"
      (cd "$temp_dir" && tar -cf - . | xz > "$backup_file_ref")
      ;;
    "zip")
      # 使用 zip 创建 .zip 备份
      backup_file_ref="$backup_dir/${backup_name}.zip"
      (cd "$temp_dir" && zip -rq "$backup_file_ref" .)
      ;;
  esac
}

# 清理旧备份
cleanup_old_backups() {
  local backup_dir="$1"
  local max_backups="$2"
  
  # 获取备份文件列表，按修改时间排序（最新的在前）
  local backup_files=()
  while IFS= read -r -d '' file; do
    backup_files+=("$file")
  done < <(find "$backup_dir" -name "landscape-*.tar.gz" -o -name "landscape-*.tar.bz2" -o -name "landscape-*.tar.xz" -o -name "landscape-*.tar" -o -name "landscape-*.gz" -o -name "landscape-*.bz2" -o -name "landscape-*.xz" -o -name "landscape-*.zip" -print0 | sort -rz)
  
  # 计算需要删除的文件数量
  local backup_count=${#backup_files[@]}
  local to_remove=$((backup_count - max_backups))
  
  # 删除旧的备份文件
  if [ $to_remove -gt 0 ]; then
    log "清理旧备份文件..."
    local i
    for ((i=backup_count-1; i>=max_backups; i--)); do
      if [ -f "${backup_files[$i]}" ]; then
        log "删除旧备份: $(basename "${backup_files[$i]}")"
        rm -f "${backup_files[$i]}"
      fi
    done
  fi
}

# 检查可用的压缩工具
check_compression_tools() {
  local landscape_dir="$1"
  
  # 检查可用的压缩工具 (按照 tar、gzip、bzip2、xz、zip 的顺序)
  local compress_tool=""
  if command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
    compress_tool="tar.gz"
  elif command -v tar >/dev/null 2>&1 && command -v bzip2 >/dev/null 2>&1; then
    compress_tool="tar.bz2"
  elif command -v tar >/dev/null 2>&1 && command -v xz >/dev/null 2>&1; then
    compress_tool="tar.xz"
  elif command -v tar >/dev/null 2>&1 && command -v gzip >/dev/null 2>&1; then
    compress_tool="tar"
  elif command -v gzip >/dev/null 2>&1; then
    compress_tool="gz"
  elif command -v bzip2 >/dev/null 2>&1; then
    compress_tool="bz2"
  elif command -v xz >/dev/null 2>&1; then
    compress_tool="xz"
  elif command -v zip >/dev/null 2>&1; then
    compress_tool="zip"
  else
    log "错误: 系统中未找到支持的压缩工具，请安装 tar、gzip、bzip2、xz 或 zip 中的一种"
    return 1
  fi
  
  log "使用压缩工具: $compress_tool"
  echo "$compress_tool"
}

# ========== 回滚相关函数 ==========

# 回滚功能
rollback_landscape() {
  local backup_dir="$LANDSCAPE_DIR/backup"
  
  # 验证备份目录存在
  validate_backup_directory "$backup_dir" || return 1
  
  # 查找所有备份文件
  local backup_files=()
  find_backup_files "$backup_dir" backup_files
  
  local backup_count=${#backup_files[@]}
  # 检查是否有备份文件
  if [ $backup_count -eq 0 ]; then
    log "错误: 未找到任何备份文件"
    return 1
  fi
  
  # 显示可用备份供用户选择
  display_backup_options backup_files
  
  # 获取用户选择
  local choice
  choice=$(get_user_backup_choice "$backup_count") || return 1
  
  local selected_backup="${backup_files[$((choice-1))]}"
  log "正在回滚到备份: $(basename "$selected_backup")"
  
  # 执行回滚操作
  execute_rollback "$selected_backup"
}

# 验证备份目录存在
validate_backup_directory() {
  local backup_dir="$1"
  
  if [ ! -d "$backup_dir" ]; then
    log "错误: 未找到备份目录 $backup_dir"
    return 1
  fi
}

# 查找备份文件
find_backup_files() {
  local backup_dir="$1"
  local -n files_ref=$2
  
  while IFS= read -r -d '' file; do
    files_ref+=("$file")
  done < <(find "$backup_dir" -name "landscape-*.tar.gz" -o -name "landscape-*.tar.bz2" -o -name "landscape-*.tar.xz" -o -name "landscape-*.tar" -o -name "landscape-*.gz" -o -name "landscape-*.bz2" -o -name "landscape-*.xz" -o -name "landscape-*.zip" -print0 | sort -rz)
}

# 显示备份选项
display_backup_options() {
  local -n files_ref=$1
  local backup_count=${#files_ref[@]}
  
  log "可用的备份文件:"
  local i
  for ((i=0; i<backup_count; i++)); do
    log "$((i+1)) $(basename "${files_ref[$i]}")"
  done
}

# 获取用户备份选择
get_user_backup_choice() {
  local backup_count="$1"
  local choice
  
  while true; do
    read -p "请选择要回滚到的备份版本 (1-${backup_count}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le $backup_count ]; then
      echo "$choice"
      return 0
    else
      log "无效选择，请输入 1 到 $backup_count 之间的数字"
    fi
  done
}

# 执行回滚操作
execute_rollback() {
  local selected_backup="$1"
  
  # 停止服务
  control_landscape_service "stop"
  
  # 根据文件扩展名确定解压方式并执行回滚
  local temp_dir
  temp_dir=$(create_temp_directory) || {
    log "错误: 无法创建临时目录"
    control_landscape_service "start"
    return 1
  }
  
  # 解压备份文件
  extract_backup_file "$selected_backup" "$temp_dir" || {
    rm -rf "$temp_dir"
    control_landscape_service "start"
    return 1
  }
  
  # 清空 landscape 目录（排除 backup 目录）
  clear_landscape_directory
  
  # 将备份内容复制回 landscape 目录
  restore_backup_content "$temp_dir"
  
  # 清理临时目录
  rm -rf "$temp_dir"
  
  log "回滚完成"
  
  # 处理重启
  handle_restart_after_rollback
}

# 解压备份文件
extract_backup_file() {
  local selected_backup="$1"
  local temp_dir="$2"
  
  # 根据文件扩展名确定解压方式
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
  elif [[ "$selected_backup" == *.gz ]]; then
    # 解压 .gz 文件
    (cd "$temp_dir" && gzip -dc "$selected_backup" | tar -xf -)
  elif [[ "$selected_backup" == *.bz2 ]]; then
    # 解压 .bz2 文件
    (cd "$temp_dir" && bzip2 -dc "$selected_backup" | tar -xf -)
  elif [[ "$selected_backup" == *.xz ]]; then
    # 解压 .xz 文件
    (cd "$temp_dir" && xz -dc "$selected_backup" | tar -xf -)
  elif [[ "$selected_backup" == *.zip ]]; then
    # 解压 .zip 文件
    (cd "$temp_dir" && unzip -q "$selected_backup")
  else
    log "错误: 不支持的备份文件格式"
    return 1
  fi
}

# 清空 landscape 目录
clear_landscape_directory() {
  # 清空 landscape 目录（排除 backup 目录）
  (cd "$LANDSCAPE_DIR" && find . -name "backup" -prune -o -exec rm -rf {} + 2>/dev/null || true)
}

# 恢复备份内容
restore_backup_content() {
  local temp_dir="$1"
  
  # 将备份内容复制回 landscape 目录
  (cd "$temp_dir" && find . -print0 | pax -0 -rwd "$LANDSCAPE_DIR")
}

# 处理回滚后的重启
handle_restart_after_rollback() {
  # 询问用户是否重启系统
  read -p "是否立即重启系统以应用回滚？(y/n): " -n 1 -r
  printf "\n"
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "正在重启系统以应用回滚..."
    reboot
  else
    log "正在启动 Landscape Router 服务..."
    control_landscape_service "start"
    log "回滚操作已成功完成，但系统尚未重启。"
    log "注意：Landscape Router 的某些功能可能无法正常工作。"
    log "重要提示：请在方便的时候尽快手动执行重启，以确保回滚完全生效。"
  fi
}

# ========== 下载相关函数 ==========

# 通用下载函数，支持wget和curl，优先使用wget
# 参数: URL, 输出文件路径
download_with_retry() {
  local url="$1"
  local output_file="$2"
  local max_retries=5
  local retry_count=0
  local download_tool=""
  
  # 检查是否有wget或curl
  check_download_tool download_tool
  
  # 处理GitHub Actions下载
  if [ "$url" = "github_actions" ]; then
    handle_github_actions_download "$output_file"
    return $?
  fi
  
  log "使用 $download_tool 下载: $url"
  
  # 执行下载重试循环
  execute_download_with_retry "$download_tool" "$url" "$output_file" "$max_retries"
}

# 检查可用的下载工具
check_download_tool() {
  local -n tool_ref=$1
  
  if command -v wget >/dev/null 2>&1; then
    tool_ref="wget"
  elif command -v curl >/dev/null 2>&1; then
    tool_ref="curl"
  else
    log "错误: 系统中未找到 wget 或 curl 命令，请安装其中一个再继续"
    return 1
  fi
}

# 处理从GitHub Actions下载
handle_github_actions_download() {
  local output_file="$1"
  log "从GitHub Actions下载Beta版本文件"
  download_from_github_actions "$output_file"
  return $?
}

# 执行下载重试循环
execute_download_with_retry() {
  local download_tool="$1"
  local url="$2"
  local output_file="$3"
  local max_retries="$4"
  local retry_count=0
  
  # 重试循环
  while [ $retry_count -lt $max_retries ]; do
    case "$download_tool" in
      "wget")
        if wget -O "$output_file" "$url"; then
          log "下载成功"
          return 0
        fi
        ;;
      "curl")
        if curl -L -o "$output_file" "$url"; then
          log "下载成功"
          return 0
        fi
        ;;
    esac
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      log "下载失败，$retry_count 秒后进行第 $retry_count 次重试..."
      sleep $retry_count
    fi
  done
  
  log "错误: 下载失败，已重试 $max_retries 次"
  return 1
}

# 从GitHub Actions下载Beta版本文件
download_from_github_actions() {
  local output_file="$1"
  local file_name=$(basename "$output_file")
  
  # 读取GitHub Token
  read_github_token
  
  # 根据文件名确定artifact名称
  local artifact_name=""
  determine_artifact_name "$file_name" artifact_name || return 1
  
  # 处理特殊文件 redirect_pkg_handler.sh
  if [ "$artifact_name" = "redirect_pkg_handler.sh" ]; then
    handle_redirect_pkg_handler_download "$output_file"
    return $?
  fi
  
  log "正在从GitHub Actions下载 $artifact_name..."
  
  # 获取最新的工作流运行ID
  local workflow_run_id=""
  local auth_header=""
  prepare_auth_header auth_header
  
  # 使用GitHub API获取最新的工作流运行
  fetch_latest_workflow_run "$auth_header" workflow_run_id || return 1
  
  log "找到最新的工作流运行ID: $workflow_run_id"
  
  # 获取artifact下载URL
  local artifacts_url="https://api.github.com/repos/ThisSeanZhang/landscape/actions/runs/$workflow_run_id/artifacts"
  local artifacts_response=""
  
  fetch_artifacts_response "$auth_header" "$artifacts_url" artifacts_response || return 1
  
  # 查找并下载指定artifact
  find_and_download_artifact "$artifacts_response" "$artifact_name" "$output_file"
}

# 读取GitHub Token
read_github_token() {
  local token_file="$LANDSCAPE_DIR/github_token"
  if [ -f "$token_file" ]; then
    GITHUB_TOKEN=$(cat "$token_file")
    log "已从 $token_file 读取GitHub Token"
  else
    log "警告: 未找到GitHub Token文件 $token_file，可能无法下载Beta版本"
  fi
}

# 确定artifact名称
determine_artifact_name() {
  local file_name="$1"
  local -n artifact_name_ref=$2
  
  case "$file_name" in
    "landscape-webserver-x86_64")
      artifact_name_ref="landscape-webserver-x86_64"
      ;;
    "landscape-webserver-x86_64-musl")
      artifact_name_ref="landscape-webserver-x86_64-musl"
      ;;
    "landscape-webserver-aarch64")
      artifact_name_ref="landscape-webserver-aarch64"
      ;;
    "static.zip")
      artifact_name_ref="static"
      ;;
    "redirect_pkg_handler-x86_64")
      artifact_name_ref="redirect_pkg_handler-x86_64"
      ;;
    "redirect_pkg_handler-x86_64-musl")
      artifact_name_ref="redirect_pkg_handler-x86_64-musl"
      ;;
    "redirect_pkg_handler-aarch64")
      artifact_name_ref="redirect_pkg_handler-aarch64"
      ;;
    "redirect_pkg_handler.sh")
      artifact_name_ref="redirect_pkg_handler.sh"
      ;;
    *)
      log "错误: 未知的文件类型 $file_name"
      return 1
      ;;
  esac
}

# 处理 redirect_pkg_handler.sh 下载
handle_redirect_pkg_handler_download() {
  local output_file="$1"
  log "下载 redirect_pkg_handler.sh..."
  # redirect_pkg_handler.sh不需要token，直接从GitHub原始链接下载
  if ! download_with_retry_raw "https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh" "$output_file"; then
    log "redirect_pkg_handler.sh 下载失败"
    return 1
  fi
  return 0
}

# 准备认证头
prepare_auth_header() {
  local -n header_ref=$1
  
  if [ -n "$GITHUB_TOKEN" ]; then
    header_ref="Authorization: Bearer $GITHUB_TOKEN"
  else
    header_ref="Authorization: Bearer \${GITHUB_TOKEN}"
  fi
}

# 获取最新的工作流运行
fetch_latest_workflow_run() {
  local auth_header="$1"
  local -n run_id_ref=$2
  
  local api_url="https://api.github.com/repos/ThisSeanZhang/landscape/actions/runs?event=push&status=success&per_page=1"
  local response=""
  
  if command -v curl >/dev/null 2>&1; then
    response=$(curl -s -H "Accept: application/vnd.github.v3+json" -H "$auth_header" "$api_url")
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$GITHUB_TOKEN" ]; then
      response=$(wget -qO- --header="Accept: application/vnd.github.v3+json" --header="$auth_header" "$api_url")
    else
      response=$(wget -qO- --header="Accept: application/vnd.github.v3+json" "$api_url")
    fi
  else
    log "错误: 系统中未找到 curl 或 wget 命令"
    return 1
  fi
  
  # 解析工作流运行ID
  run_id_ref=$(echo "$response" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
  
  if [ -z "$run_id_ref" ]; then
    log "错误: 无法获取工作流运行ID"
    log "API响应: $response"
    return 1
  fi
}

# 获取artifacts响应
fetch_artifacts_response() {
  local auth_header="$1"
  local artifacts_url="$2"
  local -n response_ref=$3
  
  if command -v curl >/dev/null 2>&1; then
    response_ref=$(curl -s -H "Accept: application/vnd.github.v3+json" -H "$auth_header" "$artifacts_url")
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$GITHUB_TOKEN" ]; then
      response_ref=$(wget -qO- --header="Accept: application/vnd.github.v3+json" --header="$auth_header" "$artifacts_url")
    else
      response_ref=$(wget -qO- --header="Accept: application/vnd.github.v3+json" "$artifacts_url")
    fi
  fi
}

# 查找并下载指定artifact
find_and_download_artifact() {
  local artifacts_response="$1"
  local artifact_name="$2"
  local output_file="$3"
  
  # 查找指定artifact
  local artifact_id=""
  local artifact_url=""
  local artifact_size=""
  
  # 解析artifact信息
  echo "$artifacts_response" | grep -A 10 -B 10 "\"name\": *\"$artifact_name\"" | {
    read -r line
    while [ -n "$line" ]; do
      if echo "$line" | grep -q '"id":'; then
        artifact_id=$(echo "$line" | grep -o '"id":[0-9]*' | cut -d: -f2)
      elif echo "$line" | grep -q '"archive_download_url":'; then
        artifact_url=$(echo "$line" | grep -o '"archive_download_url":"[^"]*"' | cut -d: -f2- | tr -d '"')
      elif echo "$line" | grep -q '"size_in_bytes":'; then
        artifact_size=$(echo "$line" | grep -o '"size_in_bytes":[0-9]*' | cut -d: -f2)
      fi
      read -r line
    done
    
    if [ -z "$artifact_id" ] || [ -z "$artifact_url" ]; then
      log "错误: 无法找到artifact $artifact_name"
      return 1
    fi
    
    log "找到artifact: $artifact_name (ID: $artifact_id, Size: $artifact_size bytes)"
    
    # 下载artifact
    download_artifact "$artifact_name" "$artifact_url" "$auth_header" "$output_file"
  }
  
  # 返回子shell的退出状态
  return $?
}

# 下载artifact
download_artifact() {
  local artifact_name="$1"
  local artifact_url="$2"
  local auth_header="$3"
  local output_file="$4"
  
  log "正在下载artifact..."
  local temp_zip="/tmp/${artifact_name}_artifact.zip"
  
  if command -v curl >/dev/null 2>&1; then
    if ! curl -L -H "Accept: application/vnd.github.v3+json" -H "$auth_header" -o "$temp_zip" "$artifact_url"; then
      log "错误: 下载artifact失败"
      rm -f "$temp_zip"
      return 1
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$GITHUB_TOKEN" ]; then
      if ! wget -O "$temp_zip" --header="Accept: application/vnd.github.v3+json" --header="$auth_header" "$artifact_url"; then
        log "错误: 下载artifact失败"
        rm -f "$temp_zip"
        return 1
      fi
    else
      if ! wget -O "$temp_zip" --header="Accept: application/vnd.github.v3+json" "$artifact_url"; then
        log "错误: 下载artifact失败"
        rm -f "$temp_zip"
        return 1
      fi
    fi
  else
    log "错误: 系统中未找到 curl 或 wget 命令"
    rm -f "$temp_zip"
    return 1
  fi
  
  # 解压并处理artifact
  extract_and_process_artifact "$artifact_name" "$temp_zip" "$output_file"
}

# 解压并处理artifact
extract_and_process_artifact() {
  local artifact_name="$1"
  local temp_zip="$2"
  local output_file="$3"
  
  # 解压artifact
  log "正在解压artifact..."
  local temp_dir="/tmp/${artifact_name}_extract"
  rm -rf "$temp_dir"
  mkdir -p "$temp_dir"
  
  if ! unzip -q "$temp_zip" -d "$temp_dir"; then
    log "错误: 解压artifact失败"
    rm -f "$temp_zip"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # 查找并复制目标文件
  local extracted_file=""
  find_target_file "$artifact_name" "$temp_dir" extracted_file
  
  if [ -z "$extracted_file" ] || [ ! -f "$extracted_file" ]; then
    log "错误: 在解压文件中未找到目标文件 $artifact_name"
    rm -f "$temp_zip"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # 复制文件到输出位置
  if ! cp "$extracted_file" "$output_file"; then
    log "错误: 复制文件失败"
    rm -f "$temp_zip"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # 清理临时文件
  rm -f "$temp_zip"
  rm -rf "$temp_dir"
  
  log "成功下载并解压 $artifact_name"
  return 0
}

# 查找目标文件
find_target_file() {
  local artifact_name="$1"
  local temp_dir="$2"
  local -n file_ref=$3
  
  if [ "$artifact_name" = "static" ]; then
    file_ref="$temp_dir/static.zip"
  else
    file_ref="$temp_dir/$artifact_name"
  fi
  
  if [ ! -f "$file_ref" ]; then
    # 尝试在子目录中查找
    file_ref=$(find "$temp_dir" -name "$artifact_name" -type f | head -1)
    if [ -z "$file_ref" ] && [ "$artifact_name" = "static" ]; then
      file_ref=$(find "$temp_dir" -name "static.zip" -type f | head -1)
    fi
  fi
}

# 直接从URL下载文件（用于redirect_pkg_handler.sh）
download_with_retry_raw() {
  local url="$1"
  local output_file="$2"
  local max_retries=5
  local retry_count=0
  local download_tool=""
  
  # 检查是否有wget或curl
  check_download_tool download_tool || return 1
  
  log "使用 $download_tool 从原始链接下载: $url"
  
  # 执行下载重试循环
  execute_download_with_retry "$download_tool" "$url" "$output_file" "$max_retries"
}

# 获取redirect_pkg_handler.sh下载URL
get_redirect_pkg_handler_script_url() {
  local download_url=""
  
  # redirect_pkg_handler.sh从相同地址下载，支持中国镜像加速，不需要GitHub token
  if [ "$USE_CN_MIRROR" = true ]; then
    download_url="https://ghfast.top/https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh"
  else
    download_url="https://raw.githubusercontent.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/main/redirect_pkg_handler.sh"
  fi
  
  echo "$download_url"
}

# 获取redirect_pkg_handler二进制文件下载URL
get_redirect_pkg_handler_binary_url() {
  local version_type="$1"
  local binary_name="$2"
  
  local download_url=""
  
  # 根据版本类型和是否使用中国镜像设置下载URL
  case "$version_type" in
    "stable")
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghfast.top/https://github.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/releases/latest/download/$binary_name"
      else
        download_url="https://github.com/CyberRookie-X/Install_landscape_on_debian12_and_manage_compose_by_dpanel/releases/latest/download/$binary_name"
      fi
      ;;
    "beta")
      # Beta版本从GitHub Actions下载
      download_url="github_actions"
      ;;
  esac
  
  echo "$download_url"
}

# ========== 升级相关函数 ==========

# 通用升级函数
upgrade_landscape_version() {
  local version_type="$1"  # stable, beta
  local display_name="$2"  # 显示名称
  local landscape_dir="$3" # 安装目录
  
  display_upgrade_start_message "$version_type" "$display_name"
  
  # 检查是否已安装
  check_landscape_installed "$landscape_dir" "$SYSTEM_ARCH" "$USE_MUSL" || exit 1
  
  # 如果需要创建备份
  handle_backup_if_needed "$landscape_dir" "$version_type"
  
  # 获取当前版本信息（仅适用于stable版本）
  local current_version=""
  if [ "$version_type" = "stable" ]; then
    current_version=$(get_current_landscape_version "$landscape_dir")
    log "当前版本: $current_version"
  fi
  
  # 创建临时目录并下载文件
  local temp_dir=""
  temp_dir=$(create_temp_directory) || exit 1
  
  log "下载文件到临时目录: $temp_dir"
  
  # 确保下载目录存在
  mkdir -p "$temp_dir"
  
  # 下载必要文件
  download_required_files "$version_type" "$temp_dir" || {
    rm -rf "$temp_dir"
    exit 1
  }
  
  # 对于稳定版，检查是否降级
  if [ "$version_type" = "stable" ]; then
    handle_stable_version_check "$landscape_dir" "$temp_dir" "$current_version"
  fi
  
  # 停止服务并执行升级
  control_landscape_service "stop"
  
  # 设置执行权限
  set_executable_permissions "$temp_dir"
  
  # 执行文件替换
  perform_file_replacement "$landscape_dir" "$temp_dir"
  
  # 清理临时目录
  rm -rf "$temp_dir"
  
  log "Landscape Router $display_name 升级完成"
  
  # 处理重启
  handle_restart_after_upgrade
}

# 显示升级开始消息
display_upgrade_start_message() {
  local version_type="$1"
  local display_name="$2"
  
  if [ "$USE_CN_MIRROR" = true ]; then
    log "正在使用中国镜像加速升级 Landscape Router 到最新 $display_name..."
  else
    log "正在升级 Landscape Router 到最新 $display_name..."
  fi
}

# 处理备份（如果需要）
handle_backup_if_needed() {
  local landscape_dir="$1"
  local version_type="$2"
  
  if [ "$CREATE_BACKUP" = true ]; then
    log "正在创建备份..."
    create_backup "$landscape_dir" "$version_type" || exit 1
  fi
}

# 获取当前Landscape版本
get_current_landscape_version() {
  local landscape_dir="$1"
  local current_filename="landscape-webserver-$SYSTEM_ARCH"
  
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    current_filename="landscape-webserver-x86_64-musl"
  fi
  
  if [ -f "$landscape_dir/$current_filename" ]; then
    "$landscape_dir/$current_filename" --version 2>/dev/null
  fi
}

# 创建临时目录
create_temp_directory() {
  local temp_dir
  temp_dir=$(mktemp -d) || {
    log "错误: 无法创建临时目录"
    return 1
  }
  echo "$temp_dir"
}

# 下载必要文件
download_required_files() {
  local version_type="$1"
  local temp_dir="$2"
  
  # 下载可执行文件
  download_executable_file "$version_type" "$temp_dir" || return 1
  
  # 下载static.zip
  download_static_zip "$version_type" "$temp_dir" || return 1
  
  # 解压static.zip到statictmp目录
  extract_static_zip "$temp_dir" || return 1
  
  # 下载redirect_pkg_handler相关文件
  download_redirect_pkg_handler_files "$version_type" "$temp_dir" || return 1
}

# 下载可执行文件
download_executable_file() {
  local version_type="$1"
  local temp_dir="$2"
  
  local download_info
  download_info=$(get_download_info "$version_type")
  local download_url=$(echo "$download_info" | cut -d'|' -f1)
  local filename=$(echo "$download_info" | cut -d'|' -f2)
  
  if ! download_with_retry "$download_url" "$temp_dir/$filename"; then
    log "可执行文件下载失败"
    return 1
  fi
}

# 下载static.zip
download_static_zip() {
  local version_type="$1"
  local temp_dir="$2"
  
  local static_download_url
  static_download_url=$(get_static_download_url "$version_type")
  
  log "正在下载 static.zip..."
  if ! download_with_retry "$static_download_url" "$temp_dir/static.zip"; then
    log "static.zip 下载失败"
    return 1
  fi
}

# 解压static.zip
extract_static_zip() {
  local temp_dir="$1"
  
  log "正在解压 static.zip..."
  mkdir -p "$temp_dir/statictmp"
  if ! unzip "$temp_dir/static.zip" -d "$temp_dir/statictmp"; then
    log "static.zip 解压失败"
    return 1
  fi
}

# 下载redirect_pkg_handler相关文件
download_redirect_pkg_handler_files() {
  local version_type="$1"
  local temp_dir="$2"
  
  log "正在下载 redirect_pkg_handler 相关文件..."
  
  # 下载redirect_pkg_handler.sh
  local redirect_pkg_handler_script_url
  redirect_pkg_handler_script_url=$(get_redirect_pkg_handler_script_url "$version_type")
  if ! download_with_retry "$redirect_pkg_handler_script_url" "$temp_dir/redirect_pkg_handler.sh"; then
    log "redirect_pkg_handler.sh 下载失败"
    return 1
  fi
  
  # 根据安装目录中已有的文件决定下载哪些redirect_pkg_handler二进制文件
  download_redirect_pkg_handler_binaries "$version_type" "$temp_dir"
}

# 处理稳定版版本检查
handle_stable_version_check() {
  local landscape_dir="$1"
  local temp_dir="$2"
  local current_version="$3"
  
  # 为新下载的文件添加执行权限以获取版本信息
  local filename="landscape-webserver-$SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    filename="landscape-webserver-x86_64-musl"
  fi
  
  chmod +x "$temp_dir/$filename"
  
  # 获取新版本信息
  local new_version=""
  new_version=$("$temp_dir/$filename" --version 2>/dev/null)
  log "最新版本: $new_version"
  
  # 比较版本，如果新版本小于等于当前版本，则不升级
  if [ -n "$current_version" ] && [ -n "$new_version" ]; then
    # 简单的版本比较（假设版本格式为 vX.Y.Z）
    # 使用 sort -V 进行版本比较
    local version_comparison=$(printf "%s\n%s" "$current_version" "$new_version" | sort -V | head -n1)
    if [ "$version_comparison" = "$new_version" ] && [ "$current_version" != "$new_version" ]; then
      log "检测到新版本 $new_version 比当前版本 $current_version 更旧，为防止降级，取消升级"
      return 1
    elif [ "$current_version" = "$new_version" ]; then
      log "当前已是最新稳定版，无需升级"
      return 1
    fi
  fi
}

# 设置执行权限
set_executable_permissions() {
  local temp_dir="$1"
  
  # 获取可执行文件名
  local filename="landscape-webserver-$SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    filename="landscape-webserver-x86_64-musl"
  fi
  
  # 设置下载文件的执行权限
  chmod +x "$temp_dir/$filename"
  
  # 为redirect_pkg_handler相关文件添加执行权限
  chmod +x "$temp_dir/redirect_pkg_handler.sh"
  
  # 根据架构为对应的redirect_pkg_handler二进制文件添加执行权限
  set_redirect_pkg_handler_permissions "$temp_dir"
}

# 设置redirect_pkg_handler权限
set_redirect_pkg_handler_permissions() {
  local temp_dir="$1"
  
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
      ;;
  esac
}

# 执行文件替换
perform_file_replacement() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  # 获取可执行文件名
  local filename="landscape-webserver-$SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    filename="landscape-webserver-x86_64-musl"
  fi
  
  # 备份并替换可执行文件
  backup_and_replace_executable "$landscape_dir" "$temp_dir" "$filename"
  
  # 替换静态文件目录
  replace_static_files "$landscape_dir" "$temp_dir"
  
  # 替换redirect_pkg_handler相关文件
  replace_redirect_pkg_handler_files "$landscape_dir" "$temp_dir"
}

# 备份并替换可执行文件
backup_and_replace_executable() {
  local landscape_dir="$1"
  local temp_dir="$2"
  local filename="$3"
  
  # 备份旧文件
  local backup_file="$landscape_dir/$filename.bak"
  if [ -f "$landscape_dir/$filename" ]; then
    if ! mv "$landscape_dir/$filename" "$backup_file"; then
      log "文件备份失败"
      control_landscape_service "start"
      return 1
    fi
  fi
  
  # 替换可执行文件
  if ! mv "$temp_dir/$filename" "$landscape_dir/$filename"; then
    log "文件替换失败"
    # 尝试恢复备份
    if [ -f "$backup_file" ]; then
      mv "$backup_file" "$landscape_dir/$filename"
    fi
    control_landscape_service "start"
    return 1
  fi
  
  # 删除备份文件
  if [ -f "$backup_file" ]; then
    rm -f "$backup_file"
  fi
}

# 替换静态文件
replace_static_files() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  log "正在更新 UI 静态文件..."
  rm -rf "$landscape_dir/static"
  
  # 在statictmp目录中查找包含index.html的目录
  log "正在查找静态文件目录..."
  local static_source_dir
  static_source_dir=$(find_static_dir "$temp_dir/statictmp")
  if [ -z "$static_source_dir" ]; then
    log "未找到包含 index.html 的目录"
    return 1
  fi
  
  if ! cp -r "$static_source_dir" "$landscape_dir/static"; then
    log "UI 静态文件替换失败"
    log "UI 可能仍为旧版本，或无法使用"
    log "后端升级失败，前端升级成功"
    log "建议您手动替换 UI 静态文件，并重启 Landscape Router"
    log "不使用 UI 时，Landscape Router 仍可正常工作"
    log "现尝试为您启动新版 Landscape Router..."
    return 1
  fi
}

# 替换redirect_pkg_handler相关文件
replace_redirect_pkg_handler_files() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  log "正在更新 redirect_pkg_handler 相关文件..."
  
  # 替换redirect_pkg_handler.sh（如果下载成功）
  replace_redirect_pkg_handler_script "$landscape_dir" "$temp_dir"
  
  # 根据架构替换对应的redirect_pkg_handler二进制文件
  replace_redirect_pkg_handler_binaries "$landscape_dir" "$temp_dir"
}

# 替换redirect_pkg_handler.sh
replace_redirect_pkg_handler_script() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  if [ -f "$temp_dir/redirect_pkg_handler.sh" ]; then
    if [ -f "$landscape_dir/redirect_pkg_handler.sh" ]; then
      mv "$landscape_dir/redirect_pkg_handler.sh" "$landscape_dir/redirect_pkg_handler.sh.bak"
    fi
    
    if ! mv "$temp_dir/redirect_pkg_handler.sh" "$landscape_dir/redirect_pkg_handler.sh"; then
      log "redirect_pkg_handler.sh 替换失败"
      # 恢复备份
      if [ -f "$landscape_dir/redirect_pkg_handler.sh.bak" ]; then
        mv "$landscape_dir/redirect_pkg_handler.sh.bak" "$landscape_dir/redirect_pkg_handler.sh"
      fi
    else
      # 删除备份
      if [ -f "$landscape_dir/redirect_pkg_handler.sh.bak" ]; then
        rm -f "$landscape_dir/redirect_pkg_handler.sh.bak"
      fi
      # 确保替换后的文件有执行权限
      chmod +x "$landscape_dir/redirect_pkg_handler.sh"
    fi
  fi
}

# 替换redirect_pkg_handler二进制文件
replace_redirect_pkg_handler_binaries() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  case "$SYSTEM_ARCH" in
    "x86_64")
      # 替换x86_64版本（如果下载成功）
      replace_redirect_pkg_handler_x86_64 "$landscape_dir" "$temp_dir"
      
      # 如果使用musl，也替换musl版本（如果下载成功）
      if [ "$USE_MUSL" = true ]; then
        replace_redirect_pkg_handler_x86_64_musl "$landscape_dir" "$temp_dir"
      fi
      ;;
    "aarch64")
      # 替换aarch64版本（如果下载成功）
      replace_redirect_pkg_handler_aarch64 "$landscape_dir" "$temp_dir"
      ;;
  esac
}

# 替换redirect_pkg_handler x86_64版本
replace_redirect_pkg_handler_x86_64() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  if [ -f "$temp_dir/redirect_pkg_handler-x86_64" ]; then
    if [ -f "$landscape_dir/redirect_pkg_handler-x86_64" ]; then
      mv "$landscape_dir/redirect_pkg_handler-x86_64" "$landscape_dir/redirect_pkg_handler-x86_64.bak"
    fi
    
    if ! mv "$temp_dir/redirect_pkg_handler-x86_64" "$landscape_dir/redirect_pkg_handler-x86_64"; then
      log "redirect_pkg_handler-x86_64 替换失败"
      # 恢复备份
      if [ -f "$landscape_dir/redirect_pkg_handler-x86_64.bak" ]; then
        mv "$landscape_dir/redirect_pkg_handler-x86_64.bak" "$landscape_dir/redirect_pkg_handler-x86_64"
      fi
    else
      # 删除备份
      if [ -f "$landscape_dir/redirect_pkg_handler-x86_64.bak" ]; then
        rm -f "$landscape_dir/redirect_pkg_handler-x86_64.bak"
      fi
      # 确保替换后的文件有执行权限
      chmod +x "$landscape_dir/redirect_pkg_handler-x86_64"
    fi
  fi
}

# 替换redirect_pkg_handler x86_64 musl版本
replace_redirect_pkg_handler_x86_64_musl() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  if [ -f "$temp_dir/redirect_pkg_handler-x86_64-musl" ]; then
    if [ -f "$landscape_dir/redirect_pkg_handler-x86_64-musl" ]; then
      mv "$landscape_dir/redirect_pkg_handler-x86_64-musl" "$landscape_dir/redirect_pkg_handler-x86_64-musl.bak"
    fi
    
    if ! mv "$temp_dir/redirect_pkg_handler-x86_64-musl" "$landscape_dir/redirect_pkg_handler-x86_64-musl"; then
      log "redirect_pkg_handler-x86_64-musl 替换失败"
      # 恢复备份
      if [ -f "$landscape_dir/redirect_pkg_handler-x86_64-musl.bak" ]; then
        mv "$landscape_dir/redirect_pkg_handler-x86_64-musl.bak" "$landscape_dir/redirect_pkg_handler-x86_64-musl"
      fi
    else
      # 删除备份
      if [ -f "$landscape_dir/redirect_pkg_handler-x86_64-musl.bak" ]; then
        rm -f "$landscape_dir/redirect_pkg_handler-x86_64-musl.bak"
      fi
      # 确保替换后的文件有执行权限
      chmod +x "$landscape_dir/redirect_pkg_handler-x86_64-musl"
    fi
  fi
}

# 替换redirect_pkg_handler aarch64版本
replace_redirect_pkg_handler_aarch64() {
  local landscape_dir="$1"
  local temp_dir="$2"
  
  if [ -f "$temp_dir/redirect_pkg_handler-aarch64" ]; then
    if [ -f "$landscape_dir/redirect_pkg_handler-aarch64" ]; then
      mv "$landscape_dir/redirect_pkg_handler-aarch64" "$landscape_dir/redirect_pkg_handler-aarch64.bak"
    fi
    
    if ! mv "$temp_dir/redirect_pkg_handler-aarch64" "$landscape_dir/redirect_pkg_handler-aarch64"; then
      log "redirect_pkg_handler-aarch64 替换失败"
      # 恢复备份
      if [ -f "$landscape_dir/redirect_pkg_handler-aarch64.bak" ]; then
        mv "$landscape_dir/redirect_pkg_handler-aarch64.bak" "$landscape_dir/redirect_pkg_handler-aarch64"
      fi
    else
      # 删除备份
      if [ -f "$landscape_dir/redirect_pkg_handler-aarch64.bak" ]; then
        rm -f "$landscape_dir/redirect_pkg_handler-aarch64.bak"
      fi
      # 确保替换后的文件有执行权限
      chmod +x "$landscape_dir/redirect_pkg_handler-aarch64"
    fi
  fi
}

# 处理升级后的重启
handle_restart_after_upgrade() {
  # 根据AUTO_REBOOT变量决定是否自动重启
  if [ "$AUTO_REBOOT" = true ]; then
    log "正在重启系统以应用更新..."
    reboot
  else
    control_landscape_service "start"
    log "升级已完成，但系统尚未重启。"
    log "Landscape Router已启动，但部分无法正常使用。"
    log "建议您在适当的时候手动重启系统。"
  fi
}

# 升级 Landscape Router 稳定版
upgrade_stable() {
  upgrade_landscape_version "stable" "稳定版" "$1"
}

# 升级到 Beta 版本
upgrade_beta() {
  upgrade_landscape_version "beta" "beta版" "$1"
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

# 执行主函数
main "$@"
