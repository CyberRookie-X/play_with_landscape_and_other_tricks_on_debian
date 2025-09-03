#!/bin/bash

# Landscape Router 升级脚本
# 用法: ./upgrade_landscape.sh [up|upb] [cn] [r]
# 参数: 
#   up  - 升级到最新稳定版（默认）stable
#   upb - 升级到最新 Beta 版        beta
#   cn  - 使用中国镜像加速（可选）
#   r   - 升级完成后自动重启（可选）


# 全局变量
USE_CN_MIRROR=false
SHOW_HELP=false
AUTO_REBOOT=false

# TODO 用户可能对于 可执行文件有不同的命名方式
# TODO stable版，通过可执行文件检查当前版本
# 获取 Landscape Router 安装路径
get_landscape_dir() {
  local landscape_dir=""
  if [ -f "/etc/systemd/system/landscape-router.service" ]; then
    landscape_dir=$(grep -oP 'ExecStart=\K[^/]*(?=/landscape-webserver-)' /etc/systemd/system/landscape-router.service 2>/dev/null)
    if [ -z "$landscape_dir" ]; then
      echo "错误: 无法从 landscape-router.service 中提取安装路径，升级终止" >&2
      return 1
    fi
  else
    echo "错误: 未找到 landscape-router.service 文件，升级终止" >&2
    return 1
  fi
  echo "$landscape_dir"
}

# 检查 Landscape Router 是否已安装
check_landscape_installed() {
  local landscape_dir="$1"
  local system_arch="$2"
  
  if [ ! -f "$landscape_dir/landscape-webserver-$system_arch" ]; then
    echo "错误: 未检测到已安装的 Landscape Router" >&2
    return 1
  fi
  return 0
}

# 获取下载URL和文件名
get_download_info() {
  local version_type="$1"
  local system_arch="$2"
  local version="$3"
  
  local download_url=""
  local filename=""
  
  if [ "$system_arch" = "aarch64" ]; then
    filename="landscape-webserver-aarch64"
  else
    filename="landscape-webserver-x86_64"
  fi
  
  # 根据是否使用中国镜像设置下载URL
  case "$version_type" in
    "stable")
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghproxy.com/https://github.com/ThisSeanZhang/landscape/releases/download/$version/$filename"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/download/$version/$filename"
      fi
      ;;
    "beta")
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghproxy.com/https://github.com/ThisSeanZhang/landscape/releases/download/$version/$filename"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/download/$version/$filename"
      fi
      ;;
  esac
  
  echo "$download_url|$filename"
}

# 获取static.zip下载URL
get_static_download_url() {
  local version_type="$1"
  local version="$2"
  
  local download_url=""
  

  # 根据是否使用中国镜像设置下载URL
  case "$version_type" in
    "stable")
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghproxy.com/https://github.com/ThisSeanZhang/landscape/releases/download/$version/static.zip"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/download/$version/static.zip"
      fi
      ;;
    "beta")
      if [ "$USE_CN_MIRROR" = true ]; then
        download_url="https://ghproxy.com/https://github.com/ThisSeanZhang/landscape/releases/download/$version/static.zip"
      else
        download_url="https://github.com/ThisSeanZhang/landscape/releases/download/$version/static.zip"
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

# 显示帮助信息
show_help() {
  echo "Landscape Router 升级脚本"
  echo "用法: ./upgrade_landscape.sh [up|upb] [cn] [r]"
  echo "参数:"
  echo "  up  - 升级到最新稳定版（默认）"
  echo "  upb - 升级到最新 Beta 版"
  echo "  cn  - 使用中国镜像加速（可选）"
  echo "  r   - 升级完成后自动重启（可选）"
  echo "  -h, --help - 显示此帮助信息"
  echo ""
  echo "示例:"
  echo "  ./upgrade_landscape.sh          # 升级到最新稳定版"
  echo "  ./upgrade_landscape.sh up       # 升级到最新稳定版"
  echo "  ./upgrade_landscape.sh upb      # 升级到最新 Beta 版"
  echo "  ./upgrade_landscape.sh up cn    # 使用中国镜像升级到最新稳定版"
  echo "  ./upgrade_landscape.sh up r     # 升级到最新稳定版并自动重启"
  echo "  ./upgrade_landscape.sh up cn r  # 使用中国镜像升级到最新稳定版并自动重启"
  echo "  ./upgrade_landscape.sh -h       # 显示帮助信息"
}

# 获取GitHub发布版本
get_github_release() {
  local version_type="$1"
  
  local repo="ThisSeanZhang/landscape"
  local version=""
  
  case "$version_type" in
    "stable")
      # 获取最新的稳定版本（非预发布版本）
      version=$(curl -s "https://api.github.com/repos/$repo/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
      ;;
    "beta")
      # 获取最新发布的版本（无论是否为预发布版本）
      version=$(curl -s "https://api.github.com/repos/$repo/releases" | grep -m 1 '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
      ;;
    *)
      echo "错误: 不支持的版本类型 $version_type" >&2
      return 1
      ;;
  esac
  
  if [ -z "$version" ]; then
    echo "错误: 无法获取 $version_type 版本信息" >&2
    return 1
  fi
  
  echo "$version"
}

# 控制Landscape服务的函数
control_landscape_service() {
  local action="$1"
  case "$action" in
    "start")
      echo "正在启动 Landscape Router 服务..."
      systemctl start landscape-router
      ;;
    "stop")
      echo "正在停止 Landscape Router 服务..."
      systemctl stop landscape-router
      ;;
    "restart")
      echo "正在重启 Landscape Router 服务..."
      systemctl restart landscape-router
      ;;
    *)
      echo "未知的服务操作: $action" >&2
      return 1
      ;;
  esac
}

