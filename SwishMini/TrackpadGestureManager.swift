//
//  TrackpadGestureManager.swift
//  SwishMini
//
//  触控板手势管理器
//

import Cocoa

// MARK: - 监控重启原因

/// 触发监控重启的原因枚举
enum MonitoringRestartReason: CustomStringConvertible {
    /// 屏幕配置变化（热插拔、分辨率调整）
    case screenConfigurationChanged
    /// 从睡眠中唤醒
    case systemWakeUp
    /// 用户手动请求
    case userRequested

    var description: String {
        switch self {
        case .screenConfigurationChanged: return "屏幕配置变化"
        case .systemWakeUp: return "系统唤醒"
        case .userRequested: return "用户请求"
        }
    }
}

// MARK: - 手势管理器

class TrackpadGestureManager {
    static let shared = TrackpadGestureManager()

    /// HUD 窗口控制器
    private let gestureHUD = GestureHUDWindowController()

    /// 重启请求的 debounce 工作项
    private var restartWorkItem: DispatchWorkItem?

    /// 重启 debounce 延迟（秒）
    private let restartDebounceDelay: TimeInterval = 0.3

    private init() {}

    func startMonitoring() {
        // 设置手势反馈回调 -> HUD 更新
        // Note: 回调已在主线程调用（由 PinchGestureDetector.globalPinchCallback 通过
        // DispatchQueue.main.async 保证），无需额外调度
        PinchGestureDetector.shared.onGestureFeedback = { [weak self] feedback in
            assert(Thread.isMainThread, "onGestureFeedback must be called on main thread")
            self?.gestureHUD.update(feedback: feedback)
        }

        // 启动捏合手势检测（MultitouchSupport）
        PinchGestureDetector.shared.startMonitoring()
    }

    func stopMonitoring() {
        // 取消待处理的重启请求
        restartWorkItem?.cancel()
        restartWorkItem = nil

        // 清理 HUD 回调
        PinchGestureDetector.shared.onGestureFeedback = nil

        // 停止 HUD 控制器
        Task { @MainActor in
            gestureHUD.stop()
        }

        // 停止捏合手势检测器
        PinchGestureDetector.shared.stopMonitoring()
    }

    // MARK: - 重启机制

    /// 请求重启监控（带 debounce）
    /// - Parameter reason: 重启原因，用于日志记录
    /// - Note: 多次快速调用会合并为一次重启，使用 debounce 防抖
    func requestRestartMonitoring(reason: MonitoringRestartReason) {
        // 取消之前的待处理请求
        restartWorkItem?.cancel()

        // 创建新的 debounced 重启任务
        let workItem = DispatchWorkItem { [weak self] in
            self?.performRestart(reason: reason)
        }
        restartWorkItem = workItem

        // 延迟执行
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDebounceDelay, execute: workItem)
    }

    /// 执行实际的重启操作
    private func performRestart(reason: MonitoringRestartReason) {
        // 1. 停止当前监控
        PinchGestureDetector.shared.stopMonitoring()

        // 2. 短暂延迟后重新启动（给系统时间完成设备更新）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard self != nil else { return }

            // 3. 重新启动监控
            let success = PinchGestureDetector.shared.startMonitoring()

            // 4. 日志记录
            #if DEBUG
            if success {
                print("[TrackpadGestureManager] 监控重启成功，原因: \(reason)")
            } else {
                print("[TrackpadGestureManager] 监控重启失败，原因: \(reason)")
            }
            #endif
        }
    }
}