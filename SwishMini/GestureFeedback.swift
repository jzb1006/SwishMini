//
//  GestureFeedback.swift
//  SwishMini
//
//  手势反馈数据模型 - 用于检测器与 HUD 之间的通信
//

import Foundation
import CoreGraphics

// MARK: - 手势阶段

/// 手势生命周期阶段
enum GesturePhase: Equatable {
    /// 手势开始（双指触摸触控板）
    case began
    /// 手势进行中（持续移动）
    case changed
    /// 手势正常结束（双指离开触控板）
    case ended
    /// 手势取消（离开有效区域等）
    case cancelled
}

// MARK: - 候选手势类型

/// 候选手势类型（基于实时数据推断）
enum GestureCandidate: Equatable {
    /// 未明确（手势幅度不足以判断）
    case none
    /// 双指张开 -> 全屏
    case pinchOpen
    /// 双指捏合 -> 还原
    case pinchClose
    /// 双指下滑 -> 最小化
    case swipeDown
    /// 双指上滑 -> 取消最小化
    case swipeUp

    /// 获取对应的 SF Symbol 图标名称
    var symbolName: String {
        switch self {
        case .none:        return "macwindow"
        case .pinchOpen:   return "arrow.up.left.and.arrow.down.right"
        case .pinchClose:  return "arrow.down.right.and.arrow.up.left"
        case .swipeDown:   return "arrow.down.circle"
        case .swipeUp:     return "arrow.up.circle"
        }
    }

    /// 获取中文标题
    var title: String {
        switch self {
        case .none:        return "标题栏区域"
        case .pinchOpen:   return "双指张开"
        case .pinchClose:  return "双指捏合"
        case .swipeDown:   return "双指下滑"
        case .swipeUp:     return "双指上滑"
        }
    }

    /// 获取动作描述
    var actionDescription: String {
        switch self {
        case .none:        return "双指手势进行中"
        case .pinchOpen:   return "全屏"
        case .pinchClose:  return "还原"
        case .swipeDown:   return "最小化"
        case .swipeUp:     return "取消最小化"
        }
    }
}

// MARK: - 手势反馈数据

/// 手势反馈数据结构
struct GestureFeedback: Equatable {
    /// 手势阶段
    let phase: GesturePhase

    /// 候选手势类型
    let candidate: GestureCandidate

    /// 归一化进度 (0~1)
    let progress: CGFloat

    /// 捏合比例（相对于手势开始时，1.0 为初始值）
    let scale: CGFloat

    /// Y 轴位移（相对于手势开始时，正值=向上，负值=向下）
    let yDelta: CGFloat

    /// 是否在有效区域内（标题栏或最小化恢复热点）
    let isInValidRegion: Bool

    /// 鼠标全局位置（屏幕坐标系）
    let mouseLocation: CGPoint

    /// 鼠标下方窗口的 frame（可选）
    let windowFrame: CGRect?

    /// 时间戳
    let timestamp: Date

    init(
        phase: GesturePhase,
        candidate: GestureCandidate,
        progress: CGFloat,
        scale: CGFloat,
        yDelta: CGFloat,
        isInValidRegion: Bool,
        mouseLocation: CGPoint,
        windowFrame: CGRect? = nil,
        timestamp: Date = Date()
    ) {
        self.phase = phase
        self.candidate = candidate
        self.progress = max(0, min(progress, 1))  // 钳制到 0~1
        self.scale = scale
        self.yDelta = yDelta
        self.isInValidRegion = isInValidRegion
        self.mouseLocation = mouseLocation
        self.windowFrame = windowFrame
        self.timestamp = timestamp
    }
}