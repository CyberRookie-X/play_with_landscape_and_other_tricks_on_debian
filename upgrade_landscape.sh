#!/bin/bash

# Landscape Router 升级脚本
# 用法: ./upgrade_landscape.sh [stable|beta] [cn] [reboot]
# 参数: 
#   stable - 升级到最新稳定版（默认）
#   beta   - 升级到最新 Beta 版
#   cn     - 使用中国镜像加速（可选）
#   reboot - 升级完成后自动重启（可选）

# TODO
# 用户可能对于 可执行文件有不同的命名方式
# 旧版 完整 备份/回退
# 完整的 gitee 仓库，以实现可靠的中国网络镜像加速
# beta版，调整到 release 发布？
# 去除 echo
# 开始前进行 依赖检测

# ========== 全局变量 ==========
USE_CN_MIRROR=false
SHOW_HELP=false
AUTO_REBOOT=false
ACTION="stable"  # 默认动作
SYSTEM_ARCH=""
INIT_SYSTEM=""
USE_MUSL=false

# ========== 主函数 ==========

main() {
  # 执行系统环境检查（包括架构、初始化系统和依赖项）
  check_system_environment
  
  # 解析命令行参数
  parse_arguments "$@"
  
  # 如果请求帮助，则显示帮助信息并退出
  if [ "$SHOW_HELP" = true ]; then
    show_help
    exit 0
  fi
  
  # 根据参数执行相应功能
  case "$ACTION" in
    "stable")
      upgrade_stable
      ;;
    "beta")
      upgrade_beta
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
}

# ========== 函数定义 ==========

# 系统环境检查（包括架构、初始化系统和依赖项）
check_system_environment() {
  # 检查系统架构
  SYSTEM_ARCH=$(uname -m)
  if [ "$SYSTEM_ARCH" != "x86_64" ] && [ "$SYSTEM_ARCH" != "aarch64" ]; then
    printf "不支持的系统架构: %s\n" "$SYSTEM_ARCH"
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
    printf "错误: 不支持的初始化系统，需要 systemd 或 OpenRC\n"
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
  
  for arg in "$@"; do
    case "$arg" in
      "stable"|"beta")
        ACTION="$arg"
        ;;
      "cn")
        USE_CN_MIRROR=true
        ;;
      "reboot")
        AUTO_REBOOT=true
        ;;
      "-h"|"--help")
        SHOW_HELP=true
        ;;
      *)
        # 忽略未知参数或显示帮助信息
        ;;
    esac
  done
}

# 显示帮助信息
show_help() {
  echo "Landscape Router 升级脚本"
  echo "用法: ./upgrade_landscape.sh [stable|beta] [cn] [reboot]"
  echo "参数:"
  echo "  stable - 升级到最新稳定版（默认）"
  echo "  beta   - 升级到最新 Beta 版"
  echo "  cn     - 使用中国镜像加速（可选）"
  echo "  reboot - 升级完成后自动重启（可选）"
  echo "  -h, --help - 显示此帮助信息"
  echo ""
  echo "示例:"
  echo "  ./upgrade_landscape.sh              # 升级到最新稳定版"
  echo "  ./upgrade_landscape.sh stable       # 升级到最新稳定版"
  echo "  ./upgrade_landscape.sh beta         # 升级到最新 Beta 版"
  echo "  ./upgrade_landscape.sh stable cn    # 使用中国镜像升级到最新稳定版"
  echo "  ./upgrade_landscape.sh stable reboot # 升级到最新稳定版并自动重启"
  echo "  ./upgrade_landscape.sh stable cn reboot  # 使用中国镜像升级到最新稳定版并自动重启"
  echo "  ./upgrade_landscape.sh -h           # 显示帮助信息"
  echo ""
  echo "当前系统初始化系统: $INIT_SYSTEM"
  echo "当前系统架构: $SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ]; then
    echo "系统类型: musl"
  else
    echo "系统类型: glibc"
  fi
}

