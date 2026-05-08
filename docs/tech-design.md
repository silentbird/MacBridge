# MacBridge 技术方案（初稿）

**状态**：草案，待验证

---

## 技术栈

- **语言**：Swift 5.9+
- **UI**：SwiftUI（菜单栏） + AppKit（必要时的底层能力）
- **最低系统**：macOS 13 Ventura（可直接用 SwiftUI `MenuBarExtra` 和 `SMAppService.loginItem`）
- **架构**：单进程菜单栏 app

---

## 关键能力与 API 选型

### 1. 键盘设备识别

**候选 API**：`IOHIDManager`（IOKit 框架）

- 通过 `IOHIDManagerCreate` + 设置 matching dictionary 监听所有 HID 键盘
- 从 `kIOHIDVendorIDKey` / `kIOHIDProductIDKey` / `kIOHIDProductKey` 获取键盘信息
- 典型判断逻辑：
  - VendorID 0x05AC = Apple → Mac 布局
  - 其他厂商（罗技、雷蛇、HHKB 等）→ 默认当 Win 布局
  - 保留用户覆盖的能力（一次选择永久记住）

**备用**：读取 `NXKeyboardType` / `kIOHIDSubsystemKey`，但可靠性不如 vendor 识别。

### 2. 键盘事件拦截与改键

**首选 API**：`CGEventTap`（Core Graphics）

- 在 `kCGSessionEventTap` 位置注册监听 `kCGEventKeyDown` / `kCGEventKeyUp` / `kCGEventFlagsChanged`
- 在回调中根据当前 profile 修改 `CGEventField` 的 keycode / modifier flags
- 优点：轻量，不需要驱动，官方授权路径清晰
- 缺点：需要辅助功能权限

**备选**：`Karabiner-VirtualHIDDevice` 这类虚拟驱动方案功能更强但部署复杂，不在 MVP 考虑。

### 3. 修饰键交换的实现方式

macOS 原生提供 `hidutil` 和 "系统设置 → 键盘 → 辅助按键" 接口来重映射修饰键。两种实现思路：

**方案 A：用 `hidutil` 设置内核级映射**
```bash
hidutil property --matching '{"VendorID":0x...}' --set '{"UserKeyMapping":[...]}'
```
- 优点：内核级映射，零延迟，重启前生效
- 缺点：重启失效需要 LaunchAgent 兜底；识别键盘要用 vendor/product 精确匹配
- 可行性：✅ 已被 Karabiner 使用，成熟方案

**方案 B：用 `CGEventTap` 在用户态翻译事件**
- 优点：灵活，可以做 Delete 键这种非标修饰键映射
- 缺点：事件链上多一跳，极端情况可能被其他 tap 干扰

**最终决定**：
- 修饰键（Cmd/Option）位置交换 → **方案 A（hidutil）**
- 非修饰键映射（Home/End 语义）→ **方案 B（CGEventTap）**
- Ctrl 快捷键语义映射（Ctrl+C/V/X/Z 等 → Cmd+同键）→ **方案 B（CGEventTap）**，需要按前台 app `bundleIdentifier` 做黑名单过滤

### 4. 菜单栏 UI

- SwiftUI `MenuBarExtra` 驻留状态栏（macOS 13+）
- 图标：SF Symbols + 自定义品牌标识

### 5. 权限处理

需要申请的权限：
1. **辅助功能 (Accessibility)** — CGEventTap 必需
2. **输入监控 (Input Monitoring)** — 监听键盘事件
3. **开机自启** — 通过 `SMAppService.loginItem`（macOS 13+）或 `ServiceManagement.SMLoginItemSetEnabled`（兼容旧版）

首次启动流程：
1. 欢迎页 → 说明为什么需要权限（配图示例）
2. 引导跳转到"系统设置 → 隐私 → 辅助功能"
3. 检测权限状态变化，授权后自动进入下一步
4. 识别当前键盘，提示用户确认 profile

---

## 模块划分

```
MacBridge/
├── App/                    # App 入口、生命周期
├── Core/
│   ├── KeyboardDetector/   # IOHIDManager 识别键盘
│   ├── EventTap/           # CGEventTap 监听和改键
│   ├── HIDUtil/            # hidutil 封装（修饰键映射）
│   └── Profile/            # Profile 定义、持久化
├── UI/
│   ├── MenuBar/            # 菜单栏主界面
│   ├── Settings/           # 设置窗口
│   └── Onboarding/         # 首次启动引导
├── Services/
│   ├── PermissionService/  # 权限检查/申请
│   └── LaunchAtLoginService/
└── Resources/              # 图标、本地化文案
```

---

## 数据持久化

- `UserDefaults` 足够存储配置（键盘 profile 记忆、开关状态）
- 无需数据库

数据结构示例：
```swift
struct KeyboardProfile: Codable {
    let vendorID: UInt32
    let productID: UInt32
    let displayName: String
    var layout: KeyboardLayout  // .windowsLayout / .appleLayout / .custom
    var rules: RuleSet
}

struct RuleSet: Codable {
    var swapModifiers: Bool           // F2
    var homeEndAsLine: Bool           // F5
    var ctrlSemanticMapping: Bool     // F8
}
```

---

## 签名与分发

- **开发阶段**：Apple Developer 账号，开发签名
- **分发**：
  - 公证 (Notarization) 后的 DMG
  - 不走 Mac App Store（沙盒会阻止 CGEventTap 全局监听）
  - 后续考虑 Homebrew Cask

---

## 风险与未知

| 风险 | 应对 |
|------|------|
| macOS 新版本 API 变动（如 12→15） | 分版本兼容 + CI 跑多版本测试 |
| 辅助功能权限授权率低（用户不信任） | 开源 + 文档详解 + 清晰授权引导 |
| 键盘识别误判（通用 USB 芯片） | 提供手动覆盖 + 记忆用户选择 |
| 与 Karabiner 同时使用冲突 | 启动时检测，提示用户二选一 |
| 蓝牙键盘重连后 profile 失效 | 监听 `IOHIDManager` 的设备增减事件 |

---

## 待验证技术点（POC 优先）

- [ ] `hidutil` 按 vendor/product 精确映射是否稳定
- [ ] `CGEventTap` 在键盘热插拔时是否需要重建
- [ ] macOS 12 上 `MenuBarExtra` 替代方案的开发体验
- [ ] 系统休眠/唤醒后所有监听是否需要重新初始化
