# Win → Mac 切换痛点清单

> 按"日常碰到频次"排序，⭐ 越多越痛。此文档用于指导功能优先级。

---

## ⭐⭐⭐ 高频痛点（MVP 必解决）

### 1. 修饰键位置错乱
- **现象**：Mac 拇指按 `Cmd`（空格旁），Win 键盘接上后拇指按到的是 `Alt`
- **影响**：`Cmd+C/V/Z/S` 几乎每一次都按错
- **现状 macOS 支持**：设置 → 键盘 → 辅助按键 可以换，但只是整体互换，且每个键盘都要单独配
- **MacBridge 做法**：自动识别后开箱即用，支持按键盘记忆（对应 F2）

### 2. Ctrl 快捷键语义不一致
- **现象**：
  - Win 肌肉记忆：`Ctrl+C/V/X/Z/A/S/F/O/N/P/T/W` 等
  - Mac：统一用 `Cmd`，同键位但换修饰键
- **影响**：迁移期最高频的按错，几乎覆盖所有日常编辑/窗口操作
- **与痛点 1 的区别**：痛点 1 关心"拇指按哪个键"，这里关心"用哪个修饰键触发复制粘贴"。F2 换位置让用户学新手位，F8 保留旧手位改键的含义
- **MacBridge 做法**：白名单式映射 12 组常用 Ctrl 组合到 Cmd，终端类 app 黑名单排除以保留 `Ctrl+C` 中断等原生功能（对应 F8，默认关闭，用户主动启用）

---

## ⭐⭐ 中频痛点（MVP 或 v0.2 解决）

### 3. Home/End 跳转语义差异
- **现象**：
  - Win: `Home` → 行首，`End` → 行尾
  - Mac: `Home` → 文档顶部，`End` → 文档底部；行首/行尾要 `Cmd+←/→`
- **影响**：写代码/写文档时痛感强烈
- **备注**：现代 app（Chrome、VSCode、主流 IDE）多数已实现为行首/行尾；只有原生 Cocoa 文本控件（TextEdit、Pages 等）坚持文档顶/底语义
- **MacBridge 做法**：可选开关（默认关闭），开启后 Home/End 映射到 `Cmd+←/→`（对应 F5）

### 4. Delete 键方向相反（⚠️ MacBridge 不处理）
- **现象**：
  - Mac 内置键盘的"delete"键 = 向左删（Backspace）
  - Win 的 `Delete` 键 = 向右删
- **真实场景分析**：
  - **外接 Win 键盘**：导航簇的独立 `Delete` 键在 macOS 上**本就是向右删**，无需映射
  - **MacBook 内置键盘**：要向右删必须按 `Fn+Delete`，这是 Mac 布局本身的设计，不在 Win 布局 profile 范围内
- **结论**：MacBridge 无可做的事，该痛点实际由用户习惯 `Fn+Delete` 解决

### 5. F 区默认行为不同（⚠️ MacBridge 不处理）
- **现象**：
  - Mac 自带键盘：F 区默认是亮度/音量，按 Fn 才是 F1-F12
  - Win 外接键盘：F 区默认是 F1-F12
- **真实场景分析**：
  - macOS 对**非 Apple 外接键盘默认就是 F1-F12**
  - 只有 Apple 键盘和 MacBook 内置才 Fn-lock 到亮度/音量
  - 切换此行为需要用户在"系统设置 → 键盘"里手动勾选，`CGEventTap` 层无可改写空间
- **结论**：MacBridge 不做独立功能，首次启动引导里可提示用户这一系统设置

### 6. PgUp/PgDn 在小键盘布局差异
- 紧凑布局的 Win 键盘（HHKB/60%）通过 Fn+方向键实现，Mac 原生 Fn 组合不同
- **MacBridge 做法**：暂不处理，用户可用原厂软件配置

### 7. 输入法切换键
- **现象**：
  - Win 用户习惯：`Shift` 或 `Ctrl+Shift` 切中英
  - Mac 默认：`Ctrl+Space` 或 `Caps Lock`
- **影响**：打字节奏被打断
- **MacBridge 做法**：v0.2 提供映射选项（`Shift` 切中英 = 按一次 Caps）

---

## ⭐ 低频但尖锐的痛点

### 8. 截图快捷键
- Win: `PrintScreen` / `Win+Shift+S`
- Mac: `Cmd+Shift+3` / `Cmd+Shift+4`
- **MacBridge 做法**：v0.2 把 `PrintScreen` 映射到 `Cmd+Shift+4`

### 9. 锁屏快捷键
- Win: `Win+L`
- Mac: `Ctrl+Cmd+Q`
- **MacBridge 做法**：v0.2 映射 `Win+L`

### 10. 任务管理器 vs 强制退出
- Win: `Ctrl+Alt+Del`
- Mac: `Cmd+Option+Esc`
- **MacBridge 做法**：优先级低，暂不做

### 11. 符号位置差异（ISO / JIS 布局）
- 日版 / 欧版键盘接到 Mac 上，`@` `"` 等符号位置错乱
- **MacBridge 做法**：不处理（macOS 设置 → 键盘 → 输入源可以选择布局）

### 12. 右 Shift / Enter 大小差异
- 物理键大小，软件无法解决

### 13. Caps Lock 行为差异
- Mac 的 Caps 按一下切换输入法（长按才锁大写），Win 按一下就锁大写
- **MacBridge 做法**：v0.2 可选：让 Caps 单击切换输入法（符合 Mac 习惯但 Win 用户可能不适应）

---

## 非键盘但值得提及（暂不做）

- 鼠标滚轮方向（Mac 自然滚动 vs Win 反向）
- 触控板手势
- 右键菜单逻辑
- 文件管理器 Finder 的剪切/粘贴不同（Cmd+C + Cmd+Option+V）

这些属于系统交互层，不在 MacBridge 范围内。
