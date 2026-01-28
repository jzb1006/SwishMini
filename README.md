<div align="center">

# SwishMini

**通过触控板手势控制任意 macOS 窗口**
**Control Any macOS Window with Trackpad Gestures**

[![Version](https://img.shields.io/badge/version-1.0-blue.svg)](https://github.com/yourusername/SwishMini/releases)
[![macOS](https://img.shields.io/badge/macOS-26.1%2B-brightgreen.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange.svg)](https://swift.org)

[中文](#zh-cn) | [English](#en)

</div>

---

<a name="zh-cn"></a>

## 📺 功能演示

> 💡 **提示**：您可以在此处添加 GIF 动图展示应用效果
>
> 建议录制以下场景：
> - 双指张开手势 → 窗口全屏
> - 双指捏合手势 → 窗口还原（全屏时）
> - 上滑 1秒 → 关闭窗口（非全屏时，带环形进度条）
> - 双指下滑手势 → 窗口最小化
> - 双指上滑手势 → 恢复最小化窗口

**预期效果：**
- ✅ 流畅的手势识别
- ✅ 即时的窗口响应
- ✅ 支持任意应用窗口
- ✅ Chrome 浏览器特别优化
- ✅ 实时 HUD 视觉反馈（环形进度条 + 颜色渐变）

---

## ✨ 核心功能

SwishMini 为 macOS 带来直观的触控板手势控制，让窗口管理更加高效。

### 手势映射表

| 手势 | 动作 | 说明 |
|------|------|------|
| 👐 **双指张开** | 全屏 | 将当前窗口切换至全屏模式 |
| 🤏 **双指捏合** | 还原 | 全屏时退出全屏 |
| 👆 **上滑 1秒** | 关闭窗口 | 非全屏时上滑 1 秒关闭当前窗口 |
| 👇 **双指下滑** | 最小化 | 最小化当前窗口到 Dock |
| 👆 **双指上滑** | 取消最小化 | 在原位置恢复最小化的窗口 |

### 🎯 HUD 视觉反馈

执行手势时，屏幕会显示实时视觉反馈：

- **环形进度条**：上滑关闭窗口时显示倒计时进度环
- **颜色渐变**：从橙色平滑过渡到红色，表示紧迫程度
- **进度百分比**：实时显示当前进度（如 50%、75%）
- **取消提示**：松手或收回手指时显示"已取消"

### 🌐 特别支持

- **Chrome 浏览器兼容性**：自动检测并使用键盘快捷键（⌘ + Ctrl + F），确保全屏功能在 Chrome 中正常工作
- **智能手势识别**：区分滑动和捏合动作，避免误触发
- **位置记忆**：最小化窗口后，在原位置附近上滑即可恢复

---

## 🚀 快速开始

### 下载安装

1. **下载应用**
   ```
   [待发布] - 后续将提供 GitHub Releases 下载链接
   ```

2. **安装步骤**
   - 解压下载的 ZIP 文件
   - 将 `SwishMini.app` 拖入 `/Applications` 文件夹
   - 双击打开应用

3. **处理安全提示** 🔐

   由于 SwishMini 未经过 Apple 公证，首次打开时可能会看到提示：

   > "Apple 无法验证 'SwishMini' 是否包含可能危害 Mac 安全或泄漏隐私的恶意软件。"

   **解决方法（选择其一）：**

   **方法一：右键打开（推荐）**
   - 在 Finder 中找到 `SwishMini.app`
   - 按住 `Control` 键点击（或右键点击）应用图标
   - 选择"打开"
   - 在弹出的对话框中点击"打开"

   **方法二：系统设置允许**
   - 尝试打开应用后，前往 `系统设置 > 隐私与安全性`
   - 滚动到底部，找到关于 SwishMini 被阻止的提示
   - 点击"仍要打开"

   **方法三：终端命令（高级用户）**
   ```bash
   xattr -cr /Applications/SwishMini.app
   ```
   然后正常双击打开应用。

4. **授予权限** ⚠️ **重要步骤**

   首次运行时，系统会提示授予 **辅助功能权限**：

   - 方式一：点击系统弹窗中的"打开系统偏好设置"
   - 方式二：手动前往 `系统设置 > 隐私与安全性 > 辅助功能`
   - 勾选 `SwishMini` 旁边的复选框
   - 重启应用使权限生效

5. **验证安装**

   打开任意窗口（如 Safari、Finder），在窗口标题栏区域尝试：
   - 双指张开 → 窗口应进入全屏
   - 双指捏合 → 窗口应退出全屏
   - 双指下滑 → 窗口应最小化
   - 双指上滑 → 窗口应恢复

### 如何退出/禁用

- **临时退出**：点击菜单栏图标 → 选择"退出"
- **完全卸载**：将应用从 `/Applications` 文件夹移到废纸篓
- **撤销权限**：前往 `系统设置 > 隐私与安全性 > 辅助功能`，取消勾选 `SwishMini`

---

## ⚙️ 系统要求

| 项目 | 要求 |
|------|------|
| **操作系统** | macOS 26.1 或更高版本 |
| **设备** | 配备触控板的 Mac（内置或外接） |
| **架构** | Apple Silicon (M1/M2/M3) 或 Intel |
| **权限** | 辅助功能访问权限 |

**已测试应用：**
- ✅ Safari
- ✅ Finder
- ✅ Chrome / Chrome Canary
- ✅ 大多数第三方应用

---

## 🔐 权限说明

SwishMini 需要以下系统权限才能正常工作：

| 权限 | 用途 | 如何授予 | 如何撤销 |
|------|------|---------|---------|
| **辅助功能** | 检测窗口信息并执行窗口操作（全屏、最小化等） | `系统设置 > 隐私与安全性 > 辅助功能` 勾选应用 | 同路径，取消勾选 |

### 详细说明

- **辅助功能 (Accessibility)**：
  - ✅ 允许应用获取鼠标下的窗口信息
  - ✅ 允许应用控制窗口状态（全屏、最小化、还原）
  - ❌ 不会读取窗口内容
  - ❌ 不会记录键盘输入
  - ❌ 不会采集任何个人数据

**重要提示**：SwishMini 完全在本地运行，不联网、不采集数据、不发送任何信息。

---

## ⌨️ 快捷键

当前版本（v1.0）专注于触控板手势操作，暂不支持键盘快捷键。

**计划中的功能**：
- 🔜 自定义快捷键绑定
- 🔜 快捷键与手势混合使用
- 🔜 全局快捷键支持

---

## ⚠️ 已知问题与限制

1. **手势冲突**
   - 可能与系统自带手势或第三方手势工具（如 BetterTouchTool）冲突
   - 建议禁用重复的手势设置

2. **窗口类型限制**
   - 某些系统窗口（如"关于本机"）可能不响应
   - 全屏空间中的窗口需要先退出全屏
   - 受保护的窗口（如系统偏好设置中的某些面板）无法控制

3. **权限要求**
   - 必须授予辅助功能权限才能使用
   - 权限变更后需要重启应用

4. **Chrome 浏览器**
   - 使用键盘快捷键模拟（⌘ + Ctrl + F）切换全屏
   - 可能与 Chrome 扩展冲突

5. **多显示器**
   - 当前版本主要针对主显示器优化
   - 在多显示器环境下的行为可能不一致

---

## 🆘 故障排查

### 问题：手势无效 / 没有反应

**解决方法：**

1. ✅ **检查权限**
   - 前往 `系统设置 > 隐私与安全性 > 辅助功能`
   - 确认 `SwishMini` 已勾选
   - 如果已勾选，尝试取消后重新勾选

2. ✅ **重启应用**
   - 完全退出 SwishMini
   - 重新启动应用
   - 再次测试手势

3. ✅ **检查手势位置**
   - 确保手势在**窗口标题栏区域**进行
   - 标题栏通常是窗口顶部约 30px 的区域

4. ✅ **检查触控板**
   - 确认触控板功能正常
   - 在系统设置中测试其他手势是否工作

5. ✅ **检查应用兼容性**
   - 某些应用可能不支持窗口控制
   - 尝试在 Safari 或 Finder 中测试

### 问题：与其他手势工具冲突

**解决方法：**
- 暂时禁用其他手势工具（如 BetterTouchTool、Magnet）
- 调整其他工具的手势设置，避免重复

### 问题：Chrome 全屏不工作

**解决方法：**
- 检查 Chrome 是否禁用了 `⌘ + Ctrl + F` 快捷键
- 检查 Chrome 扩展是否占用了该快捷键
- 尝试在无扩展模式下使用

---

## 🔒 隐私与安全

SwishMini 严格遵守用户隐私：

- ✅ **完全本地运行**：所有操作在您的 Mac 上完成
- ✅ **不联网**：应用不会连接任何服务器
- ✅ **不采集数据**：不收集、不存储、不发送任何使用数据
- ✅ **不读取内容**：仅控制窗口状态，不读取窗口内容
- ✅ **开源透明**：代码公开，欢迎审查

**权限使用**：
- 辅助功能权限仅用于窗口位置检测和状态控制
- 所有操作均在您明确执行手势时触发
- 不会后台运行任何监控或记录功能

---

## 📄 许可证

本项目采用 [MIT License](LICENSE) 开源协议。

**简单来说**：
- ✅ 可自由使用、修改、分发
- ✅ 可用于商业用途
- ⚠️ 需保留版权声明
- ❌ 不提供任何担保

---

## 🙏 致谢

感谢以下项目和资源的启发：

- [MultitouchSupport.framework](https://github.com/calftrail/Touch) - macOS 触控板私有框架
- [Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement) - macOS 窗口控制能力

---

## 📧 联系方式

- **作者**：江志彬
- **问题反馈**：[GitHub Issues](https://github.com/yourusername/SwishMini/issues)
- **功能建议**：[GitHub Discussions](https://github.com/yourusername/SwishMini/discussions)

---

<div align="center">

**如果 SwishMini 对您有帮助，请给个 ⭐️ Star 支持一下！**

Made with ❤️ by 江志彬

</div>

---
---

<a name="en"></a>

<div align="center">

# SwishMini

**Control Any macOS Window with Trackpad Gestures**

</div>

## 📺 Demo

> 💡 **Tip**: You can add GIF animations here to showcase the app in action
>
> Suggested scenarios to record:
> - Two-finger pinch open → Window goes fullscreen
> - Two-finger pinch close → Window restores (when fullscreen)
> - Swipe up 1s → Close window (when not fullscreen, with progress ring)
> - Two-finger swipe down → Window minimizes
> - Two-finger swipe up → Restore minimized window

**Expected Effects:**
- ✅ Smooth gesture recognition
- ✅ Instant window response
- ✅ Works with any application window
- ✅ Special optimization for Chrome browser
- ✅ Real-time HUD visual feedback (progress ring + color gradient)

---

## ✨ Core Features

SwishMini brings intuitive trackpad gesture control to macOS, making window management more efficient.

### Gesture Mapping Table

| Gesture | Action | Description |
|---------|--------|-------------|
| 👐 **Two-Finger Pinch Open** | Fullscreen | Switch current window to fullscreen mode |
| 🤏 **Two-Finger Pinch Close** | Restore | Exit fullscreen (when in fullscreen) |
| 👆 **Swipe Up 1s** | Close Window | Close current window (when not fullscreen) |
| 👇 **Two-Finger Swipe Down** | Minimize | Minimize current window to Dock |
| 👆 **Two-Finger Swipe Up** | Unminimize | Restore minimized window at original location |

### 🎯 HUD Visual Feedback

Real-time visual feedback is displayed when performing gestures:

- **Progress Ring**: Shows countdown progress when swiping up to close window
- **Color Gradient**: Smoothly transitions from orange to red, indicating urgency
- **Progress Percentage**: Displays current progress in real-time (e.g., 50%, 75%)
- **Cancel Indicator**: Shows "Cancelled" when releasing or retracting fingers

### 🌐 Special Support

- **Chrome Browser Compatibility**: Automatically detects and uses keyboard shortcuts (⌘ + Ctrl + F) to ensure fullscreen works properly in Chrome
- **Smart Gesture Recognition**: Distinguishes between swipe and pinch actions to avoid false triggers
- **Location Memory**: After minimizing a window, swipe up near the original location to restore it

---

## 🚀 Quick Start

### Download & Installation

1. **Download the App**
   ```
   [To be released] - GitHub Releases download link will be provided
   ```

2. **Installation Steps**
   - Unzip the downloaded ZIP file
   - Drag `SwishMini.app` to the `/Applications` folder
   - Double-click to open the app

3. **Handle Security Warning** 🔐

   Since SwishMini is not notarized by Apple, you may see a warning on first launch:

   > "Apple could not verify 'SwishMini' is free of malware that may harm your Mac or compromise your privacy."

   **Solutions (choose one):**

   **Method 1: Right-Click to Open (Recommended)**
   - Find `SwishMini.app` in Finder
   - Hold `Control` and click (or right-click) the app icon
   - Select "Open"
   - Click "Open" in the dialog that appears

   **Method 2: Allow in System Settings**
   - After attempting to open the app, go to `System Settings > Privacy & Security`
   - Scroll to the bottom and find the message about SwishMini being blocked
   - Click "Open Anyway"

   **Method 3: Terminal Command (Advanced Users)**
   ```bash
   xattr -cr /Applications/SwishMini.app
   ```
   Then double-click to open the app normally.

4. **Grant Permissions** ⚠️ **Important Step**

   On first launch, the system will prompt for **Accessibility permission**:

   - Method 1: Click "Open System Preferences" in the system alert
   - Method 2: Manually go to `System Settings > Privacy & Security > Accessibility`
   - Check the checkbox next to `SwishMini`
   - Restart the app for permissions to take effect

5. **Verify Installation**

   Open any window (e.g., Safari, Finder) and try these gestures over the window title bar:
   - Two-finger pinch open → Window should go fullscreen
   - Two-finger pinch close → Window should exit fullscreen
   - Two-finger swipe down → Window should minimize
   - Two-finger swipe up → Window should restore

### How to Quit/Disable

- **Temporary Quit**: Click menu bar icon → Select "Quit"
- **Complete Uninstall**: Move the app from `/Applications` to Trash
- **Revoke Permissions**: Go to `System Settings > Privacy & Security > Accessibility`, uncheck `SwishMini`

---

## ⚙️ System Requirements

| Item | Requirement |
|------|-------------|
| **Operating System** | macOS 26.1 or later |
| **Device** | Mac with trackpad (built-in or external) |
| **Architecture** | Apple Silicon (M1/M2/M3) or Intel |
| **Permissions** | Accessibility access permission |

**Tested Applications:**
- ✅ Safari
- ✅ Finder
- ✅ Chrome / Chrome Canary
- ✅ Most third-party applications

---

## 🔐 Permissions

SwishMini requires the following system permissions to function:

| Permission | Purpose | How to Grant | How to Revoke |
|------------|---------|--------------|---------------|
| **Accessibility** | Detect window information and perform window operations (fullscreen, minimize, etc.) | `System Settings > Privacy & Security > Accessibility` check the app | Same path, uncheck |

### Detailed Explanation

- **Accessibility**:
  - ✅ Allows the app to get window information under the mouse cursor
  - ✅ Allows the app to control window states (fullscreen, minimize, restore)
  - ❌ Does NOT read window content
  - ❌ Does NOT record keyboard input
  - ❌ Does NOT collect any personal data

**Important Note**: SwishMini runs completely locally, does not connect to the internet, does not collect data, and does not send any information.

---

## ⌨️ Keyboard Shortcuts

The current version (v1.0) focuses on trackpad gesture control and does not support keyboard shortcuts yet.

**Planned Features**:
- 🔜 Custom keyboard shortcut bindings
- 🔜 Mixed use of shortcuts and gestures
- 🔜 Global shortcut support

---

## ⚠️ Known Issues & Limitations

1. **Gesture Conflicts**
   - May conflict with system gestures or third-party gesture tools (e.g., BetterTouchTool)
   - Recommend disabling duplicate gesture settings

2. **Window Type Limitations**
   - Some system windows (e.g., "About This Mac") may not respond
   - Windows in fullscreen spaces need to exit fullscreen first
   - Protected windows (e.g., some System Settings panels) cannot be controlled

3. **Permission Requirements**
   - Accessibility permission must be granted for use
   - App needs to be restarted after permission changes

4. **Chrome Browser**
   - Uses keyboard shortcut simulation (⌘ + Ctrl + F) to toggle fullscreen
   - May conflict with Chrome extensions

5. **Multiple Displays**
   - Current version primarily optimized for the main display
   - Behavior may be inconsistent in multi-display environments

---

## 🆘 Troubleshooting

### Issue: Gestures Not Working / No Response

**Solutions:**

1. ✅ **Check Permissions**
   - Go to `System Settings > Privacy & Security > Accessibility`
   - Confirm `SwishMini` is checked
   - If already checked, try unchecking and rechecking

2. ✅ **Restart the App**
   - Completely quit SwishMini
   - Restart the application
   - Test gestures again

3. ✅ **Check Gesture Location**
   - Ensure gestures are performed over the **window title bar area**
   - Title bar is usually the top ~30px area of the window

4. ✅ **Check Trackpad**
   - Confirm trackpad is functioning properly
   - Test other gestures in System Settings

5. ✅ **Check App Compatibility**
   - Some apps may not support window control
   - Try testing in Safari or Finder

### Issue: Conflicts with Other Gesture Tools

**Solutions:**
- Temporarily disable other gesture tools (e.g., BetterTouchTool, Magnet)
- Adjust settings in other tools to avoid duplicates

### Issue: Chrome Fullscreen Not Working

**Solutions:**
- Check if Chrome has disabled the `⌘ + Ctrl + F` shortcut
- Check if Chrome extensions are using that shortcut
- Try using without extensions

---

## 🔒 Privacy & Security

SwishMini strictly respects user privacy:

- ✅ **Completely Local**: All operations are performed on your Mac
- ✅ **No Internet Connection**: The app does not connect to any servers
- ✅ **No Data Collection**: Does not collect, store, or send any usage data
- ✅ **No Content Reading**: Only controls window states, does not read window content
- ✅ **Open Source & Transparent**: Code is public, welcome to review

**Permission Usage**:
- Accessibility permission is only used for window position detection and state control
- All operations are triggered only when you explicitly perform gestures
- No background monitoring or recording functions

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

**In Simple Terms**:
- ✅ Free to use, modify, and distribute
- ✅ Can be used for commercial purposes
- ⚠️ Must retain copyright notice
- ❌ No warranty provided

---

## 🙏 Acknowledgments

Thanks to the following projects and resources for inspiration:

- [MultitouchSupport.framework](https://github.com/calftrail/Touch) - macOS trackpad private framework
- [Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement) - macOS window control capabilities

---

## 📧 Contact

- **Author**: 江志彬 (Jiang Zhibin)
- **Bug Reports**: [GitHub Issues](https://github.com/yourusername/SwishMini/issues)
- **Feature Requests**: [GitHub Discussions](https://github.com/yourusername/SwishMini/discussions)

---

<div align="center">

**If SwishMini is helpful to you, please give it a ⭐️ Star!**

Made with ❤️ by 江志彬

</div>