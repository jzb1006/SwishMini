//
//  WindowManager.swift
//  SwishMini
//
//  窗口管理器 - 检测标题栏和执行窗口操作
//

import Foundation
import ApplicationServices
import Cocoa

// MARK: - 私有 API 声明

/// 获取 AXUIElement 对应的 CGWindowID（私有 API，用于精确窗口匹配）
/// 运行时动态加载，失败则回退到公开 API
private var _AXUIElementGetWindowFunc: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
        print("⚠️ [WindowManager] 私有 API _AXUIElementGetWindow 不可用，将使用公开 API 回退")
        return nil
    }
    return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
}()

class WindowManager {
    
    static let shared = WindowManager()
    
    private init() {}
    
    // MARK: - 窗口检测
    
    /// 获取鼠标位置下的窗口
    func getWindowUnderMouse(_ mouseLocation: CGPoint) -> (window: AXUIElement, frame: CGRect)? {
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let mainScreenHeight = mainScreen.frame.height
        let screenPoint = CGPoint(x: mouseLocation.x, y: mainScreenHeight - mouseLocation.y)

        // 排除自身进程的窗口（如 HUD 浮层），防止 HUD 干扰窗口检测导致抖动
        let selfPID = getpid()

        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for windowInfo in windowList {
            let cgWindowNumber = windowInfo[kCGWindowNumber as String] as? CGWindowID
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer >= 0 && layer < 25,
                  ownerPID != selfPID else {  // 忽略 SwishMini 自身的窗口
                continue
            }

            let windowFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )

            // 过滤太小的窗口（如 Chrome 全屏时的工具栏，高度只有几十像素）
            let minWindowSize: CGFloat = 100
            guard windowFrame.width >= minWindowSize && windowFrame.height >= minWindowSize else {
                continue
            }

            if windowFrame.contains(screenPoint) {
                let app = AXUIElementCreateApplication(ownerPID)

                var windowsValue: AnyObject?
                let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)

                guard result == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
                    continue
                }

                // 优先用 CGWindowNumber 精确匹配 AXWindow（解决 Chrome 多窗口/全屏场景取错窗口问题）
                let matchedWindow: AXUIElement? = cgWindowNumber.flatMap { targetID in
                    windows.first { getAXWindowID($0) == targetID }
                }

                // Fallback: focusedWindow > windows.first
                let fallbackFocused = getFocusedWindow(for: app)
                let candidateWindow = matchedWindow ?? fallbackFocused ?? windows.first

                if matchedWindow == nil {
                    let focusedID = fallbackFocused.flatMap { getAXWindowID($0) }
                    print("⚠️ [WindowManager] AX 窗口映射 fallback (cgWindowID: \(cgWindowNumber.map(String.init) ?? "nil"), focusedAXWindowID: \(focusedID.map(String.init) ?? "nil"), windowCount: \(windows.count))")
                }

