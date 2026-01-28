//
//  PinchGestureDetector.swift
//  SwishMini
//
//  基于 MultitouchSupport 私有框架的触控板手势检测器
//  支持：双指张开(全屏)、双指捏合(还原)、双指下滑(最小化)
//

import Cocoa

// MARK: - 手势类型
enum TitleBarGestureType {
    case pinchOpen      // 双指张开 -> 全屏
    case pinchClose     // 双指捲合 -> 还原
    case swipeDown      // 双指下滑 -> 最小化
    case swipeUp        // 双指上滑 -> 取消最小化
}

// 最小化窗口记录（用于上滑恢复）
struct MinimizedWindowRecord {
    let windowElement: AXUIElement      // 窗口引用
    let location: CGPoint               // 最小化时的鼠标位置
    let timestamp: Date                 // 时间戳
}

// MARK: - 检测器类

class PinchGestureDetector {
    static let shared = PinchGestureDetector()
    
    // 状态追踪
    private var isMonitoring = false
    private var isGestureActive = false
    private var previousDistance: Float = 0
    private var gestureStartDistance: Float = 0
    private var gestureStartTime: Date?
    private var didEnterCloseWindowHint = false  // 是否进入过"关闭窗口"提示状态

    // 下滑检测相关
    private var gestureStartY: Float = 0
    private var previousY: Float = 0

    // 非全屏上滑关闭窗口的持续时间阈值（秒）
    private let nonFullScreenSwipeUpCloseThreshold: TimeInterval = 1.0

    // 框架引用
    private var frameworkHandle: UnsafeMutableRawPointer?
    private var deviceList: [UnsafeMutableRawPointer] = []
    
    // 回调
    var onGestureDetected: ((TitleBarGestureType) -> Void)?
    var onPinchChanged: ((CGFloat) -> Void)?
    var onPinchEnded: ((CGFloat) -> Void)?

    /// 手势反馈回调 - 用于 HUD 显示
    var onGestureFeedback: ((GestureFeedback) -> Void)?
    
    // 手势阈值（增加死区，减少误触发）
    private let pinchOpenThreshold: Float = 1.5      // 张开阈值（从1.4提高）
    private let pinchCloseThreshold: Float = 0.5     // 捏合阈值（从0.6降低）
    private let swipeDownThreshold: Float = 0.18     // 下滑距离阈值（从0.15提高）
    private let swipeUpThreshold: Float = 0.15       // 上滑距离阈值（从0.12提高）
    
    // 主导手势判断阈值
    private let scaleDeviationThreshold: Float = 0.25  // scale变化超过25%才算有效捏合/张开
    private let yDeltaThreshold: Float = 0.10          // Y变化超过10%才算有效滑动
    
    // 最小化窗口记录（用于上滑恢复）
    private var lastMinimizedWindow: MinimizedWindowRecord?
    private let restoreProximityThreshold: CGFloat = 150  // 恢复位置容差（像素）
    
    private init() {}
    
    // MARK: - 启动监听
    
    func startMonitoring() {
        if isMonitoring { return }
        
        print("🔧 [PinchGestureDetector] 正在尝试加载 MultitouchSupport...")
        
        // 1. 加载框架
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            print("❌ [PinchGestureDetector] 无法 dlopen 加载 MultitouchSupport 框架")
            return
        }
        frameworkHandle = handle
        print("✅ [PinchGestureDetector] 框架加载成功")
        
        // 2. 解析函数符号
        let MTDeviceCreateListPtr = dlsym(handle, "MTDeviceCreateList")
        let MTRegisterContactFrameCallbackPtr = dlsym(handle, "MTRegisterContactFrameCallback")
        let MTDeviceStartPtr = dlsym(handle, "MTDeviceStart")
        
        if MTDeviceCreateListPtr == nil || MTRegisterContactFrameCallbackPtr == nil || MTDeviceStartPtr == nil {
            print("❌ [PinchGestureDetector] 无法解析必要的 MT 函数符号")
            return
        }
        
        // 3. 定义函数类型并转换
        typealias MTDeviceCreateListFunc = @convention(c) () -> CFArray?
        typealias MTRegisterCallbackFunc = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> Void
        typealias MTDeviceStartFunc = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
        
