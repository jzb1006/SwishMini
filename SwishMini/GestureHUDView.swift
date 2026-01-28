//
//  GestureHUDView.swift
//  SwishMini
//
//  手势反馈 HUD 视图 - 使用 SwiftUI 实现 macOS 原生风格的提示浮层
//

import SwiftUI
import AppKit
import Combine

// MARK: - 布局常量

private enum HUDViewLayout {
    static let size = CGSize(width: 200, height: 64)
    static let cornerRadius: CGFloat = 14
    static let iconSize: CGFloat = 28
    static let titleFontSize: CGFloat = 13
    static let subtitleFontSize: CGFloat = 11
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 12
    static let spacing: CGFloat = 12
    static let textSpacing: CGFloat = 2
    static let borderOpacity: Double = 0.18

    // 环形进度条配置
    static let progressRingSize: CGFloat = 40
    static let progressRingLineWidth: CGFloat = 3
}

// MARK: - ViewModel

/// HUD 视图模型 - 管理 HUD 显示状态
@MainActor
final class GestureHUDViewModel: ObservableObject {
    /// 当前候选手势类型
    @Published private(set) var candidate: GestureCandidate = .none

    /// 手势进度 (0~1)
    @Published private(set) var progress: CGFloat = 0

    /// 应用手势反馈数据
    func apply(_ feedback: GestureFeedback) {
        let p = max(0, min(feedback.progress, 1))

        withAnimation(.easeOut(duration: 0.12)) {
            candidate = feedback.candidate
            progress = p
        }
    }

    /// 重置为默认状态
    func reset() {
        withAnimation(.easeOut(duration: 0.12)) {
            candidate = .none
            progress = 0
        }
    }
}

// MARK: - HUD View

/// 手势 HUD 视图
struct GestureHUDView: View {
    @ObservedObject var viewModel: GestureHUDViewModel

    /// 是否显示关闭窗口的倒计时进度
    private var showCloseWindowProgress: Bool {
        viewModel.candidate == .closeWindow
    }

    /// 图标缩放效果
    private var iconScale: CGFloat {
        switch viewModel.candidate {
        case .pinchOpen, .pinchClose:
            return 1.0 + (0.25 * viewModel.progress)
        case .closeWindow:
            // 关闭窗口时图标缩放更明显
            return 1.0 + (0.15 * viewModel.progress)
        case .swipeDown, .swipeUp:
            return 1.0 + (0.15 * viewModel.progress)
        case .none, .cancelled:
            return 1.0
        }
    }

    /// 进度条颜色（从橙色平滑渐变到红色）
    private var progressColor: Color {
        // 使用线性插值实现平滑颜色渐变
        // 橙色 (1.0, 0.6, 0.0) → 红色 (1.0, 0.2, 0.2)
        let progress = viewModel.progress
        let green = 0.6 - (0.4 * progress)   // 0.6 → 0.2
        let blue = 0.2 * progress            // 0.0 → 0.2
        return Color(red: 1.0, green: green, blue: blue)
    }

    /// 图标颜色
    private var iconColor: Color {
        if showCloseWindowProgress {
            return progressColor
        }
        return Color.primary
    }

    var body: some View {
        ZStack {
            // 毛玻璃背景
            VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: HUDViewLayout.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: HUDViewLayout.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(HUDViewLayout.borderOpacity), lineWidth: 1)
                )

