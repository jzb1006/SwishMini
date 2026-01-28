//
//  TrackpadGestureManager.swift
//  SwishMini
//
//  触控板手势管理器
//

import Cocoa

class TrackpadGestureManager {
    static let shared = TrackpadGestureManager()

    /// HUD 窗口控制器
    private let gestureHUD = GestureHUDWindowController()

    private init() {}

    func startMonitoring() {
        // 设置手势反馈回调 -> HUD 更新
        PinchGestureDetector.shared.onGestureFeedback = { [weak self] feedback in
            self?.gestureHUD.update(feedback: feedback)
        }

        // 启动捏合手势检测（MultitouchSupport）
        PinchGestureDetector.shared.startMonitoring()

        print("✅ 触控板手势监控已启动")
        print("   📌 双指张开 → 全屏")
        print("   📌 双指捏合 → 还原")
        print("   📌 双指下滑 → 最小化")
        print("   📌 双指上滑 → 取消最小化（需在原位置附近）")
        print("   🎨 手势 HUD 提示已启用")
    }

    func stopMonitoring() {
        // 清理 HUD 回调
        PinchGestureDetector.shared.onGestureFeedback = nil

        // 停止 HUD 控制器
        Task { @MainActor in
            gestureHUD.stop()
        }

        // 停止捏合手势检测器
        PinchGestureDetector.shared.stopMonitoring()

        print("⏹️ 触控板手势监控已停止")
    }
}