        let MTDeviceCreateList = unsafeBitCast(MTDeviceCreateListPtr, to: MTDeviceCreateListFunc.self)
        let MTRegisterContactFrameCallback = unsafeBitCast(MTRegisterContactFrameCallbackPtr, to: MTRegisterCallbackFunc.self)
        let MTDeviceStart = unsafeBitCast(MTDeviceStartPtr, to: MTDeviceStartFunc.self)
        
        // 4. 获取设备列表
        guard let devicesRef = MTDeviceCreateList() else {
             print("❌ [PinchGestureDetector] MTDeviceCreateList 返回 nil")
             return
        }
        
        let count = CFArrayGetCount(devicesRef)
        var devices: [UnsafeMutableRawPointer] = []
        print("✅ [PinchGestureDetector] 原始设备列表包含 \(count) 个项目")
        
        for i in 0..<count {
            if let ptr = CFArrayGetValueAtIndex(devicesRef, i) {
                let mutablePtr = UnsafeMutableRawPointer(mutating: ptr)
                devices.append(mutablePtr)
            }
        }
        
        print("✅ [PinchGestureDetector] 解析出 \(devices.count) 个触控设备")
        
        if devices.isEmpty {
            print("⚠️ [PinchGestureDetector] 没有找到触控板设备，无法监控")
            return
        }
        
        deviceList = devices
        
        // 5. 注册回调并启动
        // 使用 Bridging Header 中定义的 mtTouch 结构体
        typealias MTContactCallbackFunc = @convention(c) (
            UnsafeMutableRawPointer,          // device
            UnsafePointer<mtTouch>,           // 使用 Bridging Header 中的 mtTouch
            Int32,                            // nFingers
            Double,                           // timestamp
            Int32                             // frame
        ) -> Void
        
        typealias MTRegisterCallbackFuncTyped = @convention(c) (UnsafeMutableRawPointer, MTContactCallbackFunc) -> Void
        let MTRegisterContactFrameCallbackTyped = unsafeBitCast(MTRegisterContactFrameCallbackPtr, to: MTRegisterCallbackFuncTyped.self)
        
        for (index, device) in devices.enumerated() {
            print("🔧 [PinchGestureDetector] 正在启动设备 #\(index)...")
            MTRegisterContactFrameCallbackTyped(device, globalPinchCallback)
            MTDeviceStart(device, 0)
        }
        