            // 内容
            HStack(spacing: HUDViewLayout.spacing) {
                // 图标区域（可能带环形进度条）
                ZStack {
                    // 环形进度条背景（仅关闭窗口时显示）
                    if showCloseWindowProgress {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: HUDViewLayout.progressRingLineWidth)
                            .frame(width: HUDViewLayout.progressRingSize, height: HUDViewLayout.progressRingSize)

                        // 环形进度条
                        Circle()
                            .trim(from: 0, to: viewModel.progress)
                            .stroke(
                                progressColor,
                                style: StrokeStyle(
                                    lineWidth: HUDViewLayout.progressRingLineWidth,
                                    lineCap: .round
                                )
                            )
                            .frame(width: HUDViewLayout.progressRingSize, height: HUDViewLayout.progressRingSize)
                            .rotationEffect(.degrees(-90))  // 从顶部开始
                    }

                    // 图标
                    Image(systemName: viewModel.candidate.symbolName)
                        .font(.system(size: HUDViewLayout.iconSize, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .scaleEffect(iconScale)
                }
                .frame(width: HUDViewLayout.progressRingSize, height: HUDViewLayout.progressRingSize)

                // 文字
                VStack(alignment: .leading, spacing: HUDViewLayout.textSpacing) {
                    Text(viewModel.candidate.title)
                        .font(.system(size: HUDViewLayout.titleFontSize, weight: .semibold))
                        .foregroundStyle(showCloseWindowProgress ? progressColor : Color.primary)

                    // 副标题：关闭窗口时显示进度百分比
                    if showCloseWindowProgress {
                        Text("\(Int(viewModel.progress * 100))%")
                            .font(.system(size: HUDViewLayout.subtitleFontSize, weight: .medium).monospacedDigit())
                            .foregroundStyle(progressColor)
                    } else {
                        Text(viewModel.candidate.actionDescription)
                            .font(.system(size: HUDViewLayout.subtitleFontSize, weight: .regular))
                            .foregroundStyle(Color.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, HUDViewLayout.horizontalPadding)
            .padding(.vertical, HUDViewLayout.verticalPadding)
        }
        .frame(width: HUDViewLayout.size.width, height: HUDViewLayout.size.height)
    }
}

// MARK: - Visual Effect Background

/// NSVisualEffectView 的 SwiftUI 包装
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

// MARK: - Preview

#if DEBUG
#Preview("默认状态") {
    GestureHUDView(viewModel: GestureHUDViewModel())
        .padding(20)
}

#Preview("双指张开") {
    GestureHUDView(viewModel: {
        let vm = GestureHUDViewModel()
        Task { @MainActor in
            vm.apply(GestureFeedback(
                phase: .changed,
                candidate: .pinchOpen,
                progress: 0.7,
                scale: 1.35,
                yDelta: 0,
                isInValidRegion: true,
                mouseLocation: .zero
            ))
        }
        return vm
    }())
    .padding(20)
}

#Preview("双指下滑") {
    GestureHUDView(viewModel: {
        let vm = GestureHUDViewModel()
        Task { @MainActor in
            vm.apply(GestureFeedback(
                phase: .changed,
                candidate: .swipeDown,
                progress: 0.6,
                scale: 1.0,
                yDelta: -0.1,
                isInValidRegion: true,
                mouseLocation: .zero
            ))
        }
        return vm
    }())
    .padding(20)
}

#Preview("关闭窗口 - 50%") {
    GestureHUDView(viewModel: {
        let vm = GestureHUDViewModel()
        Task { @MainActor in
            vm.apply(GestureFeedback(
                phase: .changed,
                candidate: .closeWindow,
                progress: 0.5,
                scale: 0.7,
                yDelta: 0,
                isInValidRegion: true,
                mouseLocation: .zero
            ))
        }
        return vm
    }())
    .padding(20)
}

#Preview("关闭窗口 - 90%") {
    GestureHUDView(viewModel: {
        let vm = GestureHUDViewModel()
        Task { @MainActor in
            vm.apply(GestureFeedback(
                phase: .changed,
                candidate: .closeWindow,
                progress: 0.9,
                scale: 0.6,
                yDelta: 0,
                isInValidRegion: true,
                mouseLocation: .zero
            ))
        }
        return vm
    }())
    .padding(20)
}

#Preview("已取消") {
    GestureHUDView(viewModel: {
        let vm = GestureHUDViewModel()
        Task { @MainActor in
            vm.apply(GestureFeedback(
                phase: .ended,
                candidate: .cancelled,
                progress: 1.0,
                scale: 0.8,
                yDelta: 0,
                isInValidRegion: true,
                mouseLocation: .zero
            ))
        }
        return vm
    }())
    .padding(20)
}
#endif