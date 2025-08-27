# 用 dpanel 部署 dockercompose




## 使用 dpanel 的必要性
dpanel 集成 dockercompose 应用商店，便于一键部署容器应用。    
[dpanel 文档](https://dpanel.cc/#/zh-cn/install/docker) |
[dpanel 演示站/demo](https://dpanel.park1991.com/dpanel/ui/user/login)
##  dpanel标准版 与 dpanel lite 

标准版本中提供了域名绑定及证书功能，需要绑定 80 及 443 端口。Lite版与标准版只有镜像地址区别，除不再需要映射 80 及 443 端口外，其余配置均一致。  
个人推荐 lite 版，标准版额外功能网页相对简陋，何不traefik？如需更丰富的配置可使用 [Nginx UI](https://nginxui.com/zh_CN/guide/about.html)、[Nginx Proxy Manager](https://nginxproxymanager.com/)、[OpenResty Manager](https://om.uusec.com/cn/) 等项目。

## 安装 dpanel

[参看官方文档，三种方式任选一种（一键安装、docker、compose）](https://dpanel.cc/#/zh-cn/install/docker) 

## 在其他机器上使用 dpanel管理本机docker

### 创建docker tcp    

```shell
systemctl edit docker

```
添加下面几行  

```shell
[Service]
# 上面这一行必须要有
# 以下一行，配置全局时区为上海，新建容器自动配置，旧容器需重新创建容器。仍可在 docker run -e 环境变量中为容器指定其他时区 
Environment="TZ=Asia/Shanghai"
# 以下2行(可选)开启 dcoker tcp socket。（需注意 此处 未启用 tcl 加密，如需加密 参考 Dpanel 文档）
ExecStart=
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2375 -H fd:// --containerd=/run/containerd/containerd.sock
```
编辑结束后，先 `` ctrl + s `` 保存，再 `` ctrl + x `` 退出。
```shell
# 重启docker服务，需等待数十秒   
systemctl daemon-reload && systemctl restart docker
# 验证是否生效，输出有红框内容为正常
systemctl status docker

```


![image](./images/2.png)    
### docker tcp 开启 TLS加密(略)

[DPanel 可视化 Docker 管理面板](https://dpanel.cc/#/zh-cn/manual/system/remote?id=%e4%bd%bf%e7%94%a8-https-%ef%bc%88%e5%bc%80%e5%90%af-tls-%ef%bc%89)    


# Docker容器作为分流出口（接应容器部署）

## 接应容器概述  

* 仅搭配 [**接应程序**](https://github.com/ThisSeanZhang/landscape/blob/main/landscape-ebpf/src/bin/redirect_pkg_handler.rs) 进行打包的容器，可作为有效的流 **出口容器**  
* 可挂载任意程序在 `/app/server` 目录下作为 **工作程序**, 需要自行编写 `/app/server/run.sh` 脚本用于启动
* **工作程序** 需监听 `12345` 端口作为 tproxy 入口, 其他端口需要通过环境变量 `LAND_PROXY_SERVER_PORT` 修改 **接应程序** 默认监听端口
* **接应程序** 会将待处理流量转发到 **工作程序** 的 tproxy 入口 
* landscape 0.6.7+ 版本容器出口默认为 Flow 0 出口  
* tproxy 不改变数据包 SIP、SPort、DIP、DPort等字段，**工作程序** 仍可获取数据包"局域网信息"

## 接应程序配置
默认设置下， 容器有一个[**演示工作程序** ](https://github.com/ThisSeanZhang/landscape/blob/main/landscape-ebpf/src/bin/redirect_demo_server.rs) 放置在 `/app/server` 监听 `12345` 端口作为tproxy入口。

而 **接应程序** 是放置在 `/app`， 默认情况下是会将待处理流量转发到，演示 **工作程序** 监听端口 `12345`的tproxy入口。 可以通过设置容器的环境变量改变监听端口: `LAND_PROXY_SERVER_PORT`。

可将需要的 **工作程序** 挂载在 `/app/server` 目录下以替换 **演示工作程序**，将 **工作程序** 启动脚本挂载为 `/app/server/run.sh` ， `/app/start.sh` 默认会去执行`/app/server/run.sh`以启动 **工作程序** 或 **演示工作程序** 。


## 创建 worker_program 工作程序 启动脚本
**worker_program 可替换为任意 工作程序**
```shell
# 在 debina worker_program 目录中创建 worker_program 工作程序启动脚本
nano /home/worker_program/run.sh

```
```bash
#!/bin/bash

# 设置资源限制（也可在compose限制，不了解者可跳过这里）
# ulimit -n 1000000
# ulimit -u 500
# echo "设置资源限制成功"

# 启动审计程序守护进程
while true; do
    echo "启动 worker_program 工作程序..."
    /app/server/worker_program -d /app/server/config
    # 前一个为 worker_program 工作程序 二进制文件 后一个为 worker_program 工作程序 配置文件目录
    echo "worker_program 工作程序 异常退出，等待1秒后重新重启..."
    sleep 1
    # 下面检查 worker_program 工作程序 是否正常退出（可选，但推荐）
    if [[ $? -ne 0 ]]; then
        echo "worker_program 工作程序 进程异常退出，检查日志..."
        # 在这里添加日志检查或其他错误处理
        sleep 5
    fi
done
```
**编辑结束后，先 `` ctrl + s `` 保存，再 `` ctrl + x `` 退出。**  
<!--
## 为 Docker 容器启用 ipv6

**当前landscape 开启docker ipv6不会立即生效，没有主动发起 RS ，得等 上级 RA 的周期**  
**后续某一版本会解决这一问题**

```shell
# 容器开启 ipv6 ，容器访问互联网为 nat66 方式
# 已创建过 daemon.json 文件的，需用 nano /etc/docker/daemon.json 修改，不可使用以下 cat 写入
cat <<EOF > /etc/docker/daemon.json
{
  "ipv6": true,
  "fixed-cidr-v6": "fd00::/80"
}
EOF

``` 


```shell
# 重启 Docker，需等待数十秒
# 重启 Landscape Router
# 重启系统亦可
systemctl daemon-reload && systemctl restart docker
systemctl restart landscape-router.service

```
-->
## Docker 部署 单个 接应容器

**worker_program 可替换为任意 工作程序**

```shell
docker run -d \
  --name worker_program-1 \
  --sysctl net.ipv4.conf.lo.accept_local=1 \
  --cap-add=NET_ADMIN \
  --cap-add=BPF \
  --cap-add=PERFMON \
  --privileged \
  -p 外部端口:内部端口 \
  -v /root/.landscape-router/unix_link/:/ld_unix_link/:ro \ # 必要映射
  -v /home/worker_program/worker_program-1/run.sh:/app/server/run.sh \ # 修改左边挂载审计程序1启动脚本
  -v /home/worker_program/worker_program-1/config:/app/server/config \ # 修改左边挂载审计程序1配置文件
  -v /home/worker_program/worker_program-1/worker_program:/app/server/worker_program \ # 修改左边挂载审计程序1二进制文件
  ghcr.io/thisseanzhang/landscape-edge:amd64-xx # 需修改容器标签

```

## Compose 部署 多个 接应容器

**worker_program 可替换为任意 工作程序**  
**[enable_ipv6: true 时，docker配置中必须启用ipv6，否则会报错](#docker-启用-ipv6)**  
```yaml
networks:
  worker_program-br:
    driver: bridge
    enable_ipv6: true # 开启ipv6，容器自动获取ivp6配置（启用此项，docker配置中必须启用ipv6，否则会报错 /etc/docker/daemon.json）
    ipam:
      config:
        - subnet: 172.100.0.0/16
          gateway: 172.100.0.254
services:
  service-1:
    image: ghcr.io/thisseanzhang/landscape-edge:amd64-xx # 需修改容器标签
    sysctls:
      - net.ipv4.conf.lo.accept_local=1
    cap_add:
      - NET_ADMIN
      - BPF
      - PERFMON
    privileged: true
    restart: unless-stopped
    logging:
      options:
        max-size: "10m"
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 512M
    # 为启用 ports 配置时，使用容器ip:端口 即可在主机内访问容器web界面，主机外访问时需使用反代 或 端口映射到主机端口
    #ports: # 可选配置  # 静态映射，主要用于映射web端口
    #  - "0.0.0.0:外部端口号:内部端口号"        # 映射到主机v4端口
    #  - "[::]:外部端口号:内部端口号"        # 映射到主机v6端口
    networks:
      worker_program-br:
        ipv4_address: 172.100.0.1
    volumes:
      - /root/.landscape-router/unix_link/:/ld_unix_link/:ro # 必要映射
      - /home/worker_program/worker_program-1/:/app/server/
      # /home/worker_program/worker_program-1/ 目录下有 run.sh 启动脚本，config 配置文件，worker_program-1 二进制文件
  service-2:
    image: ghcr.io/thisseanzhang/landscape-edge:amd64-xx # 需修改容器标签
    sysctls:
      - net.ipv4.conf.lo.accept_local=1
    cap_add:
      - NET_ADMIN
      - BPF
      - PERFMON
    privileged: true
    restart: unless-stopped
    logging:
      options:
        max-size: "10m"
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 512M
    networks:
      worker_program-br:
        ipv4_address: 172.100.0.2
    volumes:
      - /root/.landscape-router/unix_link/:/ld_unix_link/:ro # 必要映射
      - /home/worker_program/worker_program-2/:/app/server/
      # /home/worker_program/worker_program-2/ 目录下有 run.sh 启动脚本，config 配置文件，worker_program-2 二进制文件

```

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

