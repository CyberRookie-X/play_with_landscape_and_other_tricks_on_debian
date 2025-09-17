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
  
  # 检查是否是回滚操作
  if [ "$ROLLBACK" = true ]; then
    # 初始化回滚日志
    init_log
    log "Landscape Router 回滚脚本开始执行"
    log "检测到 Landscape Router 安装目录: $LANDSCAPE_DIR"
    log "当前版本: $CURRENT_VERSION"
    rollback_landscape
    exit 0
  fi
  
  # 然后才是日志初始化等等其他的
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
  local max_logs=16
  local to_remove=$((log_count - max_logs))
  
  # 删除旧的日志文件
  if [ $to_remove -gt 0 ]; then
    local i
    for ((i=log_count-1; i>=max_logs; i--)); do
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
  SYSTEM_ARCH=$(uname -m)
  if [ "$SYSTEM_ARCH" != "x86_64" ] && [ "$SYSTEM_ARCH" != "aarch64" ]; then
    printf "不支持的系统架构: %s\n" "$SYSTEM_ARCH" >&2
    exit 1
  fi

  # 检查是否使用 musl libc
  if ldd --version 2>&1 | grep -q musl; then
    USE_MUSL=true
  fi

  # 检查系统使用的初始化系统 (systemd 或 OpenRC)
  if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
  else
    printf "错误: 不支持的初始化系统，需要 systemd 或 OpenRC\n" >&2
    exit 1
  fi
  
  # 检查依赖项
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
    printf "错误: 缺少以下依赖项:\n" >&2
    for dep in "${missing_deps[@]}"; do
      printf "  - %s\n" "$dep" >&2
    done
    printf "请安装缺少的依赖项后再运行此脚本。\n" >&2
    exit 1
  fi
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
        ACTION="${arg#--}"
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
        CREATE_BACKUP=true
        BACKUP_COUNT="${arg#--backup=}"
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
        # 忽略未知参数或显示帮助信息
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

# 获取 Landscape Router 安装路径
get_landscape_dir() {
  if [ "$INIT_SYSTEM" = "systemd" ] && [ -f "/etc/systemd/system/landscape-router.service" ]; then
    local landscape_dir
    landscape_dir=$(grep -oP 'ExecStart=\K[^/]*(?=/landscape-webserver-)' /etc/systemd/system/landscape-router.service 2>/dev/null) || true
    if [ -z "$landscape_dir" ]; then
      printf "错误: 无法从 landscape-router.service 中提取安装路径，升级终止\n" >&2
      return 1
    fi
    printf "%s" "$landscape_dir"
  elif [ "$INIT_SYSTEM" = "openrc" ] && [ -f "/etc/init.d/landscape-router" ]; then
    # 对于 OpenRC，从启动脚本中提取安装路径
    local landscape_dir
    landscape_dir=$(grep -oP 'command=\K[^/]*(?=/landscape-webserver-)' /etc/init.d/landscape-router 2>/dev/null) || true
    if [ -z "$landscape_dir" ]; then
      printf "错误: 无法从 landscape-router 启动脚本中提取安装路径，升级终止\n" >&2
      return 1
    fi
    printf "%s" "$landscape_dir"
  else
    if [ "$INIT_SYSTEM" = "systemd" ]; then
      printf "错误: 未找到 landscape-router.service 文件\n" >&2
    else
      printf "错误: 未找到 landscape-router 启动脚本\n" >&2
    fi
    return 1
  fi
}

# 检查 Landscape Router 是否已安装
check_landscape_installed() {
  local filename="landscape-webserver-$SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    filename="landscape-webserver-x86_64-musl"
  fi
  
  if [ ! -f "$1/$filename" ]; then
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
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghfast.top/https://github.com/ThisSeanZhang/landscape/releases/latest/download/$filename"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/$filename"
      fi
      ;;
    "beta")
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghfast.top/https://github.com/ThisSeanZhang/landscape/releases/download/prerelease/$filename"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/download/prerelease/$filename"
      fi
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
        download_url="https://ghfast.top/https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/latest/download/static.zip"
      fi
      ;;
    "beta")
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghfast.top/https://github.com/ThisSeanZhang/landscape/releases/download/prerelease/static.zip"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/download/prerelease/static.zip"
      fi
      ;;
  esac
  
  echo "$download_url"
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

