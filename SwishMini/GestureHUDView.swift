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

    /// 图标缩放效果
    private var iconScale: CGFloat {
        switch viewModel.candidate {
        case .pinchOpen, .pinchClose:
            return 1.0 + (0.25 * viewModel.progress)
        case .swipeDown, .swipeUp:
            return 1.0 + (0.15 * viewModel.progress)
        case .none:
            return 1.0
        }
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
                // 图标
                Image(systemName: viewModel.candidate.symbolName)
                    .font(.system(size: HUDViewLayout.iconSize, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .scaleEffect(iconScale)

                // 文字
                VStack(alignment: .leading, spacing: HUDViewLayout.textSpacing) {
                    Text(viewModel.candidate.title)
                        .font(.system(size: HUDViewLayout.titleFontSize, weight: .semibold))
                        .foregroundStyle(Color.primary)

                    Text(viewModel.candidate.actionDescription)
                        .font(.system(size: HUDViewLayout.subtitleFontSize, weight: .regular))
                        .foregroundStyle(Color.secondary)
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
#endif