# 通用升级函数
upgrade_landscape_version() {
  local version_type="$1"  # stable, beta
  local display_name="$2"  # 显示名称
  
  if [ "$USE_CN_MIRROR" = true ]; then
    echo "正在使用中国镜像加速升级 Landscape Router 到最新 $display_name..."
  else
    echo "正在升级 Landscape Router 到最新 $display_name..."
  fi
  
  # 获取安装路径
  local landscape_dir
  landscape_dir=$(get_landscape_dir) || exit 1
  
  # 检查是否已安装
  check_landscape_installed "$landscape_dir" "$SYSTEM_ARCH" || exit 1
  
  # 获取版本信息
  local version_var=""
  echo "正在获取最新 $display_name 版本信息..."
  case "$version_type" in
    "stable")
      version_var=$(get_github_release "stable")
      ;;
    "beta")
      version_var=$(get_github_release "beta")
      ;;
  esac
  
  if [ -n "$version_var" ]; then
    echo "正在下载版本: $version_var"
    
    # 获取下载信息
    local download_info
    download_info=$(get_download_info "$version_type" "$SYSTEM_ARCH" "$version_var")
    local download_url=$(echo "$download_info" | cut -d'|' -f1)
    local filename=$(echo "$download_info" | cut -d'|' -f2)
    
    # 获取static.zip下载URL
    local static_download_url
    static_download_url=$(get_static_download_url "$version_type" "$version_var")
    
    # 下载文件
    local temp_dir=$(mktemp -d)
    echo "下载文件到临时目录: $temp_dir"
    if ! curl -L "$download_url" -o "$temp_dir/$filename.new"; then
      echo "下载失败"
      rm -rf "$temp_dir"
      exit 1
    fi
    
    # 下载static.zip
    echo "正在下载 static.zip..."
    if ! curl -L "$static_download_url" -o "$temp_dir/static.zip"; then
      echo "static.zip 下载失败"
      rm -rf "$temp_dir"
      exit 1
    fi
    
    # 解压static.zip到statictmp目录
    echo "正在解压 static.zip..."
    mkdir -p "$temp_dir/statictmp"
    if ! unzip "$temp_dir/static.zip" -d "$temp_dir/statictmp"; then
      echo "static.zip 解压失败"
      rm -rf "$temp_dir"
      exit 1
    fi
    
    # 在statictmp目录中查找包含index.html的目录
    echo "正在查找静态文件目录..."
    local static_source_dir
    static_source_dir=$(find_static_dir "$temp_dir/statictmp")
    if [ -z "$static_source_dir" ]; then
      echo "未找到包含 index.html 的目录"
      rm -rf "$temp_dir"
      exit 1
    fi
    
    # 下载完成，停止服务
    echo "下载完成，正在停止 Landscape Router 服务..."
    control_landscape_service "stop"
    
    # 替换可执行文件
    if ! mv "$temp_dir/$filename.new" "$landscape_dir/$filename"; then
      echo "文件替换失败"
      # 尝试重启服务
      control_landscape_service "start"
      rm -rf "$temp_dir"
      exit 1
    fi

    # 设置可执行文件权限
    chmod 755 "$landscape_dir/landscape-webserver-$SYSTEM_ARCH"
    
    # 替换静态文件目录
    echo "正在更新 UI 静态文件..."
    rm -rf "$landscape_dir/static"
    if ! cp -r "$static_source_dir" "$landscape_dir/static"; then
      echo "UI 静态文件替换失败"
      echo "UI 可能仍为旧版本，或无法使用"
      echo "后端升级失败，前端升级成功"
      echo "建议您手动替换 UI 静态文件，并重启 Landscape Router"
      echo "不使用 UI 时，Landscape Router 仍可正常工作"
      echo "现尝试为您启动新版 Landscape Router..."
      control_landscape_service "start"
      rm -rf "$temp_dir"
      exit 1
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir"
  else
    echo "无法获取最新的 $display_name 版本信息"
    exit 1
  fi
  
  echo "Landscape Router $display_name 升级完成"
  
  # 根据AUTO_REBOOT变量决定是否自动重启
  if [ "$AUTO_REBOOT" = true ]; then
    echo "正在重启系统以应用更新..."
    reboot
  else
    # 询问用户是否重启
    read -p "是否立即重启系统以应用更新？(y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "正在重启系统以应用更新..."
      reboot
    else
      echo "升级已完成，但系统尚未重启。请在适当的时候手动重启系统以应用更新。"
    fi
  fi
}

# 升级 Landscape Router 稳定版
upgrade_landscape() {
  upgrade_landscape_version "stable" "稳定版"
}

# 升级到 Beta 版本
upgrade_beta() {
  upgrade_landscape_version "beta" "beta版"
}


# 解析命令行参数
parse_arguments() {
  ACTION="up"  # 默认动作
  
  for arg in "$@"; do
    case "$arg" in
      "up"|"upb")
        ACTION="$arg"
        ;;
      "cn")
        USE_CN_MIRROR=true
        ;;
      "r")
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

# 主函数
main() {
  # 解析命令行参数
  parse_arguments "$@"
  
  # 如果请求帮助，则显示帮助信息并退出
  if [ "$SHOW_HELP" = true ]; then
    show_help
    exit 0
  fi
  
  # 根据参数执行相应功能
  case "$ACTION" in
    "up")
      upgrade_landscape
      ;;
    "upb")
      upgrade_beta
      ;;
    *)
      show_help
      exit 1
      ;;
  esac
}

# 检查系统架构
SYSTEM_ARCH=$(uname -m)
if [ "$SYSTEM_ARCH" != "x86_64" ] && [ "$SYSTEM_ARCH" != "aarch64" ]; then
  echo "不支持的系统架构: $SYSTEM_ARCH"
  exit 1
fi

# 执行主函数
main "$@"