# 获取 Landscape Router 安装路径
get_landscape_dir() {
  local landscape_dir=""
  if [ "$INIT_SYSTEM" = "systemd" ] && [ -f "/etc/systemd/system/landscape-router.service" ]; then
    landscape_dir=$(grep -oP 'ExecStart=\K[^/]*(?=/landscape-webserver-)' /etc/systemd/system/landscape-router.service 2>/dev/null)
    if [ -z "$landscape_dir" ]; then
      printf "错误: 无法从 landscape-router.service 中提取安装路径，升级终止\n" >&2
      return 1
    fi
  elif [ "$INIT_SYSTEM" = "openrc" ] && [ -f "/etc/init.d/landscape-router" ]; then
    # 对于 OpenRC，从启动脚本中提取安装路径
    landscape_dir=$(grep -oP 'command=\K[^/]*(?=/landscape-webserver-)' /etc/init.d/landscape-router 2>/dev/null)
    if [ -z "$landscape_dir" ]; then
      printf "错误: 无法从 landscape-router 启动脚本中提取安装路径，升级终止\n" >&2
      return 1
    fi
  else
    if [ "$INIT_SYSTEM" = "systemd" ]; then
      printf "错误: 未找到 landscape-router.service 文件，升级终止\n" >&2
    else
      printf "错误: 未找到 landscape-router 启动脚本，升级终止\n" >&2
    fi
    return 1
  fi
  printf "%s" "$landscape_dir"
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
    printf "错误: 未检测到已安装的 Landscape Router\n" >&2
    return 1
  fi
  return 0
}

# 获取下载URL和文件名
get_download_info() {
  local version_type="$1"
  local system_arch="$2"
  local use_musl="$3"
  
  local download_url=""
  local filename=""
  
  if [ "$use_musl" = true ] && [ "$system_arch" = "x86_64" ]; then
    filename="landscape-webserver-x86_64-musl"
  elif [ "$system_arch" = "aarch64" ]; then
    filename="landscape-webserver-aarch64"
  else
    filename="landscape-webserver-x86_64"
  fi
  
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
      printf "%s\n" "正在启动 Landscape Router 服务..."
      if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl start landscape-router
      else
        rc-service landscape-router start
      fi
      ;;
    "stop")
      printf "%s\n" "正在停止 Landscape Router 服务..."
      if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl stop landscape-router
      else
        rc-service landscape-router stop
      fi
      ;;
    "restart")
      printf "%s\n" "正在重启 Landscape Router 服务..."
      if [ "$INIT_SYSTEM" = "systemd" ]; then
        systemctl restart landscape-router
      else
        rc-service landscape-router restart
      fi
      ;;
    *)
      printf "未知的服务操作: %s\n" "$action" >&2
      return 1
      ;;
  esac
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
    printf "错误: 系统中未找到 wget 或 curl 命令，请安装其中一个再继续\n"
    return 1
  fi
  
  printf "使用 %s 下载: %s\n" "$download_tool" "$url"
  
  # 重试循环
  while [ $retry_count -lt $max_retries ]; do
    case "$download_tool" in
      "wget")
        if wget -O "$output_file" "$url"; then
          printf "%s\n" "下载成功"
          return 0
        fi
        ;;
      "curl")
        if curl -L -o "$output_file" "$url"; then
          printf "%s\n" "下载成功"
          return 0
        fi
        ;;
    esac
    
    retry_count=$((retry_count + 1))
    if [ $retry_count -lt $max_retries ]; then
      printf "下载失败，%d 秒后进行第 %d 次重试...\n" "$retry_count" "$retry_count"
      sleep $retry_count
    fi
  done
  
  printf "错误: 下载失败，已重试 %d 次\n" "$max_retries"
  return 1
}