# 控制Landscape服务的函数
control_landscape_service() {
  local action="$1"
  case "$action" in
    "start")
      log "正在启动 Landscape Router 服务..."
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
  local max_backups=1
  if [ "$version_type" = "beta" ] && [ "$BACKUP_COUNT" -eq 0 ]; then
    max_backups=3
  elif [ "$BACKUP_COUNT" -gt 0 ]; then
    max_backups=$BACKUP_COUNT
  fi
  
  # 获取当前版本号
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
  (cd "$landscape_dir" && find . -name "backup" -prune -o -print0 | pax -0 -rwd "$temp_dir")
  
  # 根据可用工具进行压缩
  case "$compress_tool" in
    "tar.gz")
      # 使用 tar + gzip 创建 .tar.gz 备份
      backup_file="$backup_dir/${backup_name}.tar.gz"
      (cd "$temp_dir" && tar -czf "$backup_file" .)
      ;;
    "tar.bz2")
      # 使用 tar + bzip2 创建 .tar.bz2 备份
      backup_file="$backup_dir/${backup_name}.tar.bz2"
      (cd "$temp_dir" && tar -cjf "$backup_file" .)
      ;;
    "tar.xz")
      # 使用 tar + xz 创建 .tar.xz 备份
      backup_file="$backup_dir/${backup_name}.tar.xz"
      (cd "$temp_dir" && tar -cJf "$backup_file" .)
      ;;
    "tar")
      # 使用单独的 tar 创建 .tar 备份
      backup_file="$backup_dir/${backup_name}.tar"
      (cd "$temp_dir" && tar -cf "$backup_file" .)
      ;;
    "gz")
      # 使用单独的 gzip 创建 .gz 备份
      backup_file="$backup_dir/${backup_name}.tar.gz"
      (cd "$temp_dir" && tar -cf - . | gzip > "$backup_file")
      ;;
    "bz2")
      # 使用单独的 bzip2 创建 .bz2 备份
      backup_file="$backup_dir/${backup_name}.tar.bz2"
      (cd "$temp_dir" && tar -cf - . | bzip2 > "$backup_file")
      ;;
    "xz")
      # 使用单独的 xz 创建 .xz 备份
      backup_file="$backup_dir/${backup_name}.tar.xz"
      (cd "$temp_dir" && tar -cf - . | xz > "$backup_file")
      ;;
    "zip")
      # 使用 zip 创建 .zip 备份
      backup_file="$backup_dir/${backup_name}.zip"
      (cd "$temp_dir" && zip -rq "$backup_file" .)
      ;;
  esac
  
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

