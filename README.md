# 在debian里，玩转Landscape和其他花活（持续更新中...）
debian版本：12    
用户：root，非root用户请自行添加sudo    
[Landscape 文档网站](https://landscape.whileaway.dev/introduction.html) | [Landscape github](https://github.com/ThisSeanZhang/landscape)
# 目录
- [debian 安装](#debian-安装)
  - [debian安装](#debian-安装)
  - [时区修改到上海](#时区修改到上海)
  - [开启 root ssh](#开启-root-ssh)
  - [关闭 swap](#关闭-swap)
  - [升级内核，到 6.9以上](#升级内核到-69以上)
- [docker 安装](#docker-安装)
  - [脚本安装docker](#脚本安装docker)
- [landscape 安装](#landscape-安装)
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
- [dpanel 安装、配置](#dpanel-安装配置)
  - [使用 dpanel 的必要性](#使用-dpanel-的必要性)
  - [dpanel 与 dpanel lite](#dpanel-与-dpanel-lite)
  - [直接安装 dpanel](#直接安装-dpanel)
  - [容器安装 dpanel](#容器安装-dpanel)
  - [在其他机器上使用 dpanel管理本机docker](#在其他机器上使用-dpanel管理本机docker)
    - [创建docker tcp](#创建docker-tcp)
    - [docker tcp 开启 TLS加密(略)](#docker-tcp-开启-tls加密略)
- [常见网络应用、compose 安装](#常见网络应用compose-安装)
  - [ArozOS NAS 网页桌面操作系统](#arozos-nas-网页桌面操作系统)
  - [集客AC-dockercompose](#集客ac-dockercompose)
  - [ddns-go dockercompose](#ddns-go-dockercompose)
# debian 安装

## debian 安装   
安装过程省略。   
建议：   
1、语言选择英文，避免中文路径与某些软件不兼容。   
2、仅需 安装 webserver 、sshserver、标准配置。         
![image](./images/1.png)   
## 时区修改到上海   

```
timedatectl list-timezones
timedatectl set-timezone Asia/Shanghai
#查看时区
timedatectl
```
   
## 开启 root ssh    

```
echo "PermitRootLogin yes" >>/etc/ssh/sshd_config

#重启 ssh   
systemctl restart ssh
```

## 关闭 swap
### nano 用法简述
输入结束后，先 `` ctrl + s `` 保存，再 `` ctrl + x `` 退出。

### 注释或删除 Swap 挂载项
```
 nano /etc/fstab
```
找到包含 swap 的行（通常类似 /swapfile 或 /dev/mapper/...-swap），在行首添加 # 注释掉，例如：
```diff
- /swapfile none swap sw 0 0
+ #/swapfile none swap sw 0 0
```
### 禁用 systemd 管理的 Swap 单元（若有）
```
# 检查激活的 Swap 单元
systemctl --type swap

# 禁用所有 Swap 单元（替换 UNIT_NAME 为实际名称）
 systemctl mask UNIT_NAME.swap
```

## 升级内核，到 6.9以上   

```
apt update
apt search linux-image-6.12
```

```
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
# docker 安装

## 脚本安装docker   

注释掉原有所有行，换掉下面的源。如已选择合适的源则可跳过。   
```
# 修改软件源
nano /etc/apt/sources.list
```
```
deb https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware

deb https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm-updates main contrib non-free non-free-firmware

deb https://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian/ bookworm-backports main contrib non-free non-free-firmware

deb https://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
deb-src https://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware
```
安装curl   
```
apt update
apt install curl -y
curl --version

```
   
```
# 三种方式，选择一种
# 使用官方源安装（国内直接访问较慢）
curl -fsSL https://get.docker.com | bash
# 使用阿里源安装
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
# 使用中国区 Azure 源安装
curl -fsSL https://get.docker.com | bash -s docker --mirror AzureChinaCloud
```
返回docker版本信息即为成功   
   
# landscape 安装

## 创建 landscape systemd 服务文件   

```
nano /etc/systemd/system/landscape-router.service
```

```
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
```
#创建landscape-router目录。   
cd /root
mkdir /root/.landscape-router
cd /root/.landscape-router
```
```
#上传文件后，赋权
chmod -R 755 /root/.landscape-router
```
## 修改网卡配置   

将 LAN 网卡全设置为 manual 后, 将 WAN 的网卡额外在配置文件中设置一个静态 IP, 方便即使路由程序出现故障时, 使用另外一台机器设置静态 IP 后也能进行访问。 使用另外一台主机设置为 192.168.22.0/24 网段的任意地址 (比如: 192.168.22.2/24) , 直连这个网口, 就能连上路由器。   
   
```
nano /etc/network/interfaces
```
```
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

```
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl mask systemd-resolved
```
## 重启网络，并启动 landscape-router    
```
# landscape-router 开机启动
systemctl enable landscape-router.service
```
```
# 重启网络，并启动 landscape-router
systemctl restart networking && systemctl start landscape-router.service
```
通过端口，检查landsape 检查是是否成功启动，寻找6300、6400端口，   
```
ss -nutlp
```

   
## 登录 landscape 账号 root 密码 root，https://IP:6443   
## 至此可以在 landscape-router web 中进行配置   
   

## 修改apache80端口到8080, 以免后续与其他反代软件冲突   

```
nano /etc/apache2/ports.conf
```
   
 listen 80 改到 8080   
```
systemctl restart apache2
```



   
## 如何升级 landscape   ？

```
# 关闭服务
systemctl stop landscape-router.service
```
替换 staic目录（解压、注意嵌套目录）   
替换 landscape文件，并赋权   
```
# 启动服务，建议重启系统，避免出现奇奇怪怪的问题
systemctl start landscape-router.service
```
   
## 在显示器/终端中 启动/关闭 landscape-router   

需要对landscape 先赋予执行权限   
```
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
##  dpanel 与 dpanel lite 

## 直接安装 dpanel

## 容器安装 dpanel

## 在其他机器上使用 dpanel管理本机docker

### 创建docker tcp    

```
systemctl edit docker
```
添加下面几行  
```
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd -H tcp://0.0.0.0:2375 -H fd:// --containerd=/run/containerd/containerd.sock
```
重启docker服务   
```
systemctl daemon-reload && systemctl restart docker
```
```
#验证是否生效，输出有红框内容为正常
systemctl status docker
```


![image](./images/2.png)    
### docker tcp 开启 TLS加密(略)

[DPanel 可视化 Docker 管理面板](https://dpanel.cc/#/zh-cn/manual/system/remote?id=%e4%bd%bf%e7%94%a8-https-%ef%bc%88%e5%bc%80%e5%90%af-tls-%ef%bc%89)    



# 常见网络应用、compose 安装
## ArozOS NAS 网页桌面操作系统
ArozOS 少量路由器相关功能建议不开启    
[ArozOS项目仓库](https://github.com/ArozOS/ArozOS)|[ArozOS官网](https://os.aroz.org/)

```
# 使用脚本在主机中安装（非docker版）
wget -O install.sh https://raw.githubusercontent.com/tobychui/arozos/master/installer/install.sh && bash install.sh
```
## 集客AC-dockercompose

```
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
```
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

