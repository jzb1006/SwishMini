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
        return nil
    }
    return unsafeBitCast(symbol, to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self)
}()

class WindowManager {

    static let shared = WindowManager()

    /// 最小有效窗口尺寸（过滤 Chrome 全屏工具栏等小窗口）
    private let minWindowSize: CGFloat = 100

    private init() {}
    
    // MARK: - 窗口检测
    
    /// 获取鼠标位置下的窗口
    func getWindowUnderMouse(_ mouseLocation: CGPoint) -> (window: AXUIElement, frame: CGRect)? {
        guard let mainDisplayHeight = mainDisplayHeightForAXCoordinates() else { return nil }
        let screenPoint = cocoaToAX(mouseLocation, mainDisplayHeight: mainDisplayHeight)

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

                // Chrome 演示模式全屏等场景下，"鼠标下的 CGWindow"可能没有对应的 AXWindow。
                // 此时用几何/命中测试把 CGWindow 归并到正确的顶层 AXWindow，避免错误回退到 focusedWindow。
                let geometryMatchedWindow: AXUIElement? = (matchedWindow == nil) ? bestMatchingAXWindow(
                    windows,
                    cgWindowFrame: windowFrame,
                    screenPointAX: screenPoint
                ) : nil

                // Fallback 优先级：精确匹配 > 几何匹配 > focusedWindow > first
                let fallbackFocused = getFocusedWindow(for: app)
                let candidateWindow = matchedWindow ?? geometryMatchedWindow ?? fallbackFocused ?? windows.first

                if let window = candidateWindow, let axFrame = getWindowFrame(window) {
                    return (window, axFrame)
                }
            }
        }
        
        return nil
    }
    
    /// 检查鼠标是否在窗口标题栏区域
    /// - Note: Chrome 全屏检测不可靠，对 Chrome 使用更宽松的判断
    func isPointOnTitleBar(_ point: CGPoint) -> Bool {
        guard let mainDisplayHeight = mainDisplayHeightForAXCoordinates() else { return false }

        // 单次查询窗口信息，确保结果一致性
        let windowInfo = getWindowUnderMouse(point)

        // Chrome 特殊处理：演示模式全屏时，整个窗口区域都可以触发手势
        // 因为 Chrome 全屏时没有标准标题栏，但用户期望在任意位置捏合都能退出全屏
        if let window = windowInfo?.window, isChrome(window) {
            if isWindowVisuallyFullScreen(window) {
                return true
            }
        }

        // 全屏检测：鼠标在屏幕顶部边缘（用于触发全屏标题栏）
        // 使用鼠标所在屏幕的顶部，而非固定使用主屏幕高度
        let screenTopEdge: CGFloat = 6  // 顶部 6 像素触发区域
        let screenUnderPoint = NSScreen.screens.first { $0.frame.contains(point) }
        let topY = (screenUnderPoint?.frame.maxY ?? mainDisplayHeight) - screenTopEdge
        if point.y >= topY {
            if let window = windowInfo?.window {
                if isWindowFullScreen(window) {
                    return true
                }
            }
        }

        // 普通窗口标题栏检测
        guard let frame = windowInfo?.frame else {
            return false
        }

        let screenPoint = cocoaToAX(point, mainDisplayHeight: mainDisplayHeight)

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

        guard let mainDisplayHeight = mainDisplayHeightForAXCoordinates() else {
            return false
        }

        // 将 AX 坐标系（左上角原点）转换为 Cocoa 坐标系（左下角原点）
        let windowFrameCocoa = axToCocoa(windowFrame, mainDisplayHeight: mainDisplayHeight)

        // 选取与窗口交集面积最大的屏幕（比 center-contains 更稳健，避免边缘漂移误判）
        let bestScreen = NSScreen.screens.max { intersectionArea(windowFrameCocoa, $0.frame) < intersectionArea(windowFrameCocoa, $1.frame) }
        guard let screen = bestScreen ?? NSScreen.main else {
            return false
        }

        let screenFrame = screen.frame

        // Chrome 演示模式全屏特征：窗口覆盖整个屏幕（包括菜单栏）
        // 使用比例容差 + 最小容差，兼容不同显示器/缩放/刘海安全区
        // 同时匹配 screenFrame 和 safeAreaFrame，避免刘海屏误判
        let minTolerance: CGFloat = 10.0
        let relativeTolerance: CGFloat = 0.01

        // 计算 safe area frame（去掉刘海/菜单栏等系统区域）
        let safeInsets = screen.safeAreaInsets
        let safeAreaFrame = CGRect(
            x: screenFrame.origin.x + safeInsets.left,
            y: screenFrame.origin.y + safeInsets.bottom,
            width: max(0, screenFrame.width - safeInsets.left - safeInsets.right),
            height: max(0, screenFrame.height - safeInsets.top - safeInsets.bottom)
        )

        /// 评估窗口与参考 frame 的匹配程度
        func evalMatch(_ reference: CGRect, heightTolerance: CGFloat? = nil) -> (matches: Bool, dx: CGFloat, dy: CGFloat, dw: CGFloat, dh: CGFloat, tolX: CGFloat, tolY: CGFloat) {
            let tolX = max(minTolerance, reference.width * relativeTolerance)
            let tolY = heightTolerance ?? max(minTolerance, reference.height * relativeTolerance)
            let dx = abs(windowFrameCocoa.origin.x - reference.origin.x)
            let dy = abs(windowFrameCocoa.origin.y - reference.origin.y)
            let dw = abs(windowFrameCocoa.width - reference.width)
            let dh = abs(windowFrameCocoa.height - reference.height)
            let matches = dx <= tolX && dy <= tolY && dw <= tolX && dh <= tolY
            return (matches, dx, dy, dw, dh, tolX, tolY)
        }

        let screenEval = evalMatch(screenFrame)
        let safeEval = evalMatch(safeAreaFrame)

        // 严格匹配：任一匹配即视为全屏（兼容刘海屏和非刘海屏）
        var isVisuallyFullScreen = screenEval.matches || safeEval.matches

        // Chrome 宽松匹配：宽度完全匹配，高度允许最多 15% 差异（地址栏/标签栏）
        // 条件：x 坐标匹配、宽度匹配、高度 >= 85% 屏幕高度
        if !isVisuallyFullScreen && isChrome(window) {
            let chromeHeightTolerance = screenFrame.height * 0.15  // 允许 15% 高度差异
            let chromeEval = evalMatch(screenFrame, heightTolerance: chromeHeightTolerance)
            if chromeEval.dx <= chromeEval.tolX && chromeEval.dw <= chromeEval.tolX && chromeEval.dh <= chromeHeightTolerance {
                isVisuallyFullScreen = true
            }
        }

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

    /// 获取主显示器（CGMainDisplayID 对应的 NSScreen）的高度（点），用于 Cocoa<->AX/CG 坐标翻转。
    /// AX/CGWindowList 坐标系以"主显示器"左上角为原点，y 向下；
    /// Cocoa/NSScreen 坐标系以左下角为原点，y 向上。
    private func mainDisplayHeightForAXCoordinates() -> CGFloat? {
        let mainDisplayID = CGMainDisplayID()
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            if CGDirectDisplayID(screenNumber.uint32Value) == mainDisplayID {
                return screen.frame.height
            }
        }
        // Fallback: 主显示器未找到时，使用 main 或 first
        return NSScreen.main?.frame.height ?? NSScreen.screens.first?.frame.height
    }

    /// Cocoa 坐标转 AX 坐标（左下原点 -> 左上原点）
    private func cocoaToAX(_ point: CGPoint, mainDisplayHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: mainDisplayHeight - point.y)
    }

    /// AX 矩形转 Cocoa 矩形（左上原点 -> 左下原点）
    private func axToCocoa(_ rect: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: mainDisplayHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// 当 CGWindowID 无法精确匹配到 AXWindowID 时，使用几何/命中测试选择最可能的顶层 AXWindow。
    /// Chrome 演示模式全屏等场景下，"鼠标下的 CGWindow"可能没有对应的 AXWindow，
    /// 此时通过窗口 frame 和鼠标位置的几何关系来归并到正确的 AXWindow。
    private func bestMatchingAXWindow(
        _ windows: [AXUIElement],
        cgWindowFrame: CGRect,
        screenPointAX: CGPoint
    ) -> AXUIElement? {
        // 获取所有有效窗口的 frame
        let frames: [(window: AXUIElement, frame: CGRect)] = windows.compactMap { w in
            guard let f = getWindowFrame(w) else { return nil }
            guard f.width >= minWindowSize && f.height >= minWindowSize else { return nil }
            return (w, f)
        }
        guard !frames.isEmpty else { return nil }

        // 优先选择包含鼠标点的窗口
        let containing = frames.filter { $0.frame.contains(screenPointAX) }
        let pool = containing.isEmpty ? frames : containing

        // 在候选池中，选择与 CGWindow frame 交集面积最大的
        let best = pool.max { a, b in
            let ia = intersectionArea(a.frame, cgWindowFrame)
            let ib = intersectionArea(b.frame, cgWindowFrame)
            if ia != ib { return ia < ib }

            // 交集相同时，倾向面积更接近 CGWindow bounds 的 AX window
            let areaA = a.frame.width * a.frame.height
            let areaB = b.frame.width * b.frame.height
            let areaCG = cgWindowFrame.width * cgWindowFrame.height
            let da = abs(areaA - areaCG)
            let db = abs(areaB - areaCG)
            return da > db
        }

        // 安全保护：只有当交集面积 > 0 或鼠标点在窗口内时才返回匹配结果
        // 避免在所有候选窗口都不匹配时返回错误窗口
        guard let result = best else { return nil }
        let hasValidMatch = result.frame.contains(screenPointAX) || intersectionArea(result.frame, cgWindowFrame) > 0
        return hasValidMatch ? result.window : nil
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
    func getAppBundleIdentifier(for window: AXUIElement) -> String? {
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
        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
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
            return toggleFullScreenViaKeyboard()
        }

        // 方法1: 直接设置 AXFullScreen 属性（最可靠）
        var fullScreenValue: AnyObject?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenValue) == .success,
           let isFullScreen = fullScreenValue as? Bool {
            let newValue = !isFullScreen as CFBoolean
            if AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, newValue) == .success {
                return true
            }
        }

        // 方法2: 点击全屏按钮
        var fullScreenButton: AnyObject?
        if AXUIElementCopyAttributeValue(window, kAXFullScreenButtonAttribute as CFString, &fullScreenButton) == .success {
            if AXUIElementPerformAction(fullScreenButton as! AXUIElement, kAXPressAction as CFString) == .success {
                return true
            }
        }

        // 方法3: 回退到键盘快捷键（最后手段）
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x03, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x03, keyDown: false)
        
        keyDown?.flags = [.maskControl, .maskCommand]
        keyUp?.flags = [.maskControl, .maskCommand]
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        return true
    }
    
    /// 还原窗口（退出全屏或恢复到标准大小）
    /// - Note: Chrome 演示模式全屏不设置 AXFullScreen 属性，全屏检测不可靠，
    ///         因此对 Chrome 直接使用键盘快捷键切换，跳过全屏状态检测
    @discardableResult
    func restoreWindow(_ window: AXUIElement) -> Bool {
        // Chrome 兼容性：演示模式全屏检测不可靠，直接用键盘快捷键切换
        if isChrome(window) {
            return toggleFullScreenViaKeyboard()
        }

        // 其他应用：通过 AXFullScreen 属性判断是否全屏
        var fullScreenValue: AnyObject?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenValue) == .success,
           let isFullScreen = fullScreenValue as? Bool, isFullScreen {
            return toggleFullScreen(window)
        }

        return false
    }
}
