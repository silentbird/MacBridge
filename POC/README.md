# MacBridge POC

最小可跑的概念验证：在菜单栏 app 里通过 `CGEventTap` 把 `A` 键改成 `B`。

验证一件事：**辅助功能权限申请 + 全局键盘事件拦截改键的技术链路能跑通**。一旦打通，后续 F2/F5/F8 规则只是在同一个 tap 回调里加规则引擎。

## 构建

```bash
./build.sh           # release + universal binary + 打 .app + 签 ad-hoc
./build.sh debug     # debug 构建
```

产物：`MacBridgePOC.app`

## 使用

```bash
open MacBridgePOC.app
```

1. 菜单栏出现键盘图标（`keyboard` SF Symbol）
2. 点击 → `Enable A → B test`
3. 首次勾选会弹系统对话框：前往 **系统设置 → 隐私与安全 → 辅助功能**，勾上 `MacBridgePOC`
4. 重新勾选菜单里的开关（系统权限变更后需要重新启动 tap）
5. 打开 TextEdit 或任意输入框，按 `A` → 出 `B`
6. 菜单里关掉开关后 `A` 恢复正常

## 代码结构

```
POC/
├── Package.swift                                  # SPM manifest (macOS 13+)
├── Info.plist                                     # LSUIElement=YES，隐藏 Dock
├── build.sh                                       # swift build + 打 .app + 签名
└── Sources/MacBridgePOC/
    ├── MacBridgePOCApp.swift                      # @main, MenuBarExtra
    ├── AccessibilityPermission.swift              # AX 权限检查
    └── EventTap.swift                             # CGEventTap 封装 + A→B
```

## 已知限制

- **未代码签名**：ad-hoc 签名，换路径重建 app 后 TCC 会要求重新授权
- **重启后权限丢失**：macOS 会记住 bundle id + 签名身份，ad-hoc 情况下 rebuild 经常需要重授
- **事件 tap 超时**：手动实现了 `tapDisabledByTimeout` 重启，POC 层面够用
- **没做键盘识别**：所有键盘都会被 tap，POC 阶段不区分

## 通过验收后

把以下迁移到正式项目：
- `EventTap.swift` → `Core/EventTap/` 模块，改键逻辑换成规则引擎
- `AccessibilityPermission.swift` → `Services/PermissionService/`
- Bundle 打包流程可保留到 CI 或迁到 Xcode 项目
