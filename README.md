# myconfig

一套 mihomo 配置，同时服务两处：

- **macOS**：FlClash 导入 `mihomo/macos.yaml`
- **OpenWrt 旁路由**：nikki 导入 `mihomo/router.yaml`（老固件可用 OpenClash）
- 附带一份 **Quantumult X** 配置模板（`QuantumultX.conf`）

订阅地址与 API secret 不进入仓库：`base.yaml` / overlay 里是占位符，构建时从本地文件注入。

## 目录

```
.
├── QuantumultX.conf              # QX 模板（订阅地址为占位符）
├── mihomo/
│   ├── base.yaml                 # 两端共用的节点源、策略组、规则、DNS
│   ├── overlays/
│   │   ├── router.yaml           # OpenWrt/nikki 设备段（TPROXY、API、日志）
│   │   └── macos.yaml            # macOS/FlClash 设备段（TUN 关闭、进程匹配）
│   ├── scripts/
│   │   ├── set-subscription.sh   # 写入订阅地址并重建全部配置
│   │   ├── build-configs.sh      # base + overlay -> router/macos.yaml
│   │   ├── install-china-list.sh # 路由器 dnsmasq 国内域名分流
│   │   └── mihomo-guard.sh       # 核心异常时停止 nikki，恢复直连
│   └── subscription.url.example  # 订阅地址示例
└── .gitignore
```

以下文件在本地生成，已被 git 忽略：

```
mihomo/subscription.url      # 真实订阅地址（权限 600）
mihomo/.secret               # 路由器 API secret（首次构建自动生成）
mihomo/router.yaml           # 由 base + overlays/router.yaml 生成
mihomo/macos.yaml            # 由 base + overlays/macos.yaml 生成
QuantumultX.local.conf       # 含真实订阅地址的 QX 配置
```

## 快速开始

```bash
git clone <repo> && cd myconfig

# 一条命令完成：写入订阅地址、生成 router.yaml / macos.yaml、生成 QX 本地副本
./mihomo/scripts/set-subscription.sh 'https://你的机场/api/v1/...'
```

脚本会：

1. 校验地址（必须 `http(s)://`，拒绝占位符）
2. 写入 `mihomo/subscription.url`
3. 首次运行自动生成 `mihomo/.secret`
4. 合并配置并执行 `mihomo -t`（本机有 `mihomo` 时；也可用 `MIHOMO_BIN=/path/to/mihomo`）
5. 生成 `QuantumultX.local.conf`

只重建某一份：

```bash
./mihomo/scripts/build-configs.sh router
./mihomo/scripts/build-configs.sh macos
```

## 路由器（OpenWrt + nikki）

前置条件：OpenWrt >= 24.10、firewall4、kernel >= 5.13；建议内存 >= 256MB。

```bash
# 安装 nikki（OpenWrt 24.10+）
wget -O - https://github.com/nikkinikki-org/OpenWrt-nikki/raw/refs/heads/main/feed.sh | ash
opkg install nikki luci-app-nikki luci-i18n-nikki-zh-cn
```

在 nikki 中：

1. 上传/选择 `mihomo/router.yaml`
2. 代理模式：**TCP = TPROXY**；**UDP = 关闭**（游戏 UDP 直连，见下）
3. 勾选 **绕过中国大陆 IP**
4. **关闭 DNS 劫持**（LAN DNS 交给 dnsmasq）
5. 访问控制：Lan 放行
6. 去掉硬件/软件 flow offloading：`/etc/config/firewall` 中 `flow_offloading`、`flow_offloading_hw` 设为 `0`

路由器侧端口：

| 用途 | 端口 |
|---|---|
| mixed（HTTP/SOCKS） | 7890 |
| TPROXY | 7893 |
| RESTful API | 9090（带 secret，仅 LAN） |
| DNS | 127.0.0.1:1053 |

### DNS：不影响国内解析

```bash
./mihomo/scripts/install-china-list.sh
```

脚本会：

- 把 felixonmars/dnsmasq-china-list 的 CN 域名列表装到 `/etc/dnsmasq.d`
- 设置 `dhcp.@dnsmasq[0].confdir=/etc/dnsmasq.d`
- 默认上游 `127.0.0.1#1053`（mihomo fake-IP），兜底 `223.5.5.5`
- CN 域名直接问国内 DNS，不经过 mihomo

效果：mihomo 挂掉时，CN 域名仍可解析、CN 网站仍可访问；配合“绕过中国大陆 IP”，CN 流量根本不进 TPROXY。

验证：

```bash
dig @<旁路由> www.baidu.com      # 国内 IP
dig @<旁路由> www.google.com     # 198.18.x.x
```

### 看门狗

```bash
nohup ./mihomo/scripts/mihomo-guard.sh >/dev/null 2>&1 &
```

连续 3 次探测 `/version` 失败后执行 `/etc/init.d/nikki stop`，移除 nft 规则并恢复直连。建议放进开机脚本或 crontab。

### 老固件

OpenWrt < 24.10 / firewall3 可以用 OpenClash 导入同一份 `mihomo/router.yaml`，TCP 选 TPROXY 或 Redirect。

## macOS（FlClash）

1. FlClash 导入本地文件 `mihomo/macos.yaml`
2. FlClash 启动时会用自己的设置覆盖 `log-level`、`find-process-mode`、`tun`、端口、API
3. AI 规则含 `PROCESS-NAME`（Claude / Codex / Antigravity）；要按进程命中，需在 FlClash 设置中打开进程匹配
4. 建议先用系统代理验证；TUN 需要给 core 授权（setuid root）

