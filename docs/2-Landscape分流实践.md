![](/images/13.png)

# Landscape 分流实践

# 目录
- [域名/IP 分流实践](#域名ip-分流实践)
- [基于 vlan/ssid（WiFi） 的分流实现（暂不能实现）](#基于-vlanssidwifi-的分流实现暂不能实现)

# [详细设置参考官方文档](https://landscape.whileaway.dev/feature/flow.html)
# 域名/IP 分流实践   

* 只会匹配中一条规则，匹配中即发送至出口，后续规则不再匹配 
* 以下是一种推荐分流布局，以域名分流为主，没有域名的连接由IP规则补充   
* 可使用 Geo 文件辅助分流   
* 域名初次访问时，域名分流 优先级 会影响 域名初次访问查询速度，越靠前匹配中，越快被查询
* 域名再次访问时，域名被解析后，基于 IP map，时间复杂度为 O(1)，再次访问的域名之匹配时间 = IP匹配时间 = O(1) 

| 优先级序号 | 用途 | 类别 |
|---|---|---|
| 1~999  | 局域网设备 域名重定向 | 域名分流|
| 1000 | 速查域名的 GeoSite 集合 | 域名分流 |
| 1001~2000 | （少量）域名/网站集合  | 域名分流|
| 2001~2999 | （大量）地区/ISP 集合   | 域名分流|
| 3000 | 整个 GeoSite 集合（GeoSite 兜底）  | 域名分流 |
| 10000 | 空规则 仅配置 dns 服务器（域名规则兜底） | dns 服务器配置（必须❗）|
|---|---|---|
| 11000~12000 | （少量）特定 IP 集合  | IP 分流 |
| 12000~13000 | （大量）地区/ISP 集合  | IP 分流 |        
| 20000 | 0.0.0.0/0 兜底 IP 规则 | IP 分流 |


# 基于 vlan/ssid（WiFi） 的分流实现（暂不能实现）
## 概述
* 在 SSH 中，创建多个 vlan 网卡，设为 manual
* flow 入口 设置为规则设置为 vlan
* 在 AC 中配置 ssid vlan
## landscape 中配置
```bash
# 检查网卡 
ip a

```


```bash
# 添加 vlan 网卡
nano /etc/network/interfaces

```

**上半部分保持原样，仅修改下半部分**
```shell
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback


# 上面部分保持原样即可，不需要修改
#---------------------------------------------------------------------
# 以下各部分 参照我这里的结构 修改



auto eth0
iface eth0 inet manual

# 创建 vlan id 为 10 的网卡，绑定到 物理接口 eth0
auto eth0.10
iface eth0.10 inet manual
    vlan-raw-device eth0       # 绑定物理接口

# 创建 vlan id 为 20 的网卡，绑定到 物理接口 eth0
auto eth0.20
iface eth0.20 inet manual
    vlan-raw-device eth0       # 绑定物理接口

```
**编辑结束后，先 `` ctrl + s `` 保存，再 `` ctrl + x `` 退出。**   

* 在landscape webui 中，配置为lan，开启dhcp
* `分流设置`中添加新的流，配置入口规则为 vlan 所设置 子网

## AC 中配置

为 ssid 添加 vlan 10、20   
[在 ikuai AC 中为 ssid 添加 vlan，参考官方文档 1、2 两节，dhcp已在landscape中配置无需在ikuai中配置 ](https://www.ikuai8.com/support/cjwt/ap/ap-ssid-vlan.html)
