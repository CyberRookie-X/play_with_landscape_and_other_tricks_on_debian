# 在debian里，玩转Landscape和其他花活（持续更新中...）
debian版本：12    
用户：root，非root用户请自行添加sudo    
[Landscape 文档网站](https://landscape.whileaway.dev/introduction.html) | [Landscape github](https://github.com/ThisSeanZhang/landscape)

# 本教程适用于 debian、ubuntu 及其部分衍生版本，例如 PVE、FnOS

# 目录
- [debian 安装](#debian-安装)
  - [debian 安装](#debian-安装-1)
  - [时区修改到上海](#时区修改到上海)
  - [允许root用户使用密码登录ssh](#允许root用户使用密码登录ssh)
  - [关闭 swap](#关闭-swap)
  - [修改软件源（可选）](#修改软件源可选)
  - [升级内核，到 6.9以上](#升级内核到-69以上)
  - [重启系统生效](#重启系统生效)
- [docker、docker compose 安装](#dockerdocker-compose-安装)
- [landscape 安装](#landscape-安装)
  - [安装 pppd](#安装-pppd)
  - [创建 landscape systemd 服务文件](#创建-landscape-systemd-服务文件)
  - [下载并上传 landscape-router](#下载并上传-landscape-router)
  - [修改网卡配置](#修改网卡配置)
  - [关闭本机 DNS 服务](#关闭本机-dns-服务)
  - [重启网络，并启动 landscape-router](#重启网络并启动-landscape-router)
  - [登录 landscape 账号 root 密码 root，https://IP:6443](#登录-landscape-账号-root-密码-roothttpsip6443)
  - [至此可以在 landscape-router web 中进行配置](#至此可以在-landscape-router-web-中进行配置)
  - [修改apache80端口到8080, 以免后续与其他反代软件冲突](#修改apache80端口到8080-以免后续与其他反代软件冲突)
  - [如何升级 landscape](#如何升级-landscape)
  - [在显示器/终端中 启动/关闭 landscape-router](#在显示器终端中-启动关闭-landscape-router)
- [landscape 使用](#landscape-使用)
- [用 dpanel 部署 dockercompose](#用-dpanel-部署-dockercompose)
  - [使用 dpanel 的必要性](#使用-dpanel-的必要性)
  - [dpanel标准版 与 dpanel lite](#dpanel标准版-与-dpanel-lite)
  - [直接安装 dpanel](#直接安装-dpanel)
  - [容器安装 dpanel](#容器安装-dpanel)
  - [在其他机器上使用 dpanel管理本机docker](#在其他机器上使用-dpanel管理本机docker)
- [用 docker compose 部署"接应容器"](#用-docker-compose-部署接应容器)
  - [接应容器概述](#接应容器概述)
  - [下面以审计程序为例，介绍接应容器部署](#下面以审计程序为例介绍接应容器部署)
  - [创建审计程序启动脚本](#创建审计程序启动脚本)
  - [端口映射方式 部署审计容器-compose](#端口映射方式-部署审计容器-compose)
  - [独立网桥方式 部署审计容器-compose](#独立网桥方式-部署审计容器-compose)
- [常见网络应用、compose 安装](#常见网络应用compose-安装)
  - [ArozOS NAS 网页桌面操作系统](#arozos-nas-网页桌面操作系统)
  - [集客AC dockercompose](#集客ac-dockercompose)
  - [ddns-go dockercompose](#ddns-go-dockercompose)

# debian 安

## debian 安装   
安装过程省略。   
建议：   
1、语言选择 us/english，避免中文路径与某些软件不兼容,（后面再调整时区到上海）。   
2、仅需 安装 webserver 、sshserver、标准配置。         
![image](./images/1.png)   
## 时区修改到上海   

```shell
#设置时区为上海
timedatectl set-timezone Asia/Shanghai
#查看时区
timedatectl
```
   
## 允许root用户使用密码登录ssh    

```shell
echo "PermitRootLogin yes" >>/etc/ssh/sshd_config

#重启 ssh   
systemctl restart ssh
```

## 关闭 swap
### nano 用法简述
输入结束后，先 `` ctrl + s `` 保存，再 `` ctrl + x `` 退出。

### 注释或删除 Swap 挂载项
```shell
nano /etc/fstab
```
找到包含 swap 的行（通常类似 /swapfile 或 /dev/mapper/...-swap），在行首添加 # 注释掉，例如：
```diff
- /swapfile none swap sw 0 0
+ #/swapfile none swap sw 0 0
```
### 禁用 systemd 管理的 Swap 单元（若有）
```shell
# 检查激活的 Swap 单元
systemctl --type swap

# 禁用所有 Swap 单元（替换 UNIT_NAME 为实际名称）
systemctl mask UNIT_NAME.swap
```
## 修改软件源（可选）
```shell
# 若软件源非为国内源，可以考虑修改软件源为国内源，例如ustc源
nano /etc/apt/sources.list
```
```shell
# ustc源
deb https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware

deb https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware

deb https://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware

deb https://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
```
## 升级内核，到 6.9以上   

```shell
apt update
apt search linux-image-6.12
```

```shell
# 安装内核镜像及头文件（指定 Backports 源）
apt install -t bookworm-backports \
    linux-image-6.12.30+bpo-amd64 \
    linux-headers-6.12.30+bpo-amd64

# 安装失败就问AI，6.9以上即可。   

# 更新 GRUB 引导配置
update-grub

# 重启系统生效
reboot
```
# docker、docker compose 安装

注释掉原有所有行，换掉下面的源。如已选择合适的源则可跳过。   
```shell
#安装curl   
apt update
apt install curl -y
curl --version

```
   
```shell
# 三种方式，选择一种(已包含dockercompose)
# 使用官方源安装（国内直接访问较慢）
curl -fsSL https://get.docker.com | bash
# 使用阿里源安装
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
# 使用中国区 Azure 源安装
curl -fsSL https://get.docker.com | bash -s docker --mirror AzureChinaCloud
```
返回docker版本信息即为成功   
   
# landscape 安装

## 安装 pppd
```shell
apt install ppp -y
pppd -version

```

## 创建 landscape systemd 服务文件   

```shell
nano /etc/systemd/system/landscape-router.service
```

```shell
[Unit]
Description=Landscape Router

[Service]
ExecStart=/root/.landscape-router/landscape-webserver-x86_64
# 注意这个路径与下面创建的landscape-router目录相同。
Restart=always
User=root
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
```

## 下载并上传 landscape-router  

[Releases · ThisSeanZhang/landscape](https://github.com/ThisSeanZhang/landscape/releases/)    
下载 x86 和 static，放到下面创建的目录 。
```shell
#创建landscape-router目录。   
cd /root
mkdir /root/.landscape-router
cd /root/.landscape-router
```
```shell
#上传文件后，赋权
chmod -R 755 /root/.landscape-router
```
## 修改网卡配置   

将 LAN 网卡全设置为 manual 后, 将 WAN 的网卡额外在配置文件中设置一个静态 IP, 方便即使路由程序出现故障时, 使用另外一台机器设置静态 IP 后也能进行访问。 使用另外一台主机设置为 192.168.22.0/24 网段的任意地址 (比如: 192.168.22.2/24) , 直连这个网口, 就能连上路由器。   
```shell
# 获取网卡名
ip a
```

```shell
nano /etc/network/interfaces
```
```shell
auto <第一张网卡名> <- 比如设置为 WAN
iface <第一张网卡名> inet static
    address 192.168.22.1
    netmask 255.255.255.0

auto <第二张网卡名> <- 以下都是 LAN
iface <第二张网卡名> inet manual

auto <第三张网卡名>
iface <第三张网卡名> inet manual
```
## 关闭本机 DNS 服务   

```shell
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl mask systemd-resolved
```
## 重启网络，并启动 landscape-router    
```shell
# landscape-router 开机启动
systemctl enable landscape-router.service
```
```shell
# 重启网络，并启动 landscape-router
systemctl restart networking && systemctl start landscape-router.service
```
通过端口，检查landsape 检查是是否成功启动，寻找6300、6400端口，   
```shell
ss -nutlp
```

   
## 登录 landscape 账号 root 密码 root，https://IP:6443   
## 至此可以在 landscape-router web 中进行配置   
   

## 修改apache80端口到8080, 以免后续与其他反代软件冲突   

```shell
nano /etc/apache2/ports.conf
```
   
listen 由 80 改到 8080   
```shell
systemctl restart apache2
```



   
## 如何升级 landscape   ？

```shell
# 关闭服务
systemctl stop landscape-router.service
```
替换 staic目录（解压、注意嵌套目录）   
替换 landscape文件，并赋权   
```shell
# 启动服务，建议重启系统，避免出现奇奇怪怪的问题
systemctl start landscape-router.service
```
   
## 在显示器/终端中 启动/关闭 landscape-router   

需要对landscape 先赋予执行权限   
```shell
# 启动服务
systemctl start landscape-router.service
# 重启服务
systemctl restart landscape-router.service
# 停止服务
systemctl stop landscape-router.service
# 开机启动服务 ( 确认没有问题之后执行 )
systemctl enable landscape-router.service
# 开机启动服务 ( 确认没有问题之后执行 )
systemctl disable landscape-router.service
```
# landscape 使用
太多了懒写

# 用 dpanel 部署 dockercompose

## 使用 dpanel 的必要性
dpanel 集成 dockercompose 应用商店，便于一键部署容器应用。    
[dpanel 文档](https://dpanel.cc/#/zh-cn/install/docker) |
[dpanel 演示站/demo](https://dpanel.park1991.com/dpanel/ui/user/login)
##  dpanel标准版 与 dpanel lite 

标准版本中提供了域名绑定及证书功能，需要绑定 80 及 443 端口。Lite版与标准版只有镜像地址区别，除不再需要映射 80 及 443 端口外，其余配置均一致。  
个人推荐 lite 版，标准版额外功能网页相对简陋，何不traefik？如需更丰富的配置可使用 [Nginx UI](https://nginxui.com/zh_CN/guide/about.html)、[Nginx Proxy Manager](https://nginxproxymanager.com/)、[OpenResty Manager](https://om.uusec.com/cn/) 等项目。

## 直接安装 dpanel

## 容器安装 dpanel

## 在其他机器上使用 dpanel管理本机docker

### 创建docker tcp    

```shell
systemctl edit docker
```
添加下面几行  
```shell
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2375 -H fd:// --containerd=/run/containerd/containerd.sock
```
```shell
#重启docker服务   
systemctl daemon-reload && systemctl restart docker
#验证是否生效，输出有红框内容为正常
systemctl status docker
```


![image](./images/2.png)    
### docker tcp 开启 TLS加密(略)

[DPanel 可视化 Docker 管理面板](https://dpanel.cc/#/zh-cn/manual/system/remote?id=%e4%bd%bf%e7%94%a8-https-%ef%bc%88%e5%bc%80%e5%90%af-tls-%ef%bc%89)    


# 用 docker compose 部署“接应容器”

## 接应容器概述
1、接应容器内可挂载任意具有tproxy入口的程序，如流量镜像审计程序、流量统计程序、防火墙、蜜罐等。
2、接应容器内，通过 run.sh 脚本启动 特定程序。
3、landscape 中重定向流量至容器。
4、接应程序将流量转发至特定程序tproxy端口，交由特定程序处理。
4、landscape 0.6.8 版本接应容器出口默认为flow 0出口。

## 接应程序配置
默认设置下， 容器有一个[演示程序](https://github.com/ThisSeanZhang/landscape/blob/main/landscape-ebpf/src/bin/redirect_demo_server.rs) 放置在 `/app/server` 监听 `12345` 端口。

而接应程序是放置在 `/app`， 默认情况下是会将待处理流量转发到，演示程序监听的端口 `12345`。 可以通过设置容器的环境变量改变监听端口: `LAND_PROXY_SERVER_PORT`

可将需要的程序挂载在 `/app/server` 目录下， `/app/start.sh` 默认会去执行 `/app/server/run.sh` 脚本。

## 下面以审计程序为例，介绍接应容器部署
## 创建审计程序启动脚本
```bash
#!/bin/bash

ip rule add fwmark 0x1/0x1 lookup 100
ip route add local default dev lo table 100

# 启动审计程序守护进程
while true; do
    echo "启动 审计程序..."
    /app/server/audit -d /app/server/config
	# 前一个为审计程序二进制文件 后一个为审计程序配置文件目录
    echo "审计程序 异常退出，等待1秒后重新重启..."
    sleep 1
    # 检查 审计程序 是否正常退出（可选，但推荐）
    if [[ $? -ne 0 ]]; then
        echo "审计程序 进程异常退出，检查日志..."
        # 在这里添加日志检查或其他错误处理
        sleep 5
    fi
done
```
## 端口映射方式 部署审计容器-compose
```yaml
services:
  audit-1:
    image: ghcr.io/thisseanzhang/landscape-edge:amd64-xx #需修改容器标签
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
          memory: 128M
    ports:
      - "外部端口号:内部端口号"        # 静态映射，主要用于映射web端口
    volumes:
      - /root/.landscape-router/unix_link/:/ld_unix_link/:ro # 必要映射
      - /home/audit/audit-1/run.sh:/app/server/run.sh # 修改左边挂载审计程序1启动脚本
      - /home/audit/audit-1/config:/app/server/config # 修改左边挂载审计程序1配置文件
      - /home/audit/audit-1/audit:/app/server/audit # 修改左边挂载审计程序1二进制文件
  audit-2:
    image: ghcr.io/thisseanzhang/landscape-edge:amd64-xx #需修改容器标签
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
          memory: 128M
    ports:
      - "外部端口号:内部端口号"        # 静态映射，主要用于映射web端口
    volumes:
      - /root/.landscape-router/unix_link/:/ld_unix_link/:ro # 必要映射
      - /home/audit/audit-2/run.sh:/app/server/run.sh # 挂载审计程序2启动脚本
      - /home/audit/audit-2/config:/app/server/config # 挂载审计程序2配置文件
      - /home/audit/audit-2/audit:/app/server/audit # 挂载审计程序2二进制文件
```
## 独立网桥方式 部署审计容器-compose
```yaml
networks:
  audit-br:
    driver: bridge
    ipam:
      config:
        - subnet: 172.100.0.0/16
          gateway: 172.100.0.254
services:
  service-1:
    image: ghcr.io/thisseanzhang/landscape-edge:amd64-xx #需修改容器标签
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
          memory: 128M
    networks:
      audit-br:
        ipv4_address: 172.100.0.1
    volumes:
      - /root/.landscape-router/unix_link/:/ld_unix_link/:ro # 必要映射
      - /home/audit/audit-1/run.sh:/app/server/run.sh # 挂载审计程序1启动脚本
      - /home/audit/audit-1/config:/app/server/config # 挂载审计程序1配置文件
      - /home/audit/audit-1/audit:/app/server/audit # 挂载审计程序1二进制文件
  service-2:
    image: ghcr.io/thisseanzhang/landscape-edge:amd64-xx #需修改容器标签
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
          memory: 128M
    networks:
      audit-br:
        ipv4_address: 172.100.0.2
    volumes:
      - /root/.landscape-router/unix_link/:/ld_unix_link/:ro # 必要映射
      - /home/audit/audit-2/run.sh:/app/server/run.sh # 挂载审计程序2启动脚本
      - /home/audit/audit-2/config:/app/server/config # 挂载审计程序2配置文件
      - /home/audit/audit-2/audit:/app/server/audit # 挂载审计程序2二进制文件

```

# 常见网络应用、compose 安装
## ArozOS NAS 网页桌面操作系统
ArozOS 少量路由器相关功能建议不开启    
[ArozOS官网](https://os.aroz.org/)|[ArozOS项目仓库](https://github.com/tobychui/arozos)

```shell
# 使用脚本在主机中安装（非docker版）
wget -O install.sh https://raw.githubusercontent.com/tobychui/arozos/master/installer/install.sh && bash install.sh
```
## 集客AC dockercompose

```yaml
name: gecoosac
services:
    gecoosac:
        network_mode: host
        privileged: true
        volumes:
            - /home/gecoosac:/data
            #修改左边的/home/gecoosac为实际存放数据的目录
        environment:
            - UID=0
            - GID=0
            - GIDLIST=0
            - passwd=yourpassword
            #修改右边密码
            - webport=20275
        restart: always
        container_name: gecoosac
        image: tearsful/gecoosac:latest
```

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
      #修改左边的目录为ddns-go的data目录
    image: jeessy/ddns-go:latest

```

