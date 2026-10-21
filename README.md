# ⚠️ 上游停更声明：ZCode 在登录状态下会静默 RSA 打包整个工作区及完整 Git 历史上传至云端对象存储

原项目（HumanAILoop/zemote）因此隐私问题宣布永久停更：

- https://linux.do/t/topic/2917956
- https://linux.do/t/topic/2917923

这是 ZCode 犯的错，不是本项目的错——但你在使用任何需要登录 ZCode 账号的客户端（包括官方客户端和本项目）前，都应当知晓并自行评估这一风险。如无法接受，推荐改用 [paseo](https://github.com/getpaseo/paseo) 和 [oh-my-pi](https://www.pi-gui.com/)。

---

## 本 Fork 状态

上游停更后，ZCode 又将远程控制协议从 V1 升级为 **Relay V2**（账号 OAuth 登录制），旧版 zemote 彻底无法连接。本 fork 完成了 V2 适配，项目重新可用：

- **登录制连接**：App 内直接登录 Z.AI / BigModel 账号（与桌面端同账号），无需再复制带凭据的链接
- **设备自动发现**：登录后自动列出账号下的桌面设备（含在线状态），点选即连；扫码仍是可选入口
- **一次性 token 鉴权**：每次连接现领 60 秒时效 token，本地不再保存任何设备凭据
- 其余功能（任务管理、Conversation V4 对话、文件 diff、模型供应商、用量、通知等）与原版一致

> 协议细节与迁移记录见 [CHANGELOG.md](CHANGELOG.md)；对真实桌面端的完整链路（配对 / bootstrap / 会话订阅 / channel RPC）已实测通过。

---

<div align="center">

# Zemote

**手机/平板上的 ZCode 远程控制客户端** — 独立复刻官方 Web 远程控制协议（protocol reimplementation）

[![Flutter](https://img.shields.io/badge/Flutter-3.5%2B-blue.svg?logo=flutter)](https://flutter.dev)
[![CI](https://github.com/winnerhash/zemote/actions/workflows/build-apk.yml/badge.svg)](https://github.com/winnerhash/zemote/actions/workflows/build-apk.yml)
[![Release](https://img.shields.io/github/v/release/winnerhash/zemote)](https://github.com/winnerhash/zemote/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

在手机/平板上**同时管理多台桌面设备**：登录账号 → 设备列表选择桌面 → 浏览任务、收发对话、查看文件变更、管理模型供应商与用量配额。

> ⚠️ 本项目为**协议复刻**，与官方客户端无任何代码关联。请遵守 ZCode 服务条款与当地法律法规，仅用于连接你自己的设备。

</div>

---

## 功能特性

### 账号与设备
- Z.AI / BigModel 账号登录（App 内 OAuth），设备按账号自动发现，无需手动添加
- 多台设备同时在线，一键切换无需重连；支持扫码快速定位某台桌面
- JWT 凭据在 Android 上经 Keystore 加密存储，失效自动回登录页

### 任务管理
- 任务 / 置顶 / 已归档三栏，搜索过滤、下拉刷新、滑动置顶/归档、重命名、删除
- 实时订阅 `sessions-index`，与 workspace-list 推送合并去重
- 未读标记、最近预览文本、运行状态点

### 对话（Conversation V4）
- 流式回复、推理过程展示、斜杠命令（`/`）、Skills（`$`）、模型/模式/思考级别切换
- **辅助对话**：为当前会话开启独立侧对话，互不干扰并行提问
- 排队消息管理、目标（goal）指令、暂停/恢复
- 附件上传/预览、文件变更 diff、文件回滚、编辑用户消息、点赞/点踩

### 协议层
Relay V2 账号鉴权（OAuth → 一次性 token → ws2）、rpc-frame 分片传输（CRC32 校验 + ack）、IPC 值编解码、V4 快照/增量协议。

### 调试工具
- 协议日志页（relay / IPC / V4 帧）
- RPC（relay payload）调试器、Channel RPC 调试器

### 其他
- 模型供应商管理（添加/启停/删除）、用量/配额/订阅查看
- 浅色/深色/跟随系统主题、字体缩放、中英双语
- **更新检测**：启动自动检查 GitHub 最新发布，Android 端一键下载 APK 直装
- **后台任务通知（Android）**：任务运行中通知栏常驻并实时更新，点击直达对话

## 平台

| 平台 | 状态 |
|------|------|
| Android | ✅ 主要目标平台 |
| Web | ✅ 可用（调试 / 快速预览） |
| Windows | ⚙️ 桌面端可用（未重点优化） |
| iOS / macOS / Linux | 未验证（理论上可构建） |

## 快速开始

### 前置条件

- Flutter SDK（本项目 `sdk: ^3.5.0`）
- 桌面端已安装并登录 **ZCode**（zcode.z.ai，需 ≥ 3.16），且开启远程控制

### 运行

```bash
# Android
flutter run

# Web（快速预览）
flutter run -d chrome

# Windows
flutter run -d windows
```

应用内：**登录与桌面端相同的账号** → 设备列表出现你的桌面 → 点选连接 → 进入任务列表。

### 构建 APK

```bash
flutter build apk --split-per-abi
# 产物：arm64-v8a / armeabi-v7a / x86_64 三种 APK
```

## 更新与签名

- 应用内置**更新检测**：按设备 CPU 自动选择 APK，支持断点续传、MD5 校验直装。
- 发布流程：`main` 打好代码 → `git tag vX.Y.Z` → 推送。GitHub Actions 自动执行 `flutter analyze` + `flutter test`，构建并发布三种 CPU 架构 APK 到 Release。
- 签名说明：配置 `ANDROID_KEYSTORE_*` 相关 Secrets 后 CI 出统一签名包（未配置则 debug 签名）。详见 `.github/workflows/build-apk.yml`。

## 架构

```
┌────────────────────────────────────────────────────────────┐
│ UI (lib/ui)     登录 / 设备列表 / 任务 / 对话 / 设置 / 调试器 │
├────────────────────────────────────────────────────────────┤
│ State (lib/state)  SessionStore · AccountStore · AppSession │
├────────────────────────────────────────────────────────────┤
│ Auth (lib/auth)  OAuth 授权 URL / 回调解析 / code → JWT     │
├────────────────────────────────────────────────────────────┤
│ Facade (lib/protocol/zemote_client.dart)                    │
│   relay → 配对 → bootstrap → workspace-bridge → channel RPC │
├────────────────────────────────────────────────────────────┤
│ Protocol (纯 Dart，可单测)                                  │
│   RelayHttpClient · RelayClient(V2) · RpcFrameTransport     │
│   ChannelClient · IpcCodec · Conversation(V4)               │
└────────────────────────────────────────────────────────────┘
```

| 层 | 职责 |
|---|---|
| `connection_params.dart` | V2 连接 URL 解析 + relay WS 地址（拒绝旧版凭据链接） |
| `relay_http.dart` | 设备列表 / 一次性 token / 删除设备（Bearer JWT） |
| `auth/oauth.dart` | Z.AI / BigModel 授权 URL、回调解析、code 换 JWT |
| `relay_client.dart` | relay V2 WebSocket 连接 + 心跳 + 重连 + 错误码处理 |
| `rpc_transport.dart` | rpc-frame 分片/重组/CRC32 校验/ack |
| `ipc_codec.dart` | 值编解码 + 13 字节 IPC 帧解析 |
| `channel_client.dart` | IPC channel RPC 调用/事件订阅 |
| `conversation.dart` | Conversation V4 / sessions-index 快照+增量 |
| `zemote_client.dart` | 高层门面：bootstrap / bridge / 断线恢复 |

## 测试

```bash
# 单元测试
flutter test

# 真实环境探针：需要账号 JWT 与在线桌面
ZEMOTE_PROBE_JWT="<jwt>" ZEMOTE_PROBE_URL="https://zcode.z.ai/remote/v4?sid=...&mid=..." \
  flutter test test/v2_smoke_test.dart
```

## 安全提示

- **先读顶部声明**：ZCode 登录状态下的工作区上传行为是上游停更的原因，风险自评估。
- 登录凭据为账号 JWT：Android 上 Keystore 加密存储，非 Android 平台为明文 SharedPreferences。
- 如凭据泄露，改账号密码即可作废旧 token；设备 sid 不再是凭据，泄露无实际风险。
- 本地不保存任何设备凭据（V2 连接参数只有路由提示）。

## 技术栈

- [Flutter](https://flutter.dev) / Dart
- [web_socket_channel](https://pub.dev/packages/web_socket_channel) — relay 长连接
- [webview_flutter](https://pub.dev/packages/webview_flutter) — 账号 OAuth 登录
- [crypto](https://pub.dev/packages/crypto) — 附件校验 / 缓存键 / 更新 MD5
- [mobile_scanner](https://pub.dev/packages/mobile_scanner) / [zxing2](https://pub.dev/packages/zxing2) — 扫码与图片识别
- [shared_preferences](https://pub.dev/packages/shared_preferences) — 持久化
- [http](https://pub.dev/packages/http) — relay HTTP API / 更新检测
- [flutter_markdown](https://pub.dev/packages/flutter_markdown) — Markdown 渲染

## 贡献

欢迎提交 [Issue](https://github.com/winnerhash/zemote/issues) 与 Pull Request。提交 PR 前请确保：

1. `flutter analyze` 无告警
2. `flutter test` 全部通过

## Changelog

版本变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## License

[MIT](LICENSE)

## 免责声明

本项目为个人学习与互操作目的，对 ZCode 远程控制协议的独立复刻，非官方出品。使用者须自行承担风险与合规责任。
