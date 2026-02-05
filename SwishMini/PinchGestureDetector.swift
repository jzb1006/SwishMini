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

    // ID 锁定机制：手势进行中只追踪锁定的触点对
    private var lockedIdentifiers: (Int, Int)?

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

    // 手势启动时的触点距离范围（归一化坐标）
    private let maxStartDistanceNormalized: Float = 0.85  // 距离过大则不启动手势
    private let minStartDistanceNormalized: Float = 0.05  // 距离过小则不启动手势

    // 最小化窗口记录（用于上滑恢复）
    private var lastMinimizedWindow: MinimizedWindowRecord?
    private let restoreProximityThreshold: CGFloat = 150  // 恢复位置容差（像素）

    /// 计算当前鼠标位置与最小化记录位置的距离
    /// - Parameter point: 当前鼠标位置
    /// - Returns: 距离（像素），若无最小化记录则返回 nil
    private func distanceFromLastMinimizedLocation(_ point: CGPoint) -> CGFloat? {
        guard let record = lastMinimizedWindow else { return nil }
        let dx = point.x - record.location.x
        let dy = point.y - record.location.y
        return sqrt(dx * dx + dy * dy)
    }

    /// 从触点列表中选择"距离在有效范围内"的最近一对
    /// - Parameters:
    ///   - points: 触点列表（包含 id, x, y）
    ///   - minDistance: 最小距离（归一化坐标）
    ///   - maxDistance: 最大距离（归一化坐标）
    /// - Returns: 最近的有效触点对；若无有效组合（或点数 < 2）则返回 nil
    private func findClosestValidPair(
        from points: [(id: Int, x: Float, y: Float)],
        minDistance: Float,
        maxDistance: Float
    ) -> ((id: Int, x: Float, y: Float), (id: Int, x: Float, y: Float))? {
        guard points.count >= 2 else { return nil }

        // 预计算平方值，避免循环内重复计算
        let minDistanceSquared = minDistance * minDistance
        let maxDistanceSquared = maxDistance * maxDistance

        // 遍历所有组合，找出"距离在有效范围内"的最近一对
        var closestPair: ((id: Int, x: Float, y: Float), (id: Int, x: Float, y: Float))?
        var minValidDistanceSquared: Float = .greatestFiniteMagnitude

        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                let dx = points[j].x - points[i].x
                let dy = points[j].y - points[i].y
                let distSquared = dx * dx + dy * dy

                // 过滤距离不在有效范围内的组合
                guard distSquared >= minDistanceSquared && distSquared <= maxDistanceSquared else {
                    continue
                }

                if distSquared < minValidDistanceSquared {
                    minValidDistanceSquared = distSquared
                    closestPair = (points[i], points[j])
                }
            }
        }

        return closestPair
    }

    private init() {}
    
    // MARK: - 启动监听
    
    func startMonitoring() {
        if isMonitoring { return }

        // 1. 加载框架
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
            return
        }
        frameworkHandle = handle

        // 2. 解析函数符号
        let MTDeviceCreateListPtr = dlsym(handle, "MTDeviceCreateList")
        let MTRegisterContactFrameCallbackPtr = dlsym(handle, "MTRegisterContactFrameCallback")
        let MTDeviceStartPtr = dlsym(handle, "MTDeviceStart")

        if MTDeviceCreateListPtr == nil || MTRegisterContactFrameCallbackPtr == nil || MTDeviceStartPtr == nil {
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
             return
        }

        let count = CFArrayGetCount(devicesRef)
        var devices: [UnsafeMutableRawPointer] = []

        for i in 0..<count {
            if let ptr = CFArrayGetValueAtIndex(devicesRef, i) {
                let mutablePtr = UnsafeMutableRawPointer(mutating: ptr)
                devices.append(mutablePtr)
            }
        }

        if devices.isEmpty {
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

        for device in devices {
            MTRegisterContactFrameCallbackTyped(device, globalPinchCallback)
            MTDeviceStart(device, 0)
        }

        isMonitoring = true
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
        // 且手势持续时间未达到关闭阈值，则上滑应显示为"取消最小化"
        // 注意：持续时间 >= 1秒时，关闭窗口优先于恢复热点
        if classified.candidate == .closeWindow,
           gestureDuration < nonFullScreenSwipeUpCloseThreshold,
           let distance = distanceFromLastMinimizedLocation(mouseLocation),
           distance <= restoreProximityThreshold {
            let absY = abs(yDelta)
            let denom = max(CGFloat(swipeUpThreshold), 0.0001)
            classified = (.swipeUp, min(absY / denom, 1))
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
        if let distance = distanceFromLastMinimizedLocation(mouseLocation) {
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
        var activePoints: [(id: Int, x: Float, y: Float)] = []

        for i in 0..<Int(count) {
            let t = touches[i]
            // state: 1=开始, 2=移动中, 等。只要 > 0 就是有效触摸
            // 使用 normalized 的 position
            let x = t.normalized.position.x
            let y = t.normalized.position.y

            if t.state > 0 && x >= 0 && x <= 1 && y >= 0 && y <= 1 {
                activePoints.append((id: Int(t.identifier), x: x, y: y))
            }
        }
        
        // 必须至少两个手指
        guard activePoints.count >= 2 else {
            if isGestureActive { endGesture() }
            return
        }

        // 选择要追踪的触点对
        let p1: (id: Int, x: Float, y: Float)
        let p2: (id: Int, x: Float, y: Float)

        if let locked = lockedIdentifiers {
            // 手势进行中：追踪已锁定的触点 ID
            guard let lockedP1 = activePoints.first(where: { $0.id == locked.0 }),
                  let lockedP2 = activePoints.first(where: { $0.id == locked.1 }) else {
                // 锁定的触点消失，结束手势
                endGesture()
                return
            }
            p1 = lockedP1
            p2 = lockedP2
        } else {
            // 新手势：选择距离在有效范围内的最近一对触点
            guard let pair = findClosestValidPair(
                from: activePoints,
                minDistance: minStartDistanceNormalized,
                maxDistance: maxStartDistanceNormalized
            ) else {
                if isGestureActive { endGesture() }
                return
            }
            p1 = pair.0
            p2 = pair.1
        }

        // 计算两指距离（用于捏合检测）
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let distance = sqrt(dx*dx + dy*dy)
        
        // 计算两指的平均 Y 坐标（用于下滑检测）
        let avgY = (p1.y + p2.y) / 2.0
        
        // 如果是首次识别
        if !isGestureActive {
            // 距离范围已在 findClosestValidPair 中过滤，此处无需重复检查

            isGestureActive = true
            lockedIdentifiers = (p1.id, p2.id)  // 锁定触点对 ID
            gestureStartDistance = distance
            previousDistance = distance
            gestureStartY = avgY
            previousY = avgY
            gestureStartTime = Date()
            didEnterCloseWindowHint = false

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
            
            // 只有变化足够大才触发回调（防抖动）
            if abs(distanceDelta) > 0.002 || abs(avgY - previousY) > 0.01 {
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

        // === 主导手势类型判断 ===
        // 计算各维度的绝对变化量
        let absYDelta = abs(totalYDelta)
        let scaleDeviation = abs(finalScale - 1.0)  // 偏离1.0的程度

        // 判断主导手势类型：
        // 1. 滑动主导：Y轴变化明显 且 是scale变化的2倍以上
        // 2. 捏合主导：scale变化明显 且 不是滑动主导
        let isSwipeGestureDominant = absYDelta > yDeltaThreshold && absYDelta > (scaleDeviation * 2)
        let isPinchGestureDominant = scaleDeviation > scaleDeviationThreshold && !isSwipeGestureDominant

        // === 发送手势结束反馈（处理"已取消"场景）===
        let mouseLocation = NSEvent.mouseLocation
        let windowInfo = WindowManager.shared.getWindowUnderMouse(mouseLocation)
        let isWindowFullScreen = windowInfo.map { WindowManager.shared.isWindowFullScreen($0.window) } ?? false
        let hasValidWindow = windowInfo != nil

        // 预判本次手势会执行哪种动作（需要有效窗口才能真正执行）
        let willSwipeDown = hasValidWindow && isSwipeGestureDominant && totalYDelta < -swipeDownThreshold
        // swipeUp 需要有记录的最小化窗口，且在原位置附近才能恢复
        // 注意：非全屏 + 持续 >= 1秒时，关闭窗口优先于恢复热点，此时不算 willSwipeUp
        let willSwipeUp: Bool = {
            guard isSwipeGestureDominant,
                  totalYDelta > swipeUpThreshold,
                  let distance = distanceFromLastMinimizedLocation(mouseLocation),
                  distance <= restoreProximityThreshold else { return false }

            // 非全屏 + 持续 >= 1秒时，关闭窗口优先于恢复热点
            if hasValidWindow, !isWindowFullScreen, gestureDuration >= nonFullScreenSwipeUpCloseThreshold {
                return false
            }
            return true
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
                onGestureDetected?(.swipeDown)
                executeWindowAction(.swipeDown, gestureDuration: gestureDuration)
            } else if totalYDelta > swipeUpThreshold {
                onGestureDetected?(.swipeUp)
                executeWindowAction(.swipeUp, gestureDuration: gestureDuration)
            }
        } else if isPinchGestureDominant {
            // 捏合手势
            if finalScale > pinchOpenThreshold {
                onGestureDetected?(.pinchOpen)
                executeWindowAction(.pinchOpen, gestureDuration: gestureDuration)
            } else if finalScale < pinchCloseThreshold {
                onGestureDetected?(.pinchClose)
                executeWindowAction(.pinchClose, gestureDuration: gestureDuration)
            }
        }

        onPinchEnded?(CGFloat(finalScale))

        // 重置状态
        isGestureActive = false
        lockedIdentifiers = nil  // 清除 ID 锁定
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
            // 双指上滑优先级规则（解决两窗口场景下的冲突）：
            // 1. 非全屏 + 持续 >= 1秒：关闭当前窗口（优先于恢复热点）
            // 2. 否则，命中恢复热点：恢复最近一次最小化的窗口
            // 3. 全屏时：无动作

            // 优先检查：是否满足关闭窗口条件
            if gestureDuration >= nonFullScreenSwipeUpCloseThreshold,
               let (window, _) = WindowManager.shared.getWindowUnderMouse(mouseLocation),
               !WindowManager.shared.isWindowFullScreen(window) {
                WindowManager.shared.closeWindow(window)
                return
            }

            // 其次检查：是否在恢复热点内
            if let distance = distanceFromLastMinimizedLocation(mouseLocation),
               distance <= restoreProximityThreshold,
               let record = lastMinimizedWindow {
                WindowManager.shared.unminimizeWindow(record.windowElement)
                lastMinimizedWindow = nil  // 清除记录
                return
            }

            return

        default:
            break
        }

        // 其他手势需要获取当前窗口
        guard let (window, _) = WindowManager.shared.getWindowUnderMouse(mouseLocation) else {
            return
        }

        switch gesture {
        case .pinchOpen:
            // 双指张开 -> 全屏
            WindowManager.shared.toggleFullScreen(window)

        case .pinchClose:
            // 双指捏合：
            // - Chrome：直接发送键盘快捷键（演示模式全屏检测不可靠）
            // - 其他应用全屏状态：退出全屏
            // - 非全屏：无动作
            let bundleId = WindowManager.shared.getAppBundleIdentifier(for: window)
            let isChromeWindow = bundleId == "com.google.Chrome" || bundleId == "com.google.Chrome.canary"

            if isChromeWindow {
                // Chrome 特殊处理：直接调用 restoreWindow，不检测全屏状态
                WindowManager.shared.restoreWindow(window)
            } else {
                let isFullScreen = WindowManager.shared.isWindowFullScreen(window)
                if isFullScreen {
                    WindowManager.shared.restoreWindow(window)
                }
            }

        case .swipeDown:
            // 双指下滑 -> 最小化，并记录位置
            lastMinimizedWindow = MinimizedWindowRecord(
                windowElement: window,
                location: mouseLocation,
                timestamp: Date()
            )
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
