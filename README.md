<div align="center">

<img src="assets/images/icon.png" alt="FlClash for iOS" width="100" style="border-radius: 22px; box-shadow: 0 4px 16px rgba(0,0,0,0.15);">

# FlClash for iOS

### Next-Generation High-Performance Proxy Client Tailored for iOS

Powered by **Mihomo (Clash.Meta)** core and **Flutter** modern architecture. Clean, open-source, ad-free, ultra-fast, and memory-optimized.

**English** · [简体中文](README_zh_CN.md)

<br/>

[![Platform](https://img.shields.io/badge/Platform-iOS%2015.0%2B-007AFF?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/Sunny-qwe/FlClash-iOS)
[![Arch](https://img.shields.io/badge/Arch-arm64-black?style=for-the-badge)](https://github.com/Sunny-qwe/FlClash-iOS)
[![LiveContainer](https://img.shields.io/badge/LiveContainer-Compatible-34C759?style=for-the-badge&logo=apple)](https://github.com/Sunny-qwe/FlClash-iOS)
[![License](https://img.shields.io/badge/License-GPL--3.0-orange?style=for-the-badge)](LICENSE)

<br/>

[✨ Features](#-key-features) · [📥 Installation](#-installation-guide) · [🌐 Protocol Matrix](#-protocol-support-matrix) · [🛠️ CI/CD Build](#️-cloud-automated-build-cicd)

</div>

---

## 🌟 Key Features

- 🍏 **Native iOS NetworkExtension Optimization**  
  Built on Apple's native NetworkExtension framework. Rigorously engineered to prevent iOS Jetsam memory limit kills (OOM protection) and maintain rock-solid connection stability.

- 🛡️ **Loopback Protection & Local Bypass**  
  Native exclusion for local loopback (`127.0.0.1`) and reserved IP ranges. Perfect compatibility for **LiveContainer** and **SideStore** sandboxed environments.

- 🚀 **Intelligent Anti-403 Subscription Import**  
  Built-in multi-tier User-Agent fallback engine (Clash Verge / Safari / Shadowrocket headers). Seamlessly bypasses strict airport WAF (V2Board, XBoard, SSPanel) and Cloudflare bot filters.

- 🌐 **One-Click Link Unwrapping**  
  Supports quick-import URLs (`clash://install-config`, `stash://`), automatically parsing real subscription endpoints and extracting profile titles.

- 🎨 **Apple Design Aesthetics**  
  Preview ribbon and test watermark completely removed (No PRE Banner). Features fluid Material 3/Apple Human Interface dynamics, adaptive dark mode, and smooth continuous corners.

- ⚡ **Full Mihomo (Clash.Meta) Power**  
  Comprehensive rule-based routing, proxy group latency checks, advanced DNS traffic management, TUN mode, and external rule-set providers.

---

## 📥 Installation Guide

This repository builds unsigned iOS app bundles (`.ipa`) automatically via GitHub Actions:

### Method 1: LiveContainer (Recommended ⭐⭐⭐⭐⭐)
> **No certificate required! No 7-day expiration hassle!**
1. Install [LiveContainer](https://github.com/khanld/livecontainer) on your iOS device.
2. Download the `.ipa` artifact from [GitHub Actions](#️-cloud-automated-build-cicd) or Releases to your device's Files app.
3. Open LiveContainer, tap the **「+」** icon, select the `.ipa`, and launch instantly!

### Method 2: Certificate Signing (ESign, GBox, Bullfrog, Sideloadly)
- Send the `.ipa` to your device and import into your preferred sideloading tool (ESign, GBox, AltStore) with your Apple ID or enterprise certificate.

---

## 🌐 Protocol Support Matrix

| Category | Protocols | Highlights |
| :--- | :--- | :--- |
| **Next-Gen Speed** | **Hysteria 2 / Hy2**, Hysteria 1, **TUIC v4 / v5** | QUIC/UDP-based, port hopping, BBR congestion control |
| **Core Anti-Censorship** | **VLESS**, **VMess** | Full **Reality** support, Vision, gRPC, WebSocket, H2, HTTPUpgrade |
| **Classic Proxies** | **Trojan**, **Shadowsocks (SS)**, **ShadowsocksR (SSR)** | SIP002, AEAD 2022, Shadow-TLS, v2ray-plugin |
| **Tunnels & VPNs** | **WireGuard / AmneziaWG**, **Snell (v1~v4)**, **SSH** | Pre-shared keys (PSK), reserved bytes, AWG parameters |
| **Universal Protocols** | **SOCKS5**, **HTTP / HTTPS**, **AnyTLS**, **Mieru** | Pure proxy protocols and anti-probe tunnels |

---

## 🛠️ Cloud Automated Build (CI/CD)

```mermaid
flowchart LR
    A["Modify Code Locally"] -->|"git push"| B["GitHub Repository"]
    B --> C["GitHub Actions<br/>(macOS Runner)"]
    C --> D["Automated Compilation"]
    D --> E["Download FlClash.ipa<br/>(Ready to Install)"]
```

1. Navigate to your repository's **「Actions」** tab.
2. Select the **「Build iOS IPA」** workflow on the left.
3. Click the blue **「Run workflow」** button.
4. Download the newly compiled `.ipa` from the **Artifacts** section once complete!

---

## 📄 License

Open-sourced under the [GPL-3.0 License](LICENSE).
