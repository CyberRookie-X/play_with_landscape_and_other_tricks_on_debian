# 在 Debian 里，玩转 Landscape Router 和其他花活（持续更新中...）

**本文可自由转载，无需标注出处**  
[Landscape Router 文档网站](https://landscape.whileaway.dev/introduction.html) | [Landscape Router github](https://github.com/ThisSeanZhang/landscape)


**本教程已适配中国大陆网络** 

## 安装过程并不复杂，复制命令粘贴到SSH终端执行即可

## 核心特性
* 分流控制（SIP、QoS(dscp)、DIP、域名、Geo 匹配规则）
* eBPF 路由
* 每个流 Flow 独立 dns 配置以及缓存（避免 dns 污染、泄露）
* 流量导入 Docker 容器
* Geo 管理

## 内核版本兼容的 常见 Linux 发行版  
✅ 内核版本兼容  
🟢 部分版本的内核版本兼容  
❌ 内核版本不兼容  
**需要 GNU libc（GLIBC）标准库才能运行，内核版本6.9+才能使用全部功能（6.6可能也可以，未明确）**


| 发行版 | 兼容 | 版本要求 | 备注 |  
|---|---|---|---|  
| Debian  | ✅ | 13+ | 低版本需更新内核至6.9+ |  
| Ubuntu | ✅ | 25.04+ | 低版本需更新内核至6.9+|  
| PVE | ✅ | 9+ | 低版本需更新内核至6.9+|  
| OMV | ✅ | 8+ | 低版本需更新内核至6.9+| 
| Armbian | 🟢 |  | 需内核版本6.9+|  
| FnOS | ❌ |  | 内核限制 |  
| OpenWRT | ❌ |  | 非GLIBC无法兼容 |  
| Alpine | ❌ |  | 非GLIBC无法兼容 |  
<!--⚠️ 调整后可兼容-->
<!--🟡 未知  -->
``` shell
# 查看内核版本
uname -r

```
``` shell
# 输出带有 GLIBC 或 GNU libc 支持，带有 musl libc 则不支持
ldd --version

```
# 手工安装指南 [文档](/docs/1-手工安装指南.md)

# Docker容器作为分流出口（接应容器部署）[文档](/docs/2-Docker容器作为分流出口-接应容器.md)

# 常见网络应用、compose 安装 [文档](/docs/3-常见网络应用-compose安装.md)

# 文档目录
- [Debian 安装配置（机器能连中国网络即可）](/docs/1-手工安装指南.md/#debian-安装配置机器能连中国网络即可)
  - [下载 debian  ISO 镜像](/docs/1-手工安装指南.md/#下载必要软件)
  - [安装 debian](/docs/1-手工安装指南.md/#安装-debian)
  - [时区修改到上海](/docs/1-手工安装指南.md/#时区修改到上海)
  - [允许root用户使用密码登录ssh](/docs/1-手工安装指南.md/#允许root用户使用密码登录ssh)
  - [关闭 swap](/docs/1-手工安装指南.md/#关闭-swap)
  - [修改软件源（可选）](#修改软件源可选)
  - [升级内核，到 6.9以上（debian 13 无需升级内核）](/docs/1-手工安装指南.md/#升级内核到-69以上debian-13-无需升级内核)
- [安装 docker、docker compose（机器能连中国网络即可） ](/docs/1-手工安装指南.md/#安装-dockerdocker-compose机器能连中国网络即可)
- [Landscape Router 安装（机器能连中国网络即可）](/docs/1-手工安装指南.md/#landscape-安装机器能连中国网络即可)
  - [安装 pppd](/docs/1-手工安装指南.md/#安装-pppd)
  - [创建 landscape systemd 服务文件](/docs/1-手工安装指南.md/#创建-landscape-systemd-服务文件)
  - [下载并上传 landscape-router](/docs/1-手工安装指南.md/#下载并上传-landscape-router)
  - [修改网卡配置](/docs/1-手工安装指南.md/#修改网卡配置)
  - [关闭本机 DNS 服务](/docs/1-手工安装指南.md/#关闭本机-dns-服务)
  - [重启网络，并启动 landscape-router](/docs/1-手工安装指南.md/#重启网络并启动-landscape-router)
  - [登录 landscape 账号 root 密码 root，https://192.168.22.1:6443](/docs/1-手工安装指南.md/#登录-landscape-账号-root-密码-roothttps1921682216443)
  - [至此可以在 landscape-router web 中进行配置](/docs/1-手工安装指南.md/#至此可以在-landscape-router-web-中进行配置)
  - [应用 Landscape-Router 开机启动](/docs/1-手工安装指南.md/#应用-landscape-router-开机启动)
  - [修改apache80端口到8080, 以免后续与其他反代软件冲突](/docs/1-手工安装指南.md/#修改apache80端口到8080-以免后续与其他反代软件冲突)
  - [如何升级 landscape](/docs/1-手工安装指南.md/#如何升级-landscape)
  - [在显示器/终端中 启动/关闭 landscape-router](/docs/1-手工安装指南.md/#在显示器终端中-启动关闭-landscape-router)
- [Landscape 实战案例](/docs/1-手工安装指南.md/#landscape-实战案例)
  - [域名/IP 分流实践](/docs/1-手工安装指南.md/#域名ip-分流实践)
  - [基于 vlan/ssid（WiFi） 的分流实现（暂不能实现）](/docs/1-手工安装指南.md/#基于-vlanssidwifi-的分流实现暂不能实现)
- [用 dpanel 部署 dockercompose](/docs/2-Docker容器作为分流出口-接应容器.md/#用-dpanel-部署-dockercompose)
  - [使用 dpanel 的必要性](/docs/2-Docker容器作为分流出口-接应容器.md/#使用-dpanel-的必要性)
  - [dpanel标准版 与 dpanel lite](/docs/2-Docker容器作为分流出口-接应容器.md/#dpanel标准版-与-dpanel-lite)
  - [安装 dpanel](/docs/2-Docker容器作为分流出口-接应容器.md/#安装-dpanel)
  - [在其他机器上使用 dpanel管理本机docker](/docs/2-Docker容器作为分流出口-接应容器.md//#在其他机器上使用-dpanel管理本机docker)
- [Docker容器作为分流出口（接应容器部署）](/docs/2-Docker容器作为分流出口-接应容器.md/#docker容器作为分流出口接应容器部署)
  - [接应容器概述](/docs/2-Docker容器作为分流出口-接应容器.md/#接应容器概述)
  - [创建 worker_program 工作程序 启动脚本](/docs/2-Docker容器作为分流出口-接应容器.md/#创建-worker_program-工作程序-启动脚本)
  - [为 Docker 容器启用 ipv6](/docs/2-Docker容器作为分流出口-接应容器.md/#为-docker-容器启用-ipv6)
  - [Docker 部署 单个 接应容器](/docs/2-Docker容器作为分流出口-接应容器.md/#docker-部署-单个-接应容器)
  - [Compose 部署 多个 接应容器](/docs/2-Docker容器作为分流出口-接应容器.md//#compose-部署-多个-接应容器)
- [常见网络应用、compose 安装](/docs/3-常见网络应用-compose安装.md/#常见网络应用compose-安装)
  - [filebrowser（文件管理）](/docs/3-常见网络应用-compose安装.md/#filebrowser文件管理)
  - [tabby （网页ssh）](/docs/3-常见网络应用-compose安装.md/#tabby-网页ssh)
  - [Homebox 局域网测速软件](/docs/3-常见网络应用-compose安装.md/#homebox-局域网测速软件)
  - [Lukcy （软路由公网神器）](/docs/3-常见网络应用-compose安装.md/#lukcy-软路由公网神器)
  - [ArozOS NAS 网页桌面操作系统](/docs/3-常见网络应用-compose安装.md/#arozos-nas-网页桌面操作系统)
  - [集客AC dockercompose](/docs/3-常见网络应用-compose安装.md/#集客ac-dockercompose)
  - [ddns-go dockercompose](/docs/3-常见网络应用-compose安装.md/#ddns-go-dockercompose)
  - [FRP 客户端（FRPC）](/docs/3-常见网络应用-compose安装.md/#frp-客户端frpc)
  - [FakeSIP、FakeHTTP](/docs/3-常见网络应用-compose安装.md/#fakesipfakehttp)
  - [netdata（性能、网络监控面板/仪表盘）](/docs/3-常见网络应用-compose安装.md/#netdata性能网络监控面板仪表盘)


