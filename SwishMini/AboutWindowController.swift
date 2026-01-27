//
//  AboutWindowController.swift
//  SwishMini
//
//  Created by 江志彬 on 2026/1/23.
//

import SwiftUI
import AppKit

/// 关于窗口视图 - macOS 标准风格
struct AboutView: View {
    
    var body: some View {
        VStack(spacing: 16) {
            // 应用图标
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 100, height: 100)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            
            // 应用名称
            Text("SwishMini")
                .font(.system(size: 24, weight: .bold))
            
            // 版本信息
            VStack(spacing: 4) {
                Text("版本 1.0.0")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Text("Build 1")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Divider()
                .padding(.horizontal, 20)
            
            // 功能介绍
            VStack(spacing: 8) {
                Text("🖱️ 触控板手势控制工具")
                    .font(.system(size: 13, weight: .medium))

                VStack(alignment: .leading, spacing: 4) {
                    Text("在窗口标题栏使用触控板手势进行操作：")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Label("双指张开 → 全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                        Label("双指捏合 → 还原", systemImage: "arrow.down.right.and.arrow.up.left")
                        Label("双指下滑 → 最小化", systemImage: "minus.circle")
                        Label("双指上滑 → 取消最小化", systemImage: "arrow.up.circle")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            
            Divider()
                .padding(.horizontal, 20)
            
            // 开发者信息
            VStack(spacing: 4) {
                Text("开发者：Jzb1006")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Text("© 2026 Jzb1006. All rights reserved.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            
            Spacer()
                .frame(height: 8)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(width: 320, height: 400)
    }
}

/// 显示关于窗口
func showAboutWindow() {
    let aboutView = AboutView()
    let hostingController = NSHostingController(rootView: aboutView)
    
    let window = NSWindow(contentViewController: hostingController)
    window.title = "关于 SwishMini"
    window.styleMask = [.titled, .closable]
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

#Preview {
    AboutView()
}
