# 在 Debian 里，玩转 Landscape Router 和其他花活（持续更新中...）

**本文可自由转载，无需标注出处**  
[Landscape Router 文档网站](https://landscape.whileaway.dev/introduction.html) | [Landscape Router github](https://github.com/ThisSeanZhang/landscape)


**本教程已适配中国大陆网络** 

# 脚本安装 Landscape Router [链接](/docs/1-安装升级指南.md/#安装-landscape-router脚本方式)

## 核心特性
* 分流控制（SIP-CIDR、DIP、域名、Geo 匹配规则）
* eBPF 路由
* 每个流 Flow 独立 dns 配置以及缓存（避免 dns 污染、泄露）
* 流量导入 Docker 容器
* 地理关系库管理

## 内核兼容的 常见 Linux 发行版  
✅ 内核兼容  
🟢 部分的内核版本兼容  
⚠️ 未经测试，可能兼容
❌ 内核不兼容  





| 发行版 | 兼容 | 发行版版本 |landscape 版本| 备注 |  
|---|---|---|---|---|  
| Debian  | ✅ | 13+ | glibc(普通版) | 低版本需更新内核至6.9+ |  
| Ubuntu | ⚠️ | 25.04+ | glibc(普通版) |  低版本需更新内核至6.9+|  
| PVE | ⚠️ | 9+ | glibc(普通版) |  低版本需更新内核至6.9+|  
| OMV | ⚠️ | 8+ | glibc(普通版) |  低版本需更新内核至6.9+| 
| Armbian | 🟢 |  |glibc(普通版) |  低版本需更新内核至6.9+| 
| Alpine | ⚠️ | 3.21 | musl |  低版本需更新内核至6.9+ | 
| OpenWRT | ⚠️ |  | musl |  低版本需更新内核至6.9+ |   
| FnOS | ❌ |  | |   内核限制 |  

<!--🟡 未知  -->

**landscape 分为普通版（Glibc），musl 版，下载landscape时，请选择对应的可执行文件安装**

``` shell
# 检查内核版本，是否 6.9+
uname -r

```
``` shell
# 查看，glibc / musl 支持
# 输出带有 GLIBC 或 GNU libc，下载 普通版（glibc）可执行文件安装
# 输出带有 musl libc ，下载 musl 版 可执行文件安装
ldd --version

```
# 一、安装/升级 指南 [文档](/docs/1-安装升级指南.md)

# 二、Landscape 分流实践 [文档](/docs/2-Landscape分流实践.md)

# 三、Docker容器作为分流出口（接应容器部署）[文档](/docs/3-Docker容器作为分流出口-接应容器.md)

# 四、常见网络应用、compose 安装 [文档](/docs/4-常见网络应用-compose安装.md)

# 文档目录
- [Debian 安装配置（已适配中国大陆网络）](/docs/1-安装升级指南.md/#debian-安装配置已适配中国大陆网络)
  - [下载 debian  ISO 镜像](/docs/1-安装升级指南.md/#下载必要软件)
  - [安装 debian](/docs/1-安装升级指南.md/#安装-debian)
- [安装 landscape router（脚本方式）](/docs/1-安装升级指南.md/#安装-landscape-router脚本方式)
- [升级 landscape router（脚本方式）](/docs/1-安装升级指南.md/#安装-landscape-router脚本方式)
- [升级 landscape router（手工方式）](/docs/1-安装升级指南.md/#升级-landscape-router手工方式)
- [安装 landscape router（手工方式）](/docs/1-安装升级指南.md/#安装-landscape-router手工方式)
  - [时区修改到上海](/docs/1-安装升级指南.md/#时区修改到上海)
  - [允许root用户使用密码登录ssh](/docs/1-安装升级指南.md/#允许root用户使用密码登录ssh)
  - [关闭 swap](/docs/1-安装升级指南.md/#关闭-swap)
  - [修改软件源（可选）](#修改软件源可选)
  - [升级内核，到 6.9以上（debian 13 无需升级内核）](/docs/1-安装升级指南.md/#升级内核到-69以上debian-13-无需升级内核)
  - [安装 docker、docker compose（已适配中国大陆网络） ](/docs/1-安装升级指南.md/#安装-dockerdocker-compose已适配中国大陆网络)
  - [Landscape Router 安装（已适配中国大陆网络）](/docs/1-安装升级指南.md/#landscape-安装已适配中国大陆网络)
  - [安装 pppd](/docs/1-安装升级指南.md/#安装-pppd)
  - [创建 landscape systemd 服务文件](/docs/1-安装升级指南.md/#创建-landscape-systemd-服务文件)
  - [下载并上传 landscape-router](/docs/1-安装升级指南.md/#下载并上传-landscape-router)
  - [修改网卡配置](/docs/1-安装升级指南.md/#修改网卡配置)
  - [关闭本机 DNS 服务](/docs/1-安装升级指南.md/#关闭本机-dns-服务)
  - [重启网络，并启动 landscape-router](/docs/1-安装升级指南.md/#重启网络并启动-landscape-router)
  - [登录 landscape 账号 root 密码 root，https://192.168.22.1:6443](/docs/1-安装升级指南.md/#登录-landscape-账号-root-密码-roothttps1921682216443)
  - [至此可以在 landscape-router web 中进行配置](/docs/1-安装升级指南.md/#至此可以在-landscape-router-web-中进行配置)
  - [应用 Landscape-Router 开机启动](/docs/1-安装升级指南.md/#应用-landscape-router-开机启动)
  - [修改apache80端口到8080, 以免后续与其他反代软件冲突](/docs/1-安装升级指南.md/#修改apache80端口到8080-以免后续与其他反代软件冲突)

- [在显示器/终端中 启动/关闭/查看 landscape-router ](/docs/1-安装升级指南.md/#在显示器终端中-启动关闭查看-landscape-router)
- [主机 失联 救急](/docs/1-安装升级指南.md/#主机-失联-救急)
- [Landscape 实战案例](/docs/2-Landscape分流实践.md/#landscape-实战案例)
  - [目的 域名/IP 分流实践](/docs/2-Landscape分流实践.md/#目的-域名ip-分流实践)
  - [基于 子网/vlan/ssid（WiFi） 的分流实现](/docs/2-Landscape分流实践.md/#基于-子网vlanssidwifi-的分流实现)
  - [对局域网 特定设备 中 特定应用(程序) 分流（通过 dscp 实现）](/docs/2-Landscape分流实践.md/#对局域网-特定设备-中-特定应用程序-分流通过-dscp-实现)
- [流行 docker、dockercompose 管理工具](/docs/3-Docker容器作为分流出口-接应容器.md/#流行-dockerdockercompose-管理工具)
  - [管理面板](/docs/3-Docker容器作为分流出口-接应容器.md/#管理面板)
  - [docker run <=> compose.yaml 命令转换](/docs/3-Docker容器作为分流出口-接应容器.md/#docker-run--composeyaml)
- [用 dpanel 部署 dockercompose](/docs/3-Docker容器作为分流出口-接应容器.md/#用-dpanel-部署-dockercompose)
  - [使用 dpanel 的必要性](/docs/3-Docker容器作为分流出口-接应容器.md/#使用-dpanel-的必要性)
  - [dpanel标准版 与 dpanel lite](/docs/3-Docker容器作为分流出口-接应容器.md/#dpanel标准版-与-dpanel-lite)
  - [安装 dpanel](/docs/3-Docker容器作为分流出口-接应容器.md/#安装-dpanel)
  - [在其他机器上使用 dpanel管理本机docker](/docs/3-Docker容器作为分流出口-接应容器.md//#在其他机器上使用-dpanel管理本机docker)
- [Docker容器作为分流出口 —— 包装脚本方式部署（推荐）](/docs/3-Docker容器作为分流出口-接应容器.md/#docker容器作为分流出口--包装脚本方式部署推荐)
  - [原理概述](/docs/3-Docker容器作为分流出口-接应容器.md/#原理概述)
  - [Docker 部署 单个 容器](/docs/3-Docker容器作为分流出口-接应容器.md/#docker-部署-单个-容器)
  - [Compose 部署 多个 容器](/docs/3-Docker容器作为分流出口-接应容器.md//#compose-部署-多个-容器)
- [Docker容器作为分流出口 —— 挂载工作程序方式部署（不推荐）](/docs/3-Docker容器作为分流出口-接应容器.md/#docker容器作为分流出口--挂载工作程序方式部署不推荐)
  - [接应容器概述](/docs/3-Docker容器作为分流出口-接应容器.md/#接应容器概述)
  - [创建 worker_program 工作程序 启动脚本](/docs/3-Docker容器作为分流出口-接应容器.md/#创建-worker_program-工作程序-启动脚本)
  - [为 Docker 容器启用 ipv6](/docs/3-Docker容器作为分流出口-接应容器.md/#为-docker-容器启用-ipv6)
  - [Docker 部署 单个 接应容器](/docs/3-Docker容器作为分流出口-接应容器.md/#docker-部署-单个-接应容器)
  - [Compose 部署 多个 接应容器](/docs/3-Docker容器作为分流出口-接应容器.md//#compose-部署-多个-接应容器)
- [常见网络应用、compose 安装](/docs/4-常见网络应用-compose安装.md/#常见网络应用compose-安装)
  - [filebrowser（文件管理）](/docs/4-常见网络应用-compose安装.md/#filebrowser文件管理)
  - [tabby （网页ssh）](/docs/4-常见网络应用-compose安装.md/#tabby-网页ssh)
  - [Homebox 局域网测速软件](/docs/4-常见网络应用-compose安装.md/#homebox-局域网测速软件)
  - [Lukcy （软路由公网神器）](/docs/4-常见网络应用-compose安装.md/#lukcy-软路由公网神器)
  - [ArozOS NAS 网页桌面操作系统](/docs/4-常见网络应用-compose安装.md/#arozos-nas-网页桌面操作系统)
  - [集客AC dockercompose](/docs/4-常见网络应用-compose安装.md/#集客ac-dockercompose)
  - [ddns-go dockercompose](/docs/4-常见网络应用-compose安装.md/#ddns-go-dockercompose)
  - [FRP 客户端（FRPC）](/docs/4-常见网络应用-compose安装.md/#frp-客户端frpc)
  - [FakeSIP、FakeHTTP](/docs/4-常见网络应用-compose安装.md/#fakesipfakehttp)
  - [netdata（性能、网络监控面板/仪表盘）](/docs/4-常见网络应用-compose安装.md/#netdata性能网络监控面板仪表盘)


