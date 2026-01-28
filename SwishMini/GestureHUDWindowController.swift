//
//  GestureHUDWindowController.swift
//  SwishMini
//
//  手势 HUD 窗口控制器 - 管理浮层窗口的显示、隐藏和位置
//

import AppKit
import SwiftUI

// MARK: - 布局常量

private enum HUDLayout {
    static let size = CGSize(width: 200, height: 64)
    static let titleBarOffset: CGFloat = 44        // 标题栏下方偏移
    static let mouseLocationOffset: CGFloat = 28   // 鼠标位置上方偏移
    static let fadeDuration: TimeInterval = 0.12
    static let hideDelay: TimeInterval = 0.2
    static let throttleInterval: TimeInterval = 1.0 / 60.0  // 60 FPS
}

// MARK: - HUD 窗口控制器

/// HUD 窗口控制器 - 管理浮层窗口的显示、隐藏和位置
@MainActor
final class GestureHUDWindowController {

    // MARK: - Properties

    private let viewModel = GestureHUDViewModel()
    private lazy var panel: NSPanel = makePanel()

    /// 隐藏延迟任务
    private var hideWorkItem: DispatchWorkItem?

    /// 待处理的反馈数据（用于节流）
    private var pendingFeedback: GestureFeedback?
    private var throttleWorkItem: DispatchWorkItem?

    /// 显示版本号 - 用于防止淡出动画回调覆盖新状态
    private var showGeneration: UInt64 = 0

    /// 是否已停止（用于防止 stop 后仍有更新）
    private var isStopped = false

    // MARK: - Initialization

    init() {
        // 触发 lazy 初始化
        _ = panel
    }

    // MARK: - Public Methods

    /// 停止 HUD 控制器，清理所有待处理任务
    func stop() {
        isStopped = true
        cancelAllPendingWork()
        hide(animated: false)
        viewModel.reset()
    }

    /// 重新启用 HUD 控制器
    func resume() {
        isStopped = false
    }

    /// 显示 HUD 在指定位置
    func show(at point: CGPoint) {
        guard !isStopped else { return }

        showGeneration &+= 1
        cancelScheduledHide()
        setPanelPosition(centeredAt: point)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            fade(to: 1, duration: HUDLayout.fadeDuration)
        } else if panel.alphaValue < 1 {
            fade(to: 1, duration: HUDLayout.fadeDuration)
        }
    }

    /// 隐藏 HUD（带动画）
    func hide() {
        hide(animated: true)
    }

    /// 更新 HUD 状态
    func update(feedback: GestureFeedback) {
        guard !isStopped else { return }

        pendingFeedback = feedback

        // 节流：避免高频更新导致性能问题
        if throttleWorkItem != nil {
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            self.throttleWorkItem = nil
            guard let latest = self.pendingFeedback else { return }
            self.apply(feedback: latest)
        }

        throttleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + HUDLayout.throttleInterval, execute: work)
    }

    // MARK: - Private Methods

    private func apply(feedback: GestureFeedback) {
        // 如果不在有效区域，隐藏 HUD
        if !feedback.isInValidRegion {
            cancelScheduledHide()
            hide(animated: true)
            return
        }

        let anchor = anchorPoint(for: feedback)

        switch feedback.phase {
        case .began, .changed:
            cancelScheduledHide()
            show(at: anchor)
            viewModel.apply(feedback)

        case .ended, .cancelled:
            viewModel.apply(feedback)
            scheduleHide(after: HUDLayout.hideDelay)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        cancelScheduledHide()

        let work = DispatchWorkItem { [weak self] in
            self?.hide(animated: true)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func cancelAllPendingWork() {
        throttleWorkItem?.cancel()
        throttleWorkItem = nil
        pendingFeedback = nil
        cancelScheduledHide()
    }

    private func hide(animated: Bool) {
        cancelScheduledHide()

        guard panel.isVisible else { return }

        if animated {
            let currentGeneration = showGeneration
            fade(to: 0, duration: HUDLayout.fadeDuration) { [weak self] in
                guard let self else { return }
                // 仅当版本号未变化时才执行 orderOut，防止竞态
                if self.showGeneration == currentGeneration {
                    self.panel.orderOut(nil)
                }
            }
        } else {
            panel.alphaValue = 0
            panel.orderOut(nil)
        }
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = alpha
        } completionHandler: {
            completion?()
        }
    }

    /// 计算 HUD 锚点位置
    private func anchorPoint(for feedback: GestureFeedback) -> CGPoint {
        if let frame = feedback.windowFrame {
            // 优先使用窗口标题栏中心位置
            return CGPoint(x: frame.midX, y: frame.maxY - HUDLayout.titleBarOffset)
        }

        // 回退：鼠标位置附近
        return CGPoint(x: feedback.mouseLocation.x, y: feedback.mouseLocation.y + HUDLayout.mouseLocationOffset)
    }

    /// 设置面板位置（居中于指定点）
    private func setPanelPosition(centeredAt center: CGPoint) {
        let size = panel.frame.size
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)

        // 确保窗口在屏幕可见区域内
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main {
            let vf = screen.visibleFrame
            origin.x = max(vf.minX, min(origin.x, vf.maxX - size.width))
            origin.y = max(vf.minY, min(origin.y, vf.maxY - size.height))
        }

        panel.setFrameOrigin(origin)
    }

    /// 创建 HUD 面板
    private func makePanel() -> NSPanel {
        let contentView = GestureHUDView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = CGRect(origin: .zero, size: HUDLayout.size)

        let panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 配置面板属性
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating  // 使用 .floating 而非 .statusBar，避免过高层级
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // 配置行为：跨空间可见、全屏辅助
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ] as NSWindow.CollectionBehavior

        panel.contentView = hostingView
        panel.alphaValue = 0

        return panel
    }
}