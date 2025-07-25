# Install_landscape_on_debian12_and_manage_compose_by_dpanel
在 debian12 中安装 landscape，并使用 dpanel 管理 docker compose。

## debian安装   
安装过程省略。   
建议：   
1、语言选择英文，避免中文路径与某些软件不兼容。   
2、安装 webserver 、sshserver、标准配置。         
![image](./images/1.png)   
# 时区修改到上海   

```
timedatectl list-timezones
timedatectl set-timezone Asia/Shanghai
#查看时区
timedatectl
```
   
# 开启 root ssh    

```
echo "PermitRootLogin yes" >>/etc/ssh/sshd_config

#重启 ssh   
systemctl restart ssh
```
# 升级内核，到 6.9以上   

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
# 脚本安装docker   

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
   
# 创建docker tcp    

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
# docker tcp 开启 TLS加密(略)

[DPanel 可视化 Docker 管理面板](https://dpanel.cc/#/zh-cn/manual/system/remote?id=%e4%bd%bf%e7%94%a8-https-%ef%bc%88%e5%bc%80%e5%90%af-tls-%ef%bc%89)    



   
# 安装 pppd   

```
apt update
apt install ppp -y
pppd -version
```
# 创建 landscape systemd 服务文件   

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

# 下载并上传 landscape-router  

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
# 修改网卡配置   

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
# 关闭本机 DNS 服务   

```
systemctl stop systemd-resolved
systemctl disable systemd-resolved
systemctl mask systemd-resolved
```
# 重启网络，并启动 landscape-router    
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

   
# 登录 landscape 账号 root 密码 root，https://IP:6443   
# 至此可以在 landscape-router web 中进行配置   
   

# 修改apache80端口到8080, 以免后续与其他反代软件冲突   

```
nano /etc/apache2/ports.conf
```
   
 listen 80 改到 8080   
```
systemctl restart apache2
```



   
# 如何升级 landscape   ？

```
# 关闭服务
systemctl stop landscape-router.service
```
替换 staic文件（解压、注意嵌套目录）   
landscape文件，并赋权   
```
# 启动服务，建议重启系统，避免出现奇奇怪怪的问题
systemctl start landscape-router.service
```
   
# 在显示器/终端中 启动/关闭  landscape-router   

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