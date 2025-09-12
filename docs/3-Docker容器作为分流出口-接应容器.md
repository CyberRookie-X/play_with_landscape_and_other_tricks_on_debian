![](/images/13.png)

# 目录   

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





# **debian用户：root，非 root 用户请自行添加 sudo**   
**本教程已适配中国大陆网络** 

# 流行 docker、dockercompose 管理工具

## 管理面板
### [Dpanel（中国大陆用户推荐）](https://dpanel.cc/install/shell)  
### [Dockge](https://dockge.kuma.pet/)  
### [Dockerman](https://dockman.radn.dev/)  

## docker run <=> compose.yaml 命令转换

### *[composerize（建议收藏这个网站）](https://www.composerize.com/)*

# 用 dpanel 部署 dockercompose

## 使用 dpanel 的必要性
* 中国大陆作者开发，适应中国大陆用户使用习惯
* 便捷的镜像加速配置，在 主路由中，便于拉取docker镜像

* 图形界面管理 compose、image、容器  
* dpanel 集成 dockercompose 应用商店，便于一键部署容器应用。    
[dpanel 文档](https://dpanel.cc/install/docker) |
[dpanel 演示站/demo](https://dpanel.park1991.com/dpanel/ui/user/login)
##  dpanel标准版 与 dpanel lite 

标准版本中提供了域名绑定及证书功能，需要绑定 80 及 443 端口。Lite版与标准版只有镜像地址区别，除不再需要映射 80 及 443 端口外，其余配置均一致。  
个人推荐 lite 版，标准版额外功能网页相对简陋，何不 traefik ？如需更丰富的配置可使用 [lucky](https://lucky666.cn/)、[Nginx UI](https://nginxui.com/zh_CN/guide/about.html)、[Nginx Proxy Manager](https://nginxproxymanager.com/)、[OpenResty Manager](https://om.uusec.com/cn/) 等软件。

## 安装 dpanel


**⚠ 请勿使用 landscape UI 中的 `拉取镜像` 按钮**
```shell
# 复制这条命令到 ssh 中执行
# 通过 阿里云拉取 dpanel:lite
docker pull registry.cn-hangzhou.aliyuncs.com/dpanel/dpanel:lite

```
![](/images/15.png)
**⚠ 请勿使用 landscape UI 中的 `拉取镜像` 按钮**
![](/images/16.png)

**复制以下内容，按下图填入对应位置，以创建 dpanel 容器**
```shell
dpanel
18080
8080
APP_NAME
dpanel
/var/run/docker.sock
/var/run/docker.sock
/home/dpanel
/dpanel
```
![](/images/17.png)

<!--
## 在其他机器上使用 dpanel管理本机docker（不推荐）

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
![image](/images/2.png)    

### docker tcp 开启 TLS加密(略)

[DPanel 可视化 Docker 管理面板](https://dpanel.cc/#/zh-cn/manual/system/remote?id=%e4%bd%bf%e7%94%a8-https-%ef%bc%88%e5%bc%80%e5%90%af-tls-%ef%bc%89)    
-->

# 配置 dpanel
## 登录并创建管理员账号
```shell
http://192.168.22.1:18080
```
## 配置镜像加速
### **参考 Dpanel 官方 [视频教程](https://www.bilibili.com/video/BV1WDiFexEc6/?t=73)**
### 常用 docker.io（docker hub） 镜像加速   

* 仓库地址 填这个 ↓
```shell
docker.io
```
* 加速地址 填这个 ↓
```shell
docker.m.daocloud.io
docker.1panel.live
docker.1ms.run
```
### 常用 ghcr.io（github） 镜像加速   

* 仓库地址 填这个 ↓
```shell
ghcr.io
```
* 加速地址 填这个 ↓
```shell
ghcr.m.daocloud.io
ghcr.nju.edu.cn
```


![图片来自 dpanel 文档](/images/18.png)

# Docker容器作为分流出口 —— 包装脚本方式部署（推荐）

## 原理概述
1. 通过 dockerfile 或 docker inspect 获取 镜像 原本的 ENTRYPOINT 和 CMD
2. 通过包装脚本覆盖容器原本的 ENTRYPOINT，将 原本的 ENTRYPOINT 和 CMD 传递给 包装脚本
3. 脚本 检测/安装 所需依赖（脚本会为 CN 地区用户换源）
4. 启动 redirect_pkg_handler
5. 启动 容器 原本的 ENTRYPOINT 和 CMD

## 下载 包装脚本 和 handler
* 根据 CPU 架构、镜像 OS 发行版 下载 合适的 redirect_pkg_handler
* alpine 镜像 下载 musl 版，debian/ubunt 镜像 下载普通版（glibc）
* 解压并上传到 Landscape Router 安装路径下
* 为 包装脚本 和 handler 赋予可执行权限,如 755


包装脚本 [下载连接](https://github.com/CyberRookie-X/play_with_landscape_and_other_tricks_on_debian/blob/main/redirect_pkg_handler.sh) | redirect_pkg_handler [下载连接](https://github.com/ThisSeanZhang/landscape/releases)  

![](/images/19.png)

## 包装脚本环境变量说明

* 环境变量只对 需要换源、安装依赖的 alpine 系镜像有效
* 不使用环境变量时，脚本从 互联网 API 获取必要信息，通常可以正常运行。
* 如需部署大量容器（例如大于80个），建议添加通过环境变量添加私有镜像仓库。
* 两个环境变量同时存在时，MIRROR 生效，REGION 失效。

1. REDIRECT_PKG_HANDLER_WRAPPER_REGION    
填入非 CN/cn 值时，跳过 IP 归属地检测 和 换源; 填入 CN/cn 会跳过 IP 归属地检测，从中科大/清华/阿里/网易 中随机选取一个可以成功 update 的源
2. REDIRECT_PKG_HANDLER_WRAPPER_MIRROR   
填入 alpine 镜像源地址，如 西北农林大学镜像源  REDIRECT_PKG_HANDLER_WRAPPER_MIRROR=mirrors.nwafu.edu.cn



## 获取容器镜像的 ENTRYPOINT、CMD

### 方法一 通过 dockerfile 获取

* 找到 构建 image 的 Dockerfile
* Dockerfile 最后一行，一般是 ENTRYPOINT 或 CMD

### 方法二 通过 docker inspect 获取
```shell
# 列举 所有 docker 镜像
docker image ls

```

```shell
# 同时获取 ENTRYPOINT 和 CMD 
docker inspect --format='Entrypoint: {{.Config.Entrypoint}} Cmd: {{.Config.Cmd}}' <镜像名或ID>

```

### 以  `gdy666/lucky` 为例
```shell
docker inspect --format='Entrypoint: {{.Config.Entrypoint}} Cmd: {{.Config.Cmd}}' gdy666/lucky

```
下图是回显 

![](/images/20.png)

```docker
# docker run 中的 entrypoint
--entrypoint /land/redirect_pkg_handler.sh /app/lucky -c /goodluck/lucky.conf -runInDocker \
```
```yaml
# dompose 中的 entrypoint
entrypoint: ["/land/redirect_pkg_handler.sh", "/app/lucky", "-c", "/goodluck/lucky.conf", "-runInDocker"]
```

## Docker 部署 单个 容器

```docker
docker run -d \
  --name worker_program-1 \
  --sysctl net.ipv4.conf.lo.accept_local=1 \
  --cap-add=NET_ADMIN \
  --cap-add=BPF \
  --cap-add=PERFMON \
  --privileged \
  --entrypoint /land/redirect_pkg_handler.sh /original/entrypoint original cmd args \ # 覆盖 原始 Entrypoint
  -p 外部端口:内部端口 \
  # -e REDIRECT_PKG_HANDLER_WRAPPER_REGION=cn \ # 为 alipne 容器 更换随机中国源
  # -e REDIRECT_PKG_HANDLER_WRAPPER_MIRROR=mirrors.nwafu.edu.cn \ # 为 alipne 容器 更换指定源
  -v /home/worker_program-1/config:/config \ # 挂载配置文件目录
  -v /root/.landscape-router/redirect_pkg_handler-x86_64-musl:/land/redirect_pkg_handler-x86_64-musl \ # 挂载handler 
  -v /root/.landscape-router/redirect_pkg_handler.sh:/land/redirect_pkg_handler.sh \ # 挂载包装脚本
  -v /root/.landscape-router/unix_link/:/ld_unix_link/ \ # 必要映射
  some-image:latest # 修改成你需要的镜像
```
## compose 部署 多个 容器
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
    sysctls:
      - net.ipv4.conf.lo.accept_local=1
    cap_add:
      - NET_ADMIN
      - BPF
      - PERFMON
    privileged: true
    restart: unless-stopped
    # logging:
    #   options:
    #     max-size: "10m"
    # deploy:
    #   resources:
    #     limits:
    #       cpus: '4.0'
    #       memory: 512M
    # 为启用 ports 配置时，使用容器ip:端口 即可在主机内访问容器web界面，主机外访问时需使用反代 或 端口映射到主机端口
    # ports: # 可选配置  # 静态映射，主要用于映射web端口
    #   - "0.0.0.0:外部端口号:内部端口号"        # 映射到主机v4端口
    #   - "[::]:外部端口号:内部端口号"        # 映射到主机v6端口
    networks:
      worker_program-br:
        ipv4_address: 172.100.0.1
    # encironment:
    #   - REDIRECT_PKG_HANDLER_WRAPPER_REGION=cn \ # 为 alipne 容器换源，从 中科大/清华/阿里/网易 中随机选一个
    #   - REDIRECT_PKG_HANDLER_WRAPPER_MIRROR=mirrors.nwafu.edu.cn \ # 为 alipne 容器更换指定源，如西北林业大学源
    entrypoint: ["/land/redirect_pkg_handler.sh", "/original/entrypoint", "original", "cmd", "args"] # 覆盖 原始 Entrypoint
    volumes:
      - /home/worker_program-1/config:/config  # 挂载配置文件目录
      - /root/.landscape-router/redirect_pkg_handler-x86_64-musl:/land/redirect_pkg_handler-x86_64-musl  # 挂载handler 
      - /root/.landscape-router/redirect_pkg_handler.sh:/land/redirect_pkg_handler.sh # 挂载包装脚本
      - /root/.landscape-router/unix_link/:/ld_unix_link/ # 必要映射
    image: some-image:latest # 修改成你需要的镜像

  service-2:
    sysctls:
      - net.ipv4.conf.lo.accept_local=1
    cap_add:
      - NET_ADMIN
      - BPF
      - PERFMON
    privileged: true
    restart: unless-stopped
    # logging:
    #   options:
    #     max-size: "10m"
    # deploy:
    #   resources:
    #     limits:
    #       cpus: '4.0'
    #       memory: 512M
    networks:
      worker_program-br:
        ipv4_address: 172.100.0.2
    # encironment:
    #   - REDIRECT_PKG_HANDLER_WRAPPER_REGION=cn \ 为 alipne 容器换源，从 中科大/清华/阿里/网易 中随机选一个
    #   - REDIRECT_PKG_HANDLER_WRAPPER_MIRROR=mirrors.nwafu.edu.cn \ # 为 alipne 容器更换指定源，如西北林业大学源
    entrypoint: ["/land/redirect_pkg_handler.sh", "/original/entrypoint", "original", "cmd", "args"] # 覆盖 原始 Entrypoint
    volumes:
      - /home/worker_program-1/config:/config  # 挂载配置文件目录
      - /root/.landscape-router/redirect_pkg_handler-x86_64-musl:/land/redirect_pkg_handler-x86_64-musl  # 挂载handler 
      - /root/.landscape-router/redirect_pkg_handler.sh:/land/redirect_pkg_handler.sh # 挂载包装脚本
      - /root/.landscape-router/unix_link/:/ld_unix_link/ # 必要映射
    image: some-image:latest # 修改成你需要的镜像

```


# Docker容器作为分流出口 —— 挂载工作程序方式部署（不推荐）
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

**⚠ 不同程序传参方式不同，工作程序启动命令需自行修改**

```bash
#!/bin/bash

# 设置资源限制（也可在compose限制，不了解者可跳过这里）
# ulimit -n 1000000
# ulimit -u 500
# echo "设置资源限制成功"

# 启动审计程序守护进程
while true; do
    echo "启动 worker_program 工作程序..."
    # ↓↓↓ 按需修改
    /app/server/worker_program -d /app/server/config
    # ↑↑↑ 此处按需修改，不同程序传参方式不同（前一个为 worker_program 工作程序 二进制文件 后一个为 worker_program 工作程序 配置文件目录）
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
## 在 Dpanel 中创建 compose

### **参考 Dpanel 官方 [视频教程](https://www.bilibili.com/video/BV157RpYAE5e/?t=93)**

## Docker 部署 单个 接应容器

**worker_program 可替换为任意 工作程序**

```docker
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
    # logging:
    #   options:
    #     max-size: "10m"
    # deploy:
    #   resources:
    #     limits:
    #       cpus: '4.0'
    #       memory: 512M
    # 为启用 ports 配置时，使用容器ip:端口 即可在主机内访问容器web界面，主机外访问时需使用反代 或 端口映射到主机端口
    # ports: # 可选配置  # 静态映射，主要用于映射web端口
    #   - "0.0.0.0:外部端口号:内部端口号"        # 映射到主机v4端口
    #   - "[::]:外部端口号:内部端口号"        # 映射到主机v6端口
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
    # logging:
    #   options:
    #     max-size: "10m"
    # deploy:
    #   resources:
    #     limits:
    #       cpus: '4.0'
    #       memory: 512M
    networks:
      worker_program-br:
        ipv4_address: 172.100.0.2
    volumes:
      - /root/.landscape-router/unix_link/:/ld_unix_link/:ro # 必要映射
      - /home/worker_program/worker_program-2/:/app/server/
      # /home/worker_program/worker_program-2/ 目录下有 run.sh 启动脚本，config 配置文件，worker_program-2 二进制文件

```