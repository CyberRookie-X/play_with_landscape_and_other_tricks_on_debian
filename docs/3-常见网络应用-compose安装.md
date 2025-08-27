# 目录

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


# 常见网络应用、compose 安装
<!--
## Mosdns 广告拦截
[Mosdns-x github](https://github.com/pmkol/mosdns-x) | [Mosdns UI Github](https://github.com/Jimmyzxk/MosDNSUI)  |  [alickale/mosdnsui](https://hub.docker.com/r/alickale/mosdnsui)     
Mosdns-x 改编自 Mosdns v4 ，是一个用 Go 编写的高性能 DNS 转发器，支持运行插件流水线，用户可以按需定制 DNS 处理逻辑。
![alt text](images/mosdnsui1.png)
![alt text](images/mosdnsui2.png)
## 本教程配置细节
更详细配置请查询[alickale/mosdnsui 镜像 文档](https://hub.docker.com/r/alickale/mosdnsui) | [Mosdns-x 配置文档](https://github.com/pmkol/mosdns-x/wiki)
* 2路 dns 入站，
* 每路 dns 入站，独立缓存
* 第二路 dns ，通过 socks 代理 出站
* 每路 dns 配置4个上游 DNS，阿里 DoQ、114 DoQ、阿里 DoH、114 DoH 
* 每路 dns 配置 CN/全球 广告拦截
* 仅映射 UI 端口，DNS 仅在本机使用不端口
* 广告域名列表每9小时更新一次

## 下载 Mosdns-x 二进制文件
[Mosdns-x 下载](https://github.com/pmkol/mosdns-x/releases)


### docker 部署 Mosdns
```shell
docker run -d \
  --restart=unless-stopped \
  --network=host \
  --name=mosdnsui \
  -e CRON_SCHEDULE="0 1,9,17 * * *" \
  alickale/mosdnsui

```
### Compose 部署 Mosdns
```yaml
name: <your project name>
services:
    mosdnsui:
        restart: unless-stopped
        network_mode: host
        container_name: mosdnsui
        environment:
            - CRON_SCHEDULE=0 1,9,17 * * *
        image: alickale/mosdnsui
```
### docker 部署 Mosdns UI

### Compose 部署 Mosdns UI

-->
## filebrowser（文件管理）
 TODO
## tabby （网页ssh）
 TODO


## Homebox 局域网测速软件

[Homebox 官方仓库](https://github.com/XGHeaven/homebox)   
![image](./images/9.png)   
```shel
# docker 部署，host网络（性能更好）
docker run -d --network=host --name homebox xgheaven/homebox

```
```shel
# docker 部署，端口映射方式
docker run -d -p 3300:3300 --name homebox xgheaven/homebox

```
```yaml
# compose 部署，host网络（性能更好）
name: homebox
services:
    homebox:
        network_mode: host
        container_name: homebox
        image: xgheaven/homebox:latest

```
```yaml
# compose 部署,端口映射方式
name: homebox
services:
    homebox:
        ports:
            - 3300:3300
        container_name: homebox
        image: xgheaven/homebox:latest

```
安装并启动 xgheaven/homebox 镜像，默认情况下暴露的端口是 3300。 然后在浏览器中输入 http://your.server.ip:3300 即可。   

## Lukcy （软路由公网神器）

[Lucky 官方网站](https://lucky666.cn/docs/intro) | [Lucky github](https://github.com/gdy666/lucky)  

**需修改 -v 或 volumes 左边路径为宿主机配置文件路径**
```shell
# host模式, 同时支持IPv4/IPv6, Liunx系统推荐
docker run -d --name lucky --restart=always --net=host -v /home/luckyconf:/goodluck gdy666/lucky

# 桥接模式, 只支持IPv4, Mac/Windows推荐,windows 不推荐使用docker版本
docker run -d --name lucky --restart=always -p 16601:16601 -v /home/luckyconf:/goodluck gdy666/lucky
```

```yaml
name: lucky
services:
    lucky:
        container_name: lucky
        restart: unless-stopped
        network_mode: host
        volumes:
            - /home/luckyconf:/goodluck
        image: gdy666/lucky:latest
```

**Landscape 自有 防火墙 管理 ，需禁用 lucky 自动操作防火墙功能，避免发生冲突**  
**在 lucky里 `设置` -> `全局禁止操作防火墙` 拨到 绿色 Green**
![image](./images/12.png) 

## ArozOS NAS 网页桌面操作系统
ArozOS 少量路由器相关功能建议不开启    
[ArozOS官网](https://os.aroz.org/)|[ArozOS项目仓库](https://github.com/tobychui/arozos)

```shell
# 使用脚本在主机中安装（非docker版）
wget -O install.sh https://raw.githubusercontent.com/tobychui/arozos/master/installer/install.sh && bash install.sh

```

## 集客AC dockercompose

[集客ap最新固件下载（官网）](http://file.cnrouter.com/index.php/Index/apbeta.html#) | [集客ap固件历史版本下载](https://github.com/openwrt-fork/gecoos-firmware)

```yaml
name: gecoosac
services:
    gecoosac:
        network_mode: host
        privileged: true
        volumes:
            - /home/gecoosac:/data
            # 修改左边的/home/gecoosac为实际存放数据的目录
        environment:
            - UID=0
            - GID=0
            - GIDLIST=0
            - passwd=yourpassword
            # 修改右边密码
            - webport=8080
            # 管理端口默认8080，可修改之
        restart: always
        container_name: gecoosac
        image: tearsful/gecoosac:latest

```
**登录管理面板 http://192.168.22.1:8080**
## ddns-go dockercompose
```yaml
services:
  ddns-go:
    container_name: ddns-go
    restart: always
    network_mode: host
    ports:
      - 外部端口:9876
      # 修改左边的端口为ddns-go的web端口
    volumes:
      - /yourdir/data:/root
      # 修改左边的目录为ddns-go的data目录
    image: jeessy/ddns-go:latest

```

## FRP 客户端（FRPC）
### 本机安装
[官方文档](https://gofrp.org/zh-cn/docs/setup/systemd/)
### docker 方式安装安装

[基于 Docker 搭建 FRP 内网穿透开源项目（很简单哒）](https://www.cnblogs.com/hanzhe/p/18773973)

## FakeSIP、FakeHTTP

### 如何在 landscape-router 使用
* Landcsape-router 主机中，开启 eBPF 路由后，该功能可能不生效
* 在客户主机中安装任能生效，如 pt/bt 所在主机
### 简介
[FakeHTTP](https://github.com/MikeWang000000/FakeHTTP/wiki)  
FakeHTTP 可以将你的所有 TCP 连接伪装为 HTTP 等协议以规避深度包检测 (DPI)，是一个基于 nftables / iptables 与 Netfilter Queue (NFQUEUE) 的网络工具。

* 双方 TCP 通信时，您仅需在其中一端运行 FakeHTTP。
* 用于伪装的 TCP 报文会在传输的路途中被丢弃。
* FakeHTTP 不是网络隧道，它仅在 TCP 握手时工作。


[FakeSIP](https://github.com/MikeWang000000/FakeSIP/wiki)  
FakeSIP 可以将你的所有 UDP 流量伪装为 SIP 等协议以规避深度包检测 (DPI)，是一个基于 nftables / iptables 与 Netfilter Queue (NFQUEUE) 的网络工具。  

* 双方 UDP 通信时，您仅需在其中一端运行 FakeSIP。  
* 用于伪装的 UDP 报文会在传输的路途中被丢弃。  
* FakeSIP 不是网络隧道，它仅在 UDP 通信前期工作。  

```shell
# docker 安装FakeHTTP，在主机中生效（还有其他安装方式，参靠其官方github）
docker run --rm \
    --net=host \
    --cap-add CAP_NET_ADMIN \
    --cap-add CAP_NET_RAW \
    --cap-add CAP_SYS_MODULE \
    --cap-add CAP_SYS_NICE \
    nattertool/fakehttp -z -h www.example.com -i eth0
    # 需要增加一些域名

```

## netdata（性能、网络监控面板/仪表盘）
![image](./images/5.png)  
**登录 http://192.168.22.1:19999**
```yaml
services:
  netdata:
    image: netdata/netdata:latest
    container_name: netdata
    pid: host
    network_mode: host
    restart: unless-stopped
    cap_add:
      - SYS_PTRACE
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    volumes:
      - /home/netdata/netdataconfig:/etc/netdata #左边可修改
      - /home/netdata/netdatalib:/var/lib/netdata #左边可修改
      - /home/netdata/netdatacache:/var/cache/netdata #左边可修改
      - /:/host/root:ro,rslave
      - /etc/passwd:/host/etc/passwd:ro
      - /etc/group:/host/etc/group:ro
      - /etc/localtime:/etc/localtime:ro
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /etc/os-release:/host/etc/os-release:ro
      - /var/log:/host/var/log:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro

```
**登录 http://192.168.22.1:19999**
![image](./images/6.png)  

