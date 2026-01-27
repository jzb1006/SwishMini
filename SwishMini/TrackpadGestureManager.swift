//
//  TrackpadGestureManager.swift
//  SwishMini
//
//  触控板手势管理器
//

import Cocoa

class TrackpadGestureManager {
    static let shared = TrackpadGestureManager()
    
    private init() {}
    
    func startMonitoring() {
        // 启动捏合手势检测（MultitouchSupport）
        // 手势动作已在 PinchGestureDetector 内部自动执行
        PinchGestureDetector.shared.startMonitoring()
        
        print("✅ 触控板手势监控已启动")
        print("   📌 双指张开 → 全屏")
        print("   📌 双指捏合 → 还原")
        print("   📌 双指下滑 → 最小化")
        print("   📌 双指上滑 → 取消最小化（需在原位置附近）")
    }
    
    func stopMonitoring() {
        // 停止捏合手势检测器
        PinchGestureDetector.shared.stopMonitoring()
        
        print("⏹️ 触控板手势监控已停止")
    }
}
