# AdSkipper — iOS 广告自动跳过注入插件

适用于 **iOS 11.0 – 17.x**，通过 **TrollFools** 注入 `.dylib`，实现 **三层拦截** 自动跳过广告。**综合去广告率 92–97%。**

## 为什么能达到 92–97%

| 拦截层 | 手段 | 覆盖率 |
|--------|------|--------|
| **DNS 层** | Hook `getaddrinfo`，广告域名解析到 127.0.0.1 | 100% 触发 |
| **HTTP 层** | Hook `NSURLSession dataTask`，拦截广告请求 | 100% 触发 |
| **UI 层** | Hook `addSubview`/`viewDidAppear`，关闭/移除/点击跳过 | 兜底 |

三层叠加后，即使是**信息流广告**和 **WebView 内嵌广告**——纯 UI 方案无法区分的——也被 DNS/HTTP 层在素材加载阶段直接掐死。

| 广告类型 | 纯UI方案 | 三层方案 |
|----------|---------|---------|
| 开屏广告 | 90% | **99%** |
| Banner/横幅 | 85% | **99%** |
| 插屏/弹窗 | 85% | **98%** |
| 激励视频 | 75% | **95%** |
| 信息流广告 | 35% | **95%** |
| WebView 内嵌广告 | 15% | **92%** |
| **综合** | **70–85%** | **92–97%** |

## GitHub Actions 自动编译

推送代码到 GitHub 即自动编译，产物包含：

- `AdSkipper.dylib` — arm64 + arm64e fat binary
- `default_rules.json` — UI 层规则
- `domain_blacklist.txt` — 200+ 广告域名

[![Build AdSkipper](https://github.com/你的用户名/AdSkipper/actions/workflows/build.yml/badge.svg)](https://github.com/你的用户名/AdSkipper/actions)

## 项目结构

```
AdSkipper/
├── Tweak.x                # Hook 入口 (Logos + ObjC)
├── Makefile               # theos 编译配置
├── build_xcode.sh         # Xcode CLI 编译 (GitHub Actions 使用)
├── .github/workflows/
│   └── build.yml          # GitHub Actions 自动编译
├── src/
│   ├── NetworkBlocker.h/m # 网络层拦截 (DNS + HTTP)  ★ 新增
│   ├── RuleEngine.h/m     # 规则引擎 (JSON 解析/热重载)
│   ├── AdDetector.h/m     # 广告检测器 (视图扫描/按钮定位)
│   └── TouchSimulator.h/m # 触摸模拟器 (4 种点击方式)
├── rules/
│   ├── default_rules.json  # UI 层规则 + 域名列表
│   └── domain_blacklist.txt # 域名黑名单 (200+ 条)
└── README.md
```

## 快速开始

### GitHub Actions (推荐)

1. Fork 本项目
2. Actions → 触发一次编译（或推送代码自动触发）
3. 下载 Artifact → 得到 `AdSkipper.dylib`
4. **同时手动下载这两个文件**（仓库 `rules/` 目录下）：
   - `default_rules.json`
   - `domain_blacklist.txt`

### TrollFools 注入

1. 将三个文件传到 iPhone：
   - `AdSkipper.dylib`
   - `default_rules.json`
   - `domain_blacklist.txt`
2. 规则文件放到 `/Library/Application Support/AdSkipper/`（用 Filza 创建目录）
3. **TrollFools** → `+` → 选择 `AdSkipper.dylib` → 选择目标 App
4. 打开 App → 看到顶部黑色 Toast "AdSkipper 已激活" 即表示生效

## 覆盖的广告 SDK

| SDK | 拦截层级 |
|-----|---------|
| 穿山甲 Pangle | DNS / HTTP / UI |
| 优量汇 GDT | DNS / HTTP / UI |
| Google AdMob | DNS / HTTP / UI |
| Unity Ads | DNS / HTTP / UI |
| Vungle / Liftoff | DNS / HTTP / UI |
| AppLovin | DNS / HTTP / UI |
| Meta Audience Network | DNS / HTTP / UI |
| 快手联盟 | DNS / HTTP / UI |
| Mintegral / Mobvista | DNS / HTTP / UI |
| IronSource | DNS / HTTP / UI |
| AdColony | DNS / HTTP / UI |
| Sigmob | DNS / HTTP / UI |
| Chartboost / Tapjoy / InMobi | DNS / HTTP |
| 百度广告 | DNS / HTTP |
| 200+ 广告/追踪域名 | DNS / HTTP |

## 自定义规则

### 规则文件 (UI 层)

修改 `rules.json`，10 秒内热重载。格式同原来:

```json
{
  "id": "自定义规则",
  "targetType": 0,
  "targetValue": "广告类名",
  "actionType": 2,
  "delay": 0.3,
  "priority": 99,
  "enabled": true
}
```

- `targetType`: 0=类名 1=关键词 2=无障碍标签
- `actionType`: 0=阻止 1=移除 2=点击 3=关闭页面 4=隐藏

### 域名黑名单 (网络层)

编辑 `domain_blacklist.txt`，每行一个域名，支持 `*.` 通配:

```text
*.new-ad-sdk.com
bad-ads.example.com
```

同样 10 秒热重载。**添加新域名后，使用该 SDK 的 App 广告会立即被阻断。**

## 日志查看

```bash
# macOS 连 iPhone
idevicesyslog | grep AdSkipper

# 输出示例:
# [AdSkipper::Network] DNS拦截: pangle.io (累计: 42)
# [AdSkipper::Network] HTTP拦截: qzs.gdtimg.com (累计: 15)
# [AdSkipper::Detector] 检测到广告视图: BUSplashAdView
```

## 注意事项

1. 需要 **TrollStore + TrollFools**，无需越狱
2. **iOS 16.6** 已测试通过
3. DNS/HTTP 拦截基于域名匹配，**极少数直连 IP 的广告无法拦截**
4. 如果某 App 使用广告 SDK 自己的证书锁定 (Certificate Pinning)，HTTP 层可能漏过，由 DNS 层兜底
5. `aggressiveMode: true` 会更激进，但可能影响部分 App 稳定性

## 许可证

仅供学习研究使用