# 通用升级函数
upgrade_landscape_version() {
  local version_type="$1"  # stable, beta
  local display_name="$2"  # 显示名称
  
  if [ "$USE_CN_MIRROR" = true ]; then
    printf "正在使用中国镜像加速升级 Landscape Router 到最新 %s...\n" "$display_name"
  else
    printf "正在升级 Landscape Router 到最新 %s...\n" "$display_name"
  fi
  
  # 获取安装路径
  local landscape_dir
  landscape_dir=$(get_landscape_dir) || exit 1
  
  # 检查是否已安装
  check_landscape_installed "$landscape_dir" "$SYSTEM_ARCH" "$USE_MUSL" || exit 1
  
  # 获取当前版本信息（仅适用于stable版本）
  local current_version=""
  local current_filename="landscape-webserver-$SYSTEM_ARCH"
  if [ "$USE_MUSL" = true ] && [ "$SYSTEM_ARCH" = "x86_64" ]; then
    current_filename="landscape-webserver-x86_64-musl"
  fi
  
  if [ "$version_type" = "stable" ] && [ -f "$landscape_dir/$current_filename" ]; then
    current_version=$("$landscape_dir/$current_filename" --version 2>/dev/null)
    printf "当前版本: %s\n" "$current_version"
  fi
  
  # 获取下载信息
  local download_info
  download_info=$(get_download_info "$version_type" "$SYSTEM_ARCH" "$USE_MUSL")
  local download_url=$(echo "$download_info" | cut -d'|' -f1)
  local filename=$(echo "$download_info" | cut -d'|' -f2)
  
  # 获取static.zip下载URL
  local static_download_url
  static_download_url=$(get_static_download_url "$version_type")
  
  # 创建临时目录
  local temp_dir
  temp_dir=$(mktemp -d) || {
    printf "错误: 无法创建临时目录\n" >&2
    exit 1
  }
  
  printf "下载文件到临时目录: %s\n" "$temp_dir"
  
  # 确保下载目录存在
  mkdir -p "$temp_dir"
  
  # 下载可执行文件
  if ! download_with_retry "$download_url" "$temp_dir/$filename"; then
    printf "%s\n" "可执行文件下载失败"
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
    printf "最新版本: %s\n" "$new_version"
    
    # 比较版本，如果新版本小于等于当前版本，则不升级
    if [ -n "$current_version" ] && [ -n "$new_version" ]; then
      # 简单的版本比较（假设版本格式为 vX.Y.Z）
      # 使用 sort -V 进行版本比较
      local version_comparison=$(printf "%s\n%s" "$current_version" "$new_version" | sort -V | head -n1)
      if [ "$version_comparison" = "$new_version" ] && [ "$current_version" != "$new_version" ]; then
        printf "检测到新版本 %s 比当前版本 %s 更旧，为防止降级，取消升级\n" "$new_version" "$current_version"
        rm -rf "$temp_dir"
        exit 0
      elif [ "$current_version" = "$new_version" ]; then
        printf "%s\n" "当前已是最新稳定版，无需升级"
        rm -rf "$temp_dir"
        exit 0
      fi
    fi
  fi
  
  # 下载static.zip
  printf "%s\n" "正在下载 static.zip..."
  if ! download_with_retry "$static_download_url" "$temp_dir/static.zip"; then
    printf "%s\n" "static.zip 下载失败"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 解压static.zip到statictmp目录
  printf "%s\n" "正在解压 static.zip..."
  mkdir -p "$temp_dir/statictmp"
  if ! unzip "$temp_dir/static.zip" -d "$temp_dir/statictmp"; then
    printf "%s\n" "static.zip 解压失败"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 在statictmp目录中查找包含index.html的目录
  printf "%s\n" "正在查找静态文件目录..."
  local static_source_dir
  static_source_dir=$(find_static_dir "$temp_dir/statictmp")
  if [ -z "$static_source_dir" ]; then
    printf "%s\n" "未找到包含 index.html 的目录"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 下载完成，停止服务
  printf "%s\n" "下载完成，正在停止 Landscape Router 服务..."
  control_landscape_service "stop"
  
  # 设置下载文件的执行权限
  chmod +x "$temp_dir/$filename"
  
  # 备份旧文件
  local backup_file="$landscape_dir/$filename.bak"
  if [ -f "$landscape_dir/$filename" ]; then
    if ! mv "$landscape_dir/$filename" "$backup_file"; then
      printf "%s\n" "文件备份失败"
      control_landscape_service "start"
      rm -rf "$temp_dir"
      exit 1
    fi
  fi
  
  # 替换可执行文件
  if ! mv "$temp_dir/$filename" "$landscape_dir/$filename"; then
    printf "%s\n" "文件替换失败"
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
  printf "%s\n" "正在更新 UI 静态文件..."
  rm -rf "$landscape_dir/static"
  if ! cp -r "$static_source_dir" "$landscape_dir/static"; then
    printf "%s\n" "UI 静态文件替换失败"
    printf "%s\n" "UI 可能仍为旧版本，或无法使用"
    printf "%s\n" "后端升级失败，前端升级成功"
    printf "%s\n" "建议您手动替换 UI 静态文件，并重启 Landscape Router"
    printf "%s\n" "不使用 UI 时，Landscape Router 仍可正常工作"
    printf "%s\n" "现尝试为您启动新版 Landscape Router..."
    control_landscape_service "start"
    rm -rf "$temp_dir"
    exit 1
  fi
  
  # 清理临时目录
  rm -rf "$temp_dir"
  
  printf "Landscape Router %s 升级完成\n" "$display_name"
  
  # 根据AUTO_REBOOT变量决定是否自动重启
  if [ "$AUTO_REBOOT" = true ]; then
    printf "%s\n" "正在重启系统以应用更新..."
    reboot
  else
    # 询问用户是否重启
    read -p "是否立即重启系统以应用更新？(y/N): " -n 1 -r
    printf "\n"
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      printf "%s\n" "正在重启系统以应用更新..."
      reboot
    else
      printf "%s\n" "升级已完成，但系统尚未重启。请在适当的时候手动重启系统以应用更新。"
    fi
  fi
}

# 升级 Landscape Router 稳定版
upgrade_stable() {
  upgrade_landscape_version "stable" "稳定版"
}

# 升级到 Beta 版本
upgrade_beta() {
  upgrade_landscape_version "beta" "beta版"
}

# 执行主函数
main "$@"