                if let window = candidateWindow, let axFrame = getWindowFrame(window) {
                    return (window, axFrame)
                }
            }
        }
        
        return nil
    }
    
    /// 检查鼠标是否在窗口标题栏区域
    func isPointOnTitleBar(_ point: CGPoint) -> Bool {
        guard let mainScreen = NSScreen.screens.first else { return false }
        let screenHeight = mainScreen.frame.height

        // 单次查询窗口信息，确保结果一致性
        let windowInfo = getWindowUnderMouse(point)

        // 全屏检测：鼠标在屏幕顶部边缘（用于触发全屏标题栏）
        let screenTopEdge: CGFloat = 6  // 顶部 6 像素触发区域
        if point.y >= screenHeight - screenTopEdge {
            // 检查当前窗口是否全屏
            if let window = windowInfo?.window, isWindowFullScreen(window) {
                return true
            }
        }

        // 普通窗口标题栏检测
        guard let frame = windowInfo?.frame else {
            return false
        }

        let screenPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        let titleBarHeight: CGFloat = 30.0
        let titleBarRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: titleBarHeight)

        return titleBarRect.contains(screenPoint)
    }

    /// 检查窗口是否处于全屏状态
    /// - Note: 对 Chrome 进行特殊处理，因为 Chrome 使用键盘快捷键进入的"演示模式"全屏
    ///         不会设置 AXFullScreen 属性，需要通过窗口尺寸判断
    func isWindowFullScreen(_ window: AXUIElement) -> Bool {
        // 方法1: 检查标准的 AXFullScreen 属性
        var fullScreenValue: AnyObject?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenValue) == .success,
           let isFullScreen = fullScreenValue as? Bool, isFullScreen {
            return true
        }

        // 方法2: 对 Chrome 进行视觉全屏检测
        // Chrome 使用 ⌘+Ctrl+F 进入的全屏不会设置 AXFullScreen 属性
        if isChrome(window) {
            return isWindowVisuallyFullScreen(window)
        }

        return false
    }

    /// 检查窗口是否"视觉上全屏"（覆盖整个屏幕，包括菜单栏区域）
    /// - Note: 用于检测 Chrome 等不设置 AXFullScreen 属性的应用
    /// - Important: AX API 使用左上角坐标系，NSScreen 使用左下角坐标系，需要转换
    private func isWindowVisuallyFullScreen(_ window: AXUIElement) -> Bool {
        guard let windowFrame = getWindowFrame(window) else {
            return false
        }

        guard let mainScreen = NSScreen.screens.first else {
            return false
        }
        let mainScreenHeight = mainScreen.frame.height

        // 将 AX 坐标系（左上角原点）转换为 Cocoa 坐标系（左下角原点）
        let windowFrameCocoa = CGRect(
            x: windowFrame.origin.x,
            y: mainScreenHeight - windowFrame.origin.y - windowFrame.height,
            width: windowFrame.width,
            height: windowFrame.height
        )

        // 选取与窗口交集面积最大的屏幕（比 center-contains 更稳健，避免边缘漂移误判）
        let bestScreen = NSScreen.screens.max { intersectionArea(windowFrameCocoa, $0.frame) < intersectionArea(windowFrameCocoa, $1.frame) }
        guard let screen = bestScreen ?? NSScreen.main else {
            return false
        }

        let screenFrame = screen.frame

        // Chrome 演示模式全屏特征：窗口覆盖整个屏幕（包括菜单栏）
        // 使用比例容差 + 最小容差，兼容不同显示器/缩放/刘海安全区
        let minTolerance: CGFloat = 10.0
        let relativeTolerance: CGFloat = 0.01

        let tolX = max(minTolerance, screenFrame.width * relativeTolerance)
        let tolY = max(minTolerance, screenFrame.height * relativeTolerance)

        let dx = abs(windowFrameCocoa.origin.x - screenFrame.origin.x)
        let dy = abs(windowFrameCocoa.origin.y - screenFrame.origin.y)
        let dw = abs(windowFrameCocoa.width - screenFrame.width)
        let dh = abs(windowFrameCocoa.height - screenFrame.height)

        let isVisuallyFullScreen = dx <= tolX && dy <= tolY && dw <= tolX && dh <= tolY

        // 打印诊断日志（调试期间保留）
        print("🔍 [WindowManager] 视觉全屏检测: result=\(isVisuallyFullScreen), window=(\(String(format: "%.0f", windowFrameCocoa.origin.x)),\(String(format: "%.0f", windowFrameCocoa.origin.y)),\(String(format: "%.0f", windowFrameCocoa.width))x\(String(format: "%.0f", windowFrameCocoa.height))), screen=(\(String(format: "%.0f", screenFrame.origin.x)),\(String(format: "%.0f", screenFrame.origin.y)),\(String(format: "%.0f", screenFrame.width))x\(String(format: "%.0f", screenFrame.height))), diff=(x:\(String(format: "%.1f", dx)) y:\(String(format: "%.1f", dy)) w:\(String(format: "%.1f", dw)) h:\(String(format: "%.1f", dh))), tol=\(String(format: "%.1f", tolX))")

        return isVisuallyFullScreen
    }

    // MARK: - 窗口信息

    /// 获取 AXUIElement 的 CGWindowID（用于精确窗口匹配）
    /// 优先使用私有 API，失败则回退到公开属性
    private func getAXWindowID(_ window: AXUIElement) -> CGWindowID? {
        // 方法1：私有 API（更可靠）
        if let getWindowFunc = _AXUIElementGetWindowFunc {
            var windowID: CGWindowID = 0
            if getWindowFunc(window, &windowID) == .success {
                return windowID
            }
        }

        // 方法2：公开属性（回退）
        var value: AnyObject?
        if AXUIElementCopyAttributeValue(window, "AXWindowNumber" as CFString, &value) == .success {
            if let num = value as? NSNumber {
                return CGWindowID(num.uint32Value)
            }
        }

        return nil
    }

    /// 获取应用的焦点窗口
    private func getFocusedWindow(for app: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let result = value else {
            return nil
        }
        // AXUIElement 是 CoreFoundation 类型，API 成功时必定返回有效值
        return (result as! AXUIElement)
    }

    /// 计算两个矩形的交集面积
    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return 0 }
        return inter.width * inter.height
    }

    private func getWindowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: AnyObject?
        var sizeValue: AnyObject?
        
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success else {
            return nil
        }
        
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        
        return CGRect(origin: point, size: size)
    }
    
    // MARK: - 应用识别
    
    /// 获取窗口所属应用的 Bundle ID
    private func getAppBundleIdentifier(for window: AXUIElement) -> String? {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        if let app = NSRunningApplication(processIdentifier: pid) {
            return app.bundleIdentifier
        }
        return nil
    }
    
    /// 检测是否为 Chrome 浏览器
    private func isChrome(_ window: AXUIElement) -> Bool {
        let bundleId = getAppBundleIdentifier(for: window)
        return bundleId == "com.google.Chrome" || bundleId == "com.google.Chrome.canary"
    }
    
    /// 使用键盘快捷键切换全屏 (⌘ + Ctrl + F)
    private func toggleFullScreenViaKeyboard() -> Bool {
        print("⌨️ [WindowManager] 使用键盘快捷键切换全屏")
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x03, keyDown: true)  // F 键
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x03, keyDown: false)
        
        keyDown?.flags = [.maskControl, .maskCommand]
        keyUp?.flags = [.maskControl, .maskCommand]
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        return true
    }
    
    // MARK: - 窗口操作
    
    /// 最小化窗口
    @discardableResult
    func minimizeWindow(_ window: AXUIElement) -> Bool {
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
    }
    
    /// 取消最小化窗口
    @discardableResult
    func unminimizeWindow(_ window: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        if result == .success {
            print("✅ [WindowManager] 窗口已恢复")
            return true
        } else {
            print("❌ [WindowManager] 恢复窗口失败: \(result)")
            return false
        }
    }
    
    /// 关闭窗口
    @discardableResult
    func closeWindow(_ window: AXUIElement) -> Bool {
        var closeButton: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButton) == .success else {
            return false
        }
        return AXUIElementPerformAction(closeButton as! AXUIElement, kAXPressAction as CFString) == .success
    }
    
    /// 切换全屏
    @discardableResult
    func toggleFullScreen(_ window: AXUIElement) -> Bool {
        // Chrome 兼容性：优先使用键盘快捷键
        if isChrome(window) {
            print("🌐 [WindowManager] 检测到 Chrome，使用键盘快捷键切换全屏")
            return toggleFullScreenViaKeyboard()
        }
        
        // 方法1: 直接设置 AXFullScreen 属性（最可靠）
        var fullScreenValue: AnyObject?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenValue) == .success,
           let isFullScreen = fullScreenValue as? Bool {
            let newValue = !isFullScreen as CFBoolean
            let result = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, newValue)
            if result == .success {
                print("✅ [WindowManager] 全屏状态切换成功: \(isFullScreen) -> \(!isFullScreen)")
                return true
            }
        }
        
        // 方法2: 点击全屏按钮
        var fullScreenButton: AnyObject?
        if AXUIElementCopyAttributeValue(window, kAXFullScreenButtonAttribute as CFString, &fullScreenButton) == .success {
            let result = AXUIElementPerformAction(fullScreenButton as! AXUIElement, kAXPressAction as CFString)
            if result == .success {
                print("✅ [WindowManager] 通过全屏按钮切换成功")
                return true
            }
        }
        
        // 方法3: 回退到键盘快捷键（最后手段）
        print("⚠️ [WindowManager] 回退到键盘快捷键模拟")
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x03, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x03, keyDown: false)
        
        keyDown?.flags = [.maskControl, .maskCommand]
        keyUp?.flags = [.maskControl, .maskCommand]
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        return true
    }
    
    /// 还原窗口（仅在全屏状态下退出全屏；非全屏不执行，避免触发 Zoom 等副作用）
    @discardableResult
    func restoreWindow(_ window: AXUIElement) -> Bool {
        // 仅处理全屏退出：非全屏不执行，避免 Zoom/快捷键误触发全屏等副作用
        guard isWindowFullScreen(window) else {
            print("ℹ️ [WindowManager] 当前窗口非全屏，忽略还原请求")
            return false
        }

        print("🔄 [WindowManager] 退出全屏模式")
        return toggleFullScreen(window)
    }
}