        isMonitoring = true
        print("✅ [PinchGestureDetector] 监听已启动！触控板手势检测已就绪")
    }
    
    // MARK: - 停止监听
    
    func stopMonitoring() {
        guard isMonitoring, let handle = frameworkHandle else { return }
        
        if let stopPtr = dlsym(handle, "MTDeviceStop") {
            typealias MTDeviceStopFunc = @convention(c) (UnsafeMutableRawPointer) -> Void
            let MTDeviceStop = unsafeBitCast(stopPtr, to: MTDeviceStopFunc.self)
            
            for device in deviceList {
                MTDeviceStop(device)
            }
        }
        
        deviceList.removeAll()
        isMonitoring = false
        print("⏹️ [PinchGestureDetector] 监听已停止")
    }
    
    // MARK: - 核心处理逻辑

    /// 分类手势类型并计算进度
    private func classifyGesture(
        scale: CGFloat,
        yDelta: CGFloat,
        useActionThresholds: Bool,
        isWindowFullScreen: Bool = true,
        gestureDuration: TimeInterval = 0
    ) -> (candidate: GestureCandidate, progress: CGFloat) {
        let absY = abs(yDelta)
        let scaleDeviation = abs(scale - 1.0)

        // 实时反馈使用更低的阈值，便于更早显示 HUD
        let hintYThreshold: CGFloat = 0.02
        let hintScaleThreshold: CGFloat = 0.05

        let yDominantThreshold = useActionThresholds ? CGFloat(yDeltaThreshold) : hintYThreshold
        let scaleDominantThreshold = useActionThresholds ? CGFloat(scaleDeviationThreshold) : hintScaleThreshold

        // 主导手势判断逻辑
        let isSwipeDominant = absY > yDominantThreshold && absY > (scaleDeviation * 2.0)
        let isPinchDominant = scaleDeviation > scaleDominantThreshold && !isSwipeDominant

        if isSwipeDominant {
            if yDelta < 0 {
                let denom = max(CGFloat(swipeDownThreshold), 0.0001)
                return (.swipeDown, min(absY / denom, 1))
            } else {
                // 上滑：非全屏时显示"关闭窗口"提示（使用时间进度驱动 HUD 动画）
                if !isWindowFullScreen {
                    let holdProgress = min(gestureDuration / nonFullScreenSwipeUpCloseThreshold, 1)
                    return (.closeWindow, holdProgress)
                }
                let denom = max(CGFloat(swipeUpThreshold), 0.0001)
                return (.swipeUp, min(absY / denom, 1))
            }
        }

        if isPinchDominant {
            if scale >= 1 {
                let denom = max(CGFloat(pinchOpenThreshold) - 1.0, 0.0001)
                return (.pinchOpen, min((scale - 1.0) / denom, 1))
            } else {
                let denom = max(1.0 - CGFloat(pinchCloseThreshold), 0.0001)
                return (.pinchClose, min((1.0 - scale) / denom, 1))
            }
        }

        return (.none, 0)
    }

    /// 发送手势反馈事件
    private func emitFeedback(
        phase: GesturePhase,
        scale: CGFloat,
        yDelta: CGFloat,
        isInValidRegion: Bool,
        mouseLocation: CGPoint,
        gestureDuration: TimeInterval = 0,
        override: (candidate: GestureCandidate, progress: CGFloat)? = nil,
        useActionThresholds: Bool
    ) {
        let windowInfo = WindowManager.shared.getWindowUnderMouse(mouseLocation)
        let windowFrame = windowInfo?.frame
        let isWindowFullScreen = windowInfo.map { WindowManager.shared.isWindowFullScreen($0.window) } ?? false

        var classified: (candidate: GestureCandidate, progress: CGFloat)
        if let override = override {
            classified = override
        } else {
            classified = classifyGesture(
                scale: scale,
                yDelta: yDelta,
                useActionThresholds: useActionThresholds,
                isWindowFullScreen: isWindowFullScreen,
                gestureDuration: gestureDuration
            )
        }

        // 修正：如果有可恢复的最小化窗口且鼠标在恢复热点附近，
        // 上滑应优先显示为"取消最小化"，避免 HUD 错误地显示"关闭窗口"进度环
        if classified.candidate == .closeWindow, let record = lastMinimizedWindow {
            let dx = mouseLocation.x - record.location.x
            let dy = mouseLocation.y - record.location.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance <= restoreProximityThreshold {
                let absY = abs(yDelta)
                let denom = max(CGFloat(swipeUpThreshold), 0.0001)
                classified = (.swipeUp, min(absY / denom, 1))
            }
        }

        // 记录：一旦进入"关闭窗口"提示状态
        if (phase == .began || phase == .changed), classified.candidate == .closeWindow {
            didEnterCloseWindowHint = true
        }

        onGestureFeedback?(
            GestureFeedback(
                phase: phase,
                candidate: classified.candidate,
                progress: classified.progress,
                scale: scale,
                yDelta: yDelta,
                gestureDuration: gestureDuration,
                isInValidRegion: isInValidRegion,
                mouseLocation: mouseLocation,
                windowFrame: windowFrame
            )
        )
    }

    func handleTouchCallback(data: UnsafePointer<mtTouch>?, count: Int32) {
        // 确保数据有效
        guard let touches = data, count > 0 else {
            if isGestureActive {
                endGesture()
            }
            return
        }
        
        let mouseLocation = NSEvent.mouseLocation
        
        // 特殊处理：如果有最小化窗口记录，且鼠标在记录位置附近，允许上滑恢复
        // 这样即使原位置被其他窗口占据，也能触发恢复
        let isNearMinimizedLocation: Bool
        if let record = lastMinimizedWindow {
            let dx = mouseLocation.x - record.location.x
            let dy = mouseLocation.y - record.location.y
            let distance = sqrt(dx*dx + dy*dy)
            isNearMinimizedLocation = distance <= restoreProximityThreshold
        } else {
            isNearMinimizedLocation = false
        }
        
        // 检查是否在标题栏区域
        let isOnTitleBar = WindowManager.shared.isPointOnTitleBar(mouseLocation)
        let isInValidRegionForFeedback = isOnTitleBar || isNearMinimizedLocation
        
        // 如果不在标题栏，且也不在最小化恢复位置附近，则忽略手势
        if !isOnTitleBar && !isNearMinimizedLocation {
            if isGestureActive { endGesture() }
            return
        }
        
        // 筛选有效手指（state > 0 表示手指在触控板上）
        var activePoints: [(x: Float, y: Float)] = []
        
        for i in 0..<Int(count) {
            let t = touches[i]
            // state: 1=开始, 2=移动中, 等。只要 > 0 就是有效触摸
            // 使用 normalized 的 position
            let x = t.normalized.position.x
            let y = t.normalized.position.y
            
            if t.state > 0 && x >= 0 && x <= 1 && y >= 0 && y <= 1 {
                activePoints.append((x, y))
            }
        }
        
        // 必须至少两个手指
        guard activePoints.count >= 2 else {
            if isGestureActive { endGesture() }
            return
        }
        
        // 取前两个有效点
        let p1 = activePoints[0]
        let p2 = activePoints[1]
        
        // 计算两指距离（用于捏合检测）
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let distance = sqrt(dx*dx + dy*dy)
        
        // 计算两指的平均 Y 坐标（用于下滑检测）
        let avgY = (p1.y + p2.y) / 2.0
        
        // 如果是首次识别
        if !isGestureActive {
            isGestureActive = true
            gestureStartDistance = distance
            previousDistance = distance
            gestureStartY = avgY
            previousY = avgY
            gestureStartTime = Date()
            didEnterCloseWindowHint = false
            print("✋ [Gesture] 手势开始 - 初始距离: \(String(format: "%.4f", distance)), Y: \(String(format: "%.3f", avgY))")

            // 发送手势开始反馈
            emitFeedback(
                phase: .began,
                scale: 1.0,
                yDelta: 0.0,
                isInValidRegion: isInValidRegionForFeedback,
                mouseLocation: mouseLocation,
                gestureDuration: 0,
                useActionThresholds: false
            )
        } else {
            // 计算变化
            let distanceDelta = distance - previousDistance
            let yDelta = avgY - gestureStartY  // 正值=向上，负值=向下
            let currentScale = gestureStartDistance > 0 ? distance / gestureStartDistance : 1.0
            
            // 只有变化足够大才打印（防抖动）
            if abs(distanceDelta) > 0.002 || abs(avgY - previousY) > 0.01 {
                if distanceDelta > 0.005 {
                    print("👐 [Gesture] 张开中 scale=\(String(format: "%.2f", currentScale))")
                } else if distanceDelta < -0.005 {
                    print("🤏 [Gesture] 捏合中 scale=\(String(format: "%.2f", currentScale))")
                }
                
                if yDelta < -0.02 {
                    print("👇 [Gesture] 下滑中 deltaY=\(String(format: "%.3f", yDelta))")
                } else if yDelta > 0.02 {
                    print("👆 [Gesture] 上滑中 deltaY=\(String(format: "%.3f", yDelta))")
                }
                
                onPinchChanged?(CGFloat(currentScale))
            }

            // 发送手势进行中反馈
            emitFeedback(
                phase: .changed,
                scale: CGFloat(currentScale),
                yDelta: CGFloat(yDelta),
                isInValidRegion: isInValidRegionForFeedback,
                mouseLocation: mouseLocation,
                gestureDuration: gestureStartTime.map { Date().timeIntervalSince($0) } ?? 0,
                useActionThresholds: false
            )

            previousDistance = distance
            previousY = avgY
        }
    }
    
    private func endGesture() {
        guard isGestureActive else { return }

        let finalScale = gestureStartDistance > 0 ? previousDistance / gestureStartDistance : 1.0
        let totalYDelta = previousY - gestureStartY  // 正值=向上，负值=向下
        let gestureDuration = gestureStartTime.map { Date().timeIntervalSince($0) } ?? 0

        print("✅ [Gesture] 手势结束 - scale: \(String(format: "%.2f", finalScale)), yDelta: \(String(format: "%.3f", totalYDelta)), duration: \(String(format: "%.2f", gestureDuration))s")

        // === 主导手势类型判断 ===
        // 计算各维度的绝对变化量
        let absYDelta = abs(totalYDelta)
        let scaleDeviation = abs(finalScale - 1.0)  // 偏离1.0的程度
        
        // 判断主导手势类型：
        // 1. 滑动主导：Y轴变化明显 且 是scale变化的2倍以上
        // 2. 捏合主导：scale变化明显 且 不是滑动主导
        let isSwipeGestureDominant = absYDelta > yDeltaThreshold && absYDelta > (scaleDeviation * 2)
        let isPinchGestureDominant = scaleDeviation > scaleDeviationThreshold && !isSwipeGestureDominant
        
        print("📊 [Analysis] Y变化: \(String(format: "%.3f", absYDelta)), Scale偏离: \(String(format: "%.3f", scaleDeviation))")
        print("📊 [Analysis] 滑动主导: \(isSwipeGestureDominant), 捏合主导: \(isPinchGestureDominant)")

        // === 发送手势结束反馈（处理"已取消"场景）===
        let mouseLocation = NSEvent.mouseLocation
        let windowInfo = WindowManager.shared.getWindowUnderMouse(mouseLocation)
        let isWindowFullScreen = windowInfo.map { WindowManager.shared.isWindowFullScreen($0.window) } ?? false
        let hasValidWindow = windowInfo != nil

        // 预判本次手势会执行哪种动作（需要有效窗口才能真正执行）
        let willSwipeDown = hasValidWindow && isSwipeGestureDominant && totalYDelta < -swipeDownThreshold
        // swipeUp 需要有记录的最小化窗口，且在原位置附近才能恢复
        let willSwipeUp: Bool = {
            guard isSwipeGestureDominant && totalYDelta > swipeUpThreshold,
                  let record = lastMinimizedWindow else { return false }
            let dx = mouseLocation.x - record.location.x
            let dy = mouseLocation.y - record.location.y
            let distance = sqrt(dx*dx + dy*dy)
            return distance <= restoreProximityThreshold
        }()
        let willPinchOpen = hasValidWindow && isPinchGestureDominant && finalScale > pinchOpenThreshold
        let willPinchClose = hasValidWindow && isPinchGestureDominant && finalScale < pinchCloseThreshold

        // 预判是否会执行关闭窗口操作（非全屏 + 上滑主导 + 达到阈值 + 持续时间足够 + 有效窗口）
        let willCloseWindow = hasValidWindow &&
                              !isWindowFullScreen &&
                              isSwipeGestureDominant &&
                              totalYDelta > swipeUpThreshold &&
                              gestureDuration >= nonFullScreenSwipeUpCloseThreshold &&
                              !willSwipeUp  // 若命中"恢复最小化"则不应关闭窗口

        // 预判是否会执行全屏还原操作（全屏 + 捏合）
        let willRestoreFromFullScreen = hasValidWindow && isWindowFullScreen && willPinchClose

        // 是否会执行任何有效动作（排除关闭窗口本身）
        // 注意："非全屏 + pinchClose 且持续时间不足"不执行任何操作，不算"其他动作"
        let willExecuteOtherAction = willSwipeDown || willSwipeUp || willPinchOpen || willRestoreFromFullScreen

        // 只有满足以下全部条件时才发送"已取消"反馈：
        // 1. 进入过"关闭窗口"提示
        // 2. 不会执行关闭窗口
        // 3. 不会执行其他任何动作（避免覆盖正常动作的结束反馈）
        if didEnterCloseWindowHint && !willCloseWindow && !willExecuteOtherAction {
            print("🚫 [Feedback] 关闭窗口操作已取消")
            emitFeedback(
                phase: .ended,
                scale: CGFloat(finalScale),
                yDelta: CGFloat(totalYDelta),
                isInValidRegion: true,
                mouseLocation: mouseLocation,
                gestureDuration: gestureDuration,
                override: (.cancelled, 1.0),
                useActionThresholds: true
            )
        } else {
            emitFeedback(
                phase: .ended,
                scale: CGFloat(finalScale),
                yDelta: CGFloat(totalYDelta),
                isInValidRegion: true,
                mouseLocation: mouseLocation,
                gestureDuration: gestureDuration,
                useActionThresholds: true
            )
        }

        // === 根据主导类型执行动作 ===
        if isSwipeGestureDominant {
            // 滑动手势优先
            if totalYDelta < -swipeDownThreshold {
                print("🎯 [Action] 双指下滑 -> 最小化窗口")
                onGestureDetected?(.swipeDown)
                executeWindowAction(.swipeDown, gestureDuration: gestureDuration)
            } else if totalYDelta > swipeUpThreshold {
                print("🎯 [Action] 双指上滑 -> 检查是否可恢复窗口")
                onGestureDetected?(.swipeUp)
                executeWindowAction(.swipeUp, gestureDuration: gestureDuration)
            }
        } else if isPinchGestureDominant {
            // 捏合手势
            if finalScale > pinchOpenThreshold {
                print("🎯 [Action] 双指张开 -> 全屏窗口")
                onGestureDetected?(.pinchOpen)
                executeWindowAction(.pinchOpen, gestureDuration: gestureDuration)
            } else if finalScale < pinchCloseThreshold {
                print("🎯 [Action] 双指捏合")
                onGestureDetected?(.pinchClose)
                executeWindowAction(.pinchClose, gestureDuration: gestureDuration)
            }
        } else {
            print("⚠️ [Analysis] 手势幅度不足，不触发动作")
        }

        onPinchEnded?(CGFloat(finalScale))

        // 重置状态
        isGestureActive = false
        previousDistance = 0
        gestureStartDistance = 0
        gestureStartY = 0
        previousY = 0
        gestureStartTime = nil
        didEnterCloseWindowHint = false
    }
    
    // MARK: - 执行窗口操作

    private func executeWindowAction(_ gesture: TitleBarGestureType, gestureDuration: TimeInterval = 0) {
        let mouseLocation = NSEvent.mouseLocation

        switch gesture {
        case .swipeUp:
            // 双指上滑：
            // 1. 优先恢复最小化窗口（如果有记录且在原位置附近）
            // 2. 否则，非全屏 + 持续 >= 1 秒：关闭窗口
            // 3. 全屏时：无动作（或后续扩展为其他功能）
            if let record = lastMinimizedWindow {
                // 检查是否在原来的位置附近
                let dx = mouseLocation.x - record.location.x
                let dy = mouseLocation.y - record.location.y
                let distance = sqrt(dx*dx + dy*dy)

                if distance <= restoreProximityThreshold {
                    print("✅ [Action] 在原位置附近上滑，恢复窗口 (距离: \(String(format: "%.0f", distance))px)")
                    WindowManager.shared.unminimizeWindow(record.windowElement)
                    lastMinimizedWindow = nil  // 清除记录
                    return
                }
                print("⚠️ [Action] 上滑位置距离历史位置过远 (\(String(format: "%.0f", distance))px > \(restoreProximityThreshold)px)")
            }

            // 未触发恢复（可能没有记录，或不在恢复热点），检查是否应该关闭窗口
            guard let (window, _) = WindowManager.shared.getWindowUnderMouse(mouseLocation) else {
                print("⚠️ [Action] 无法获取当前窗口")
                return
            }

            if !WindowManager.shared.isWindowFullScreen(window) && gestureDuration >= nonFullScreenSwipeUpCloseThreshold {
                print("❌ [Action] 非全屏 + 长上滑(\(String(format: "%.1f", gestureDuration))s >= \(nonFullScreenSwipeUpCloseThreshold)s)，关闭窗口")
                WindowManager.shared.closeWindow(window)
            } else {
                print("ℹ️ [Action] 上滑但不满足关闭条件")
            }
            return

        default:
            break
        }

        // 其他手势需要获取当前窗口
        guard let (window, _) = WindowManager.shared.getWindowUnderMouse(mouseLocation) else {
            print("⚠️ [Action] 无法获取当前窗口")
            return
        }

        switch gesture {
        case .pinchOpen:
            // 双指张开 -> 全屏
            WindowManager.shared.toggleFullScreen(window)

        case .pinchClose:
            // 双指捏合：
            // - 全屏状态：退出全屏
            // - 非全屏：无动作
            if WindowManager.shared.isWindowFullScreen(window) {
                print("🔄 [Action] 全屏状态，退出全屏")
                WindowManager.shared.restoreWindow(window)
            } else {
                print("ℹ️ [Action] 非全屏状态，捏合无动作")
            }

        case .swipeDown:
            // 双指下滑 -> 最小化，并记录位置
            lastMinimizedWindow = MinimizedWindowRecord(
                windowElement: window,
                location: mouseLocation,
                timestamp: Date()
            )
            print("📌 [Action] 记录最小化位置: (\(String(format: "%.0f", mouseLocation.x)), \(String(format: "%.0f", mouseLocation.y)))")
            WindowManager.shared.minimizeWindow(window)

        case .swipeUp:
            break  // 已在上面处理
        }
    }
}

// MARK: - 全局 C 回调

// 顶级 C 函数 - 使用 Bridging Header 中定义的 mtTouch 结构体
func globalPinchCallback(
    _ device: UnsafeMutableRawPointer,
    _ data: UnsafePointer<mtTouch>,
    _ nFingers: Int32,
    _ timestamp: Double,
    _ frame: Int32
) {
    PinchGestureDetector.shared.handleTouchCallback(data: data, count: nFingers)
}
