//
//  WindowManager.swift
//  SwishMini
//
//  窗口管理器 - 检测标题栏和执行窗口操作
//

import Foundation
import ApplicationServices
import Cocoa

class WindowManager {
    
    static let shared = WindowManager()
    
    private init() {}
    
    // MARK: - 窗口检测
    
    /// 获取鼠标位置下的窗口
    func getWindowUnderMouse(_ mouseLocation: CGPoint) -> (window: AXUIElement, frame: CGRect)? {
        guard let mainScreen = NSScreen.screens.first else { return nil }
        let mainScreenHeight = mainScreen.frame.height
        let screenPoint = CGPoint(x: mouseLocation.x, y: mainScreenHeight - mouseLocation.y)
        
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        
        for windowInfo in windowList {
            guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer >= 0 && layer < 25 else {
                continue
            }
            
            let windowFrame = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            
            if windowFrame.contains(screenPoint) {
                let app = AXUIElementCreateApplication(ownerPID)
                
                var windowsValue: AnyObject?
                let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
                
                guard result == .success, let windows = windowsValue as? [AXUIElement], !windows.isEmpty else {
                    continue
                }
                
                // 返回第一个窗口
                if let firstWindow = windows.first, let axFrame = getWindowFrame(firstWindow) {
                    return (firstWindow, axFrame)
                }
            }
        }
        
        return nil
    }
    
    /// 检查鼠标是否在窗口标题栏区域
    func isPointOnTitleBar(_ point: CGPoint) -> Bool {
        guard let mainScreen = NSScreen.screens.first else { return false }
        let screenHeight = mainScreen.frame.height

        // 全屏检测：鼠标在屏幕顶部边缘（用于触发全屏标题栏）
        let screenTopEdge: CGFloat = 6  // 顶部 6 像素触发区域
        if point.y >= screenHeight - screenTopEdge {
            // 检查当前窗口是否全屏
            if let (window, _) = getWindowUnderMouse(point), isWindowFullScreen(window) {
                return true
            }
        }

        // 普通窗口标题栏检测
        guard let (_, frame) = getWindowUnderMouse(point) else {
            return false
        }

        let screenPoint = CGPoint(x: point.x, y: screenHeight - point.y)

        let titleBarHeight: CGFloat = 30.0
        let titleBarRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: titleBarHeight)

        return titleBarRect.contains(screenPoint)
    }

    /// 检查窗口是否处于全屏状态
    func isWindowFullScreen(_ window: AXUIElement) -> Bool {
        var fullScreenValue: AnyObject?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenValue) == .success,
           let isFullScreen = fullScreenValue as? Bool {
            return isFullScreen
        }
        return false
    }
    
    // MARK: - 窗口信息
    
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
