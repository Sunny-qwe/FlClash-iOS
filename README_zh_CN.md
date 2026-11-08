<div align="center">

<img src="assets/images/icon.png" alt="FlClash for iOS" width="100" style="border-radius: 22px; box-shadow: 0 4px 16px rgba(0,0,0,0.15);">

# FlClash for iOS

### 专为 iOS 深度定制的新一代高性能代理客户端

基于 **Mihomo (Clash.Meta)** 核心与 **Flutter** 现代化架构，纯净开源、无广告、极速低耗。

[English](README.md) · **简体中文**

<br/>

[![Platform](https://img.shields.io/badge/Platform-iOS%2015.0%2B-007AFF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Sunny-qwe/FlClash-iOS)
[![Arch](https://img.shields.io/badge/Arch-arm64-black?style=for-the-badge)](https://github.com/Sunny-qwe/FlClash-iOS)
[![LiveContainer](https://img.shields.io/badge/LiveContainer-Compatible-34C759?style=for-the-badge&logo=apple)](https://github.com/Sunny-qwe/FlClash-iOS)
[![License](https://img.shields.io/badge/License-GPL--3.0-orange?style=for-the-badge)](LICENSE)

<br/>

[✨ 核心特性](#-核心特性) · [📥 安装指南](#-安装指南) · [🌐 协议支持](#-全协议支持矩阵) · [🛠️ 编译与打包](#️-云端自动构建-cicd)

</div>

---

## 🌟 核心特性

- 🍏 **原生 iOS NetworkExtension 深度优化**  
  基于 Apple 官方网络扩展框架打造，专门针对 iOS 系统严格的内存限制（Jetsam 机制）进行内存压制与泄漏控制，告别长时间运行爆内存闪退与断流。

- 🛡️ **回环防护与本地直连 (Loopback Support)**  
  原生排除本地回环（`127.0.0.1`）与保留地址，完美支持 **LiveContainer**、**SideStore** 免证书沙盒调试，杜绝自连接死锁。

- 🚀 **智能防封订阅导入 (Anti-403 Forbidden)**  
  内置智能多级 User-Agent 伪装机制（通用 Clash Verge / Safari / Shadowrocket 自动回退），完美通过各大机场面板（V2Board、XBoard、SSPanel）及 Cloudflare WAF 严格白名单校验，彻底解决订阅添加 403 报错。

- 🌐 **一键导入快捷解析**  
  支持粘贴机场快捷协议链接（如 `clash://install-config`、`stash://`），全自动解包真实订阅地址并自动提取机场名称。

- 🎨 **Apple 原生风格现代美学**  
  彻底剔除测试预览红带子（No PRE Banner），画面纯净无瑕。遵循 iOS Human Interface Guidelines，平滑连续曲率圆角、灵动微动效与自适应暗色模式。

- ⚡ **强大的 Mihomo (Clash.Meta) 全功能**  
  支持规则分流、策略组测速、DNS 流量控制、TUN 高性能模式、外部规则集（Rule-Set）、模块拓展与重写脚本。

---

## 📥 安装指南

本仓库通过 GitHub Actions 全自动编译生成未签名的标准 iOS 应用安装包（`.ipa`），支持多种灵活的安装方式：

### 方式 1：LiveContainer 免签名直接使用（推荐 ⭐⭐⭐⭐⭐）
> **优势**：完全不需要电脑自签，没有 7 天证书过期掉签烦恼，随时随地可用！
1. 在 iPhone / iPad 上安装好 [LiveContainer](https://github.com/khanld/livecontainer)。
2. 从本仓库 [Actions 产物](#️-云端自动构建-cicd) 或 Releases 中下载 `.ipa` 文件至手机「文件」App。
3. 打开 LiveContainer，点击右上角 **「+」** 号，选取该 `.ipa` 文件，即可直接免签名启动！

### 方式 2：个人免费证书 / 开发者证书签名安装
1. **手机端自签工具**（轻松签 ESign、全能签、GBox、牛蛙助手等）：
   - 将 `.ipa` 发送至手机并使用自签工具打开，导入您自己的苹果证书，点击「立即签名并安装」。
2. **电脑端签名工具**（爱思助手、AltStore、Sideloadly）：
   - 手机连接电脑，打开爱思助手 ->「工具箱」->「IPA 签名」，添加 `.ipa` 文件并输入 Apple ID 自签安装。

### 方式 3：SideStore / AltStore 安装
直接将下载的 `.ipa` 文件导入 SideStore / AltStore 的应用列表中进行签名安装。

---

## 🌐 全协议支持矩阵

底层集成了全功能的 Mihomo 现代内核，几乎涵盖目前所有主流与防封代理协议：

| 协议分类 | 支持协议 | 传输伪装与特性 |
| :--- | :--- | :--- |
| **新一代极速协议** | **Hysteria 2 / Hy2**、Hysteria 1、**TUIC v4 / v5** | 基于 UDP / QUIC 打造，端口跳跃、BBR 拥塞控制、抗弱网抖动 |
| **主流核心防封** | **VLESS**、**VMess** | 完整支持 **Reality**（最新防探测伪装）、Vision、gRPC、WebSocket、H2、HTTPUpgrade |
| **经典加密代理** | **Trojan**、**Shadowsocks (SS)**、**ShadowsocksR (SSR)** | 支持 SIP002、AEAD 2022、Shadow-TLS、v2ray-plugin、simple-obfs |
| **点对点与隧道** | **WireGuard / AmneziaWG**、**Snell (v1~v4)**、**SSH** | 支持预共享密钥 (PSK)、Reserved 混淆字节、AWG 自定义握手包 |
| **通用与新兴协议** | **SOCKS5**、**HTTP / HTTPS**、**AnyTLS**、**Mieru** | 纯净代理协议与新兴抗审查通道 |
| **订阅格式兼容** | **Clash YAML**、**Base64 批量节点**、**一键唤起链接** | 自动识别并转换 V2RayN Base64 订阅文本为完整 Clash 配置 |

---

## 🛠️ 云端自动构建 (CI/CD)

本项目原生接入 **GitHub Actions**，完全免除在本地配置苹果编译环境的麻烦：

```mermaid
flowchart LR
    A["本地修改代码"] -->|"git push"| B["GitHub 仓库"]
    B --> C["GitHub Actions<br/>(macOS 苹果云主机)"]
    C --> D["全自动依赖配置与编译"]
    D --> E["生成最新 FlClash.ipa<br/>(直接下载安装)"]
```

### 如何触发打包与下载最新 IPA：
1. 打开您的 GitHub 仓库页面，点击顶部的 **「Actions」** 选项卡。
2. 在左侧选择 **「Build iOS IPA」** 工作流。
3. 点击右侧蓝色的 **「Run workflow」** 下拉框并确认运行。
4. 苹果云端主机将在 8~10 分钟内完成编译；完成后在页面底部的 **Artifacts** 处点击 **`FlClash-iOS-arm64-unsigned`** 即可下载最新安装包！

---

## 💻 本地源码提交指南

每次在本地修改完代码后，只需在终端中运行以下命令即可极速推送到 GitHub 并自动触发编译：

```powershell
# 1. 暂存所有修改
git add .

# 2. 提交更新信息
git commit -m "feat(ios): 优化更新"

# 3. 推送触发云端构建
git push myorigin main
```

---

## 📄 开源许可

本项目基于 [GPL-3.0 License](LICENSE) 协议开源，感谢开源社区各位先驱开发者的杰出贡献。