# 回滚功能
rollback_landscape() {
  local backup_dir="$LANDSCAPE_DIR/backup"
  if [ ! -d "$backup_dir" ]; then
    log "错误: 未找到备份目录 $backup_dir"
    return 1
  fi
  
  # 查找所有备份文件
  local backup_files=()
  while IFS= read -r -d '' file; do
    backup_files+=("$file")
  done < <(find "$backup_dir" -name "landscape-*.tar.gz" -o -name "landscape-*.tar.bz2" -o -name "landscape-*.tar.xz" -o -name "landscape-*.tar" -o -name "landscape-*.gz" -o -name "landscape-*.bz2" -o -name "landscape-*.xz" -o -name "landscape-*.zip" -print0 | sort -rz)
  
  local backup_count=${#backup_files[@]}
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
  
  # 根据文件扩展名确定解压方式
  local temp_dir
  temp_dir=$(mktemp -d) || {
    log "错误: 无法创建临时目录"
    control_landscape_service "start"
    return 1
  }
  
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
    rm -rf "$temp_dir"
    control_landscape_service "start"
    return 1
  fi
  
  # 清空 landscape 目录（排除 backup 目录）
  (cd "$landscape_dir" && find . -name "backup" -prune -o -exec rm -rf {} + 2>/dev/null || true)
  
  # 将备份内容复制回 landscape 目录
  (cd "$temp_dir" && find . -print0 | pax -0 -rwd "$landscape_dir")
  
  # 清理临时目录
  rm -rf "$temp_dir"
  
  log "回滚完成"
  
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
  
  return 0
}

# 通用下载函数，支持wget和curl，优先使用wget
# 参数: URL, 输出文件路径
download_with_retry() {
  local url="$1"
  local output_file="$2"
  local max_retries=5
  local retry_count=0
  local download_tool=""
  
  # 检查是否有wget或curl
  if command -v wget >/dev/null 2>&1; then
    download_tool="wget"
  elif command -v curl >/dev/null 2>&1; then
    download_tool="curl"
  else
    log "错误: 系统中未找到 wget 或 curl 命令，请安装其中一个再继续"
    return 1
  fi
  
  log "使用 $download_tool 下载: $url"
  
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

# 通用升级函数
upgrade_landscape_version() {
  local version_type="$1"  # stable, beta
  local display_name="$2"  # 显示名称
  local landscape_dir="$3" # 安装目录
  
  if [ "$USE_CN_MIRROR" = true ]; then
    log "正在使用中国镜像加速升级 Landscape Router 到最新 $display_name..."
  else
    log "正在升级 Landscape Router 到最新 $display_name..."
  fi
  
  # 检查是否已安装
  check_landscape_installed "$landscape_dir" "$SYSTEM_ARCH" "$USE_MUSL" || exit 1
  
  # 如果需要创建备份
  if [ "$CREATE_BACKUP" = true ]; then
    log "正在创建备份..."
    create_backup "$landscape_dir" "$version_type" || exit 1
  fi
  
  # 获取当前版本信息（仅适用于stable版本）
  local current_version=""
  local current_filename="landscape-webserver-$SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    current_filename="landscape-webserver-x86_64-musl"
  fi
  
  if [ "$version_type" = "stable" ] && [ -f "$landscape_dir/$current_filename" ]; then
    current_version=$("$landscape_dir/$current_filename" --version 2>/dev/null)
    log "当前版本: $current_version"
  fi
  
  # 获取下载信息
  local download_info
  download_info=$(get_download_info "$version_type")
  local download_url=$(echo "$download_info" | cut -d'|' -f1)
  local filename=$(echo "$download_info" | cut -d'|' -f2)
  
  # 获取static.zip下载URL
  local static_download_url
  static_download_url=$(get_static_download_url "$version_type")
  
  # 创建临时目录
  local temp_dir
  temp_dir=$(mktemp -d) || {
    log "错误: 无法创建临时目录"
    exit 1
  }
  
  log "下载文件到临时目录: $temp_dir"
  
  # 确保下载目录存在
  mkdir -p "$temp_dir"
  
  # 下载可执行文件
  if ! download_with_retry "$download_url" "$temp_dir/$filename"; then
    log "可执行文件下载失败"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 对于稳定版，检查是否降级
  if [ "$version_type" = "stable" ]; then
    # 为新下载的文件添加执行权限以获取版本信息
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
        rm -rf "$temp_dir"
        exit 0
      elif [ "$current_version" = "$new_version" ]; then
        log "当前已是最新稳定版，无需升级"
        rm -rf "$temp_dir"
        exit 0
      fi
    fi
  fi
  
  # 下载static.zip
  log "正在下载 static.zip..."
  if ! download_with_retry "$static_download_url" "$temp_dir/static.zip"; then
    log "static.zip 下载失败"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 解压static.zip到statictmp目录
  log "正在解压 static.zip..."
  mkdir -p "$temp_dir/statictmp"
  if ! unzip "$temp_dir/static.zip" -d "$temp_dir/statictmp"; then
    log "static.zip 解压失败"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 在statictmp目录中查找包含index.html的目录
  log "正在查找静态文件目录..."
  local static_source_dir
  static_source_dir=$(find_static_dir "$temp_dir/statictmp")
  if [ -z "$static_source_dir" ]; then
    log "未找到包含 index.html 的目录"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 下载完成，停止服务
  log "下载完成，正在停止 Landscape Router 服务..."
  control_landscape_service "stop"
  
  # 设置下载文件的执行权限
  chmod +x "$temp_dir/$filename"
  
  # 备份旧文件
  local backup_file="$landscape_dir/$filename.bak"
  if [ -f "$landscape_dir/$filename" ]; then
    if ! mv "$landscape_dir/$filename" "$backup_file"; then
      log "文件备份失败"
      control_landscape_service "start"
      rm -rf "$temp_dir"
      exit 1
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
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 删除备份文件
  if [ -f "$backup_file" ]; then
    rm -f "$backup_file"
  fi
  
  # 替换静态文件目录
  log "正在更新 UI 静态文件..."
  rm -rf "$landscape_dir/static"
  if ! cp -r "$static_source_dir" "$landscape_dir/static"; then
    log "UI 静态文件替换失败"
    log "UI 可能仍为旧版本，或无法使用"
    log "后端升级失败，前端升级成功"
    log "建议您手动替换 UI 静态文件，并重启 Landscape Router"
    log "不使用 UI 时，Landscape Router 仍可正常工作"
    log "现尝试为您启动新版 Landscape Router..."
    control_landscape_service "start"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 清理临时目录
  rm -rf "$temp_dir"
  
  log "Landscape Router $display_name 升级完成"
  
  # 根据AUTO_REBOOT变量决定是否自动重启
  if [ "$AUTO_REBOOT" = true ]; then
    log "正在重启系统以应用更新..."
    reboot
  else
    # 询问用户是否重启
    read -p "是否立即重启系统以应用更新？(y/N): " -n 1 -r
    printf "\n"
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      log "正在重启系统以应用更新..."
      reboot
    else
      log "升级已完成，但系统尚未重启。请在适当的时候手动重启系统以应用更新。"
    fi
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