## Quantumult X

导入 `QuantumultX.local.conf`（由 `set-subscription.sh` 生成）。

仓库里的 `QuantumultX.conf` 是模板，订阅地址为 `__SUBSCRIPTION_URL__`，直接导入会报格式错误。

## 配置说明

### 节点与规则来源

| 来源 | 用途 | 更新 |
|---|---|---|
| 机场订阅（Clash UA） | 节点，`exclude-filter` 去掉流量/到期提示节点 | 24h |
| [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) | 日常服务（微信、B站、YouTube、Google、Netflix、Telegram、X、PayPal、微软、Apple、Steam、游戏、Crypto…） | 24h |
| [VPSDance/ai-proxy-rules](https://github.com/VPSDance/ai-proxy-rules) | AI 按厂商：OpenAI(含 Codex)、Anthropic、Gemini、xAI | 24h |
| [TG-Twilight/AWAvenue-Ads-Rule](https://github.com/TG-Twilight/AWAvenue-Ads-Rule) | 广告（`behavior: domain`） | 24h |
| [felixonmars/dnsmasq-china-list](https://github.com/felixonmars/dnsmasq-china-list) | 仅路由器 dnsmasq 的 CN 域名分流 | 手动运行脚本 |

注意：blackmatrix7 的 Clash 目录把“域名 + IP”拆开了；带 IP 段的列表（China、Apple、Netflix、GlobalMedia）必须使用 `*_Classical_No_Resolve.yaml`，否则只剩域名部分。仓库里已经按此处理。

### 策略组（28 个）

- 区域：`SG` / `JP` / `US` / `TW`（url-test，tolerance 150 避免播放中途切节点），`US手选`，`US固定`
- `AI-OpenAI` / `AI-Claude` / `AI-Gemini` / `AI-Grok`：默认 `US固定`，固定单节点保持出口 IP 稳定
- 服务：Google、YouTube、Netflix、Spotify、Telegram、X、PayPal、Microsoft、Apple、Steam、Crypto、Media、Game
- `CN`（默认 DIRECT）、`广告`、`漏网之鱼`

### 关键行为

- UDP 策略：`AND,((NETWORK,udp),(DST-PORT,443)),REJECT` 先拒绝 QUIC（UDP 443 在多数网络不可用，直连会让浏览器等数秒才回退 TCP），其余 UDP 由 `NETWORK,udp,DIRECT` 直连，优先保证游戏稳定性
- 要代理 UDP（Discord 语音、国际服游戏）：删掉上面两行，并在 nikki 打开 UDP 代理
- `Game` 组默认 `DIRECT`：游戏流量不经机场；需要加速时手动切 SG/JP
- DNS：fake-IP + 银行/局域网域名排除（`fake-ip-filter`），国内 CDN 走就近 DNS（`nameserver-policy`）
- 路由器 `log-level: silent`：核心不写连接日志，节省磁盘

### 更新配置

```bash
# 修改 base.yaml 或 overlays/ 后
./mihomo/scripts/build-configs.sh all
```

构建失败不会覆盖现有文件；`mihomo -t` 不通过时保留旧配置。

## 安全

- `mihomo/subscription.url`、`mihomo/.secret`、生成的 YAML、`QuantumultX.local.conf` 都不提交
- 推送前自查：

```bash
# 用自己订阅地址里的一段独特字符替换 <token 片段>
git grep -n '<token 片段>' HEAD || echo clean
# 确认没有把生成文件加进版本库
git ls-files | grep -E 'router\.yaml|macos\.yaml|subscription\.url|local\.conf' || echo clean
```

- 不要用 GitHub 网页拖拽上传，网页上传会绕过 `.gitignore`
- 仓库保持私有更稳妥；订阅地址等同于账号凭据
- `router.yaml` 的 API secret 只用于 LAN，防火墙不要放行 WAN

## 排错

| 现象 | 原因 / 处理 |
|---|---|
| `缺少 mihomo/subscription.url` | 先运行 `set-subscription.sh` |
| `仍是占位符` | 地址填的是 example 或 `REPLACE_ME` |
| `未找到 mihomo，跳过 -t` | 可选；用 `MIHOMO_BIN=/path/to/mihomo` 指定 |
| 路由器上 CN 域名解析异常 | 检查 `install-china-list.sh` 是否执行、`confdir` 是否为 `/etc/dnsmasq.d` |
| 代理不生效 | 关闭 flow offloading；确认 nikki TCP 模式为 TPROXY |
| 游戏丢包 | 确认 nikki UDP 代理已关闭；`NETWORK,udp,DIRECT` 仍在规则里 |
| YouTube / Spotify 卡顿 | 先确认 QUIC 已被 REJECT；再把对应策略组切到 SG（JP 节点实测最差）；带宽不足时手动选「高速专线-hy2」或美国下载节点 |
| AI 服务 403 | 链路已通，节点 IP 被风控；在 `US固定` 里换节点 |
| 想代理 UDP | 删除 `NETWORK,udp,DIRECT`，并在 nikki 打开 UDP 代理 |

## 依赖

- 路由器：mihomo（nikki/OpenClash 自带）、dnsmasq-full、curl 或 wget
- macOS：FlClash（或任意 mihomo 客户端）
- 可选：本机 `mihomo` 可执行文件，用于构建时 `-t` 校验
- Quantumult X 为付费 App，与订阅服务无关
