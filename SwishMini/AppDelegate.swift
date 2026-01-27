//
//  AppDelegate.swift
//  SwishMini
//
//  标题栏双指下滑菜单功能
//

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem?
    
    private let permissionManager = PermissionManager.shared
    private let trackpadGestureManager = TrackpadGestureManager.shared
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 SwishMini 正在启动...")
        
        // 创建菜单栏图标
        setupMenuBar()
        
        // 检查权限并启动
        checkPermissionsAndStart()
    }
    
    // MARK: - 手势识别
    
    private func startGestureRecognition() {
        print("🎯 启动触控板手势监听...")
        trackpadGestureManager.startMonitoring()
        print("✨ 手势系统已启动！")
    }
    
    // MARK: - 菜单栏设置
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "SwishMini")
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "关于 SwishMini", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "辅助功能权限...", action: #selector(requestPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    // MARK: - 权限管理
    
    private func checkPermissionsAndStart() {
        print("🔍 检查权限状态...")
        print("   辅助功能权限: \(permissionManager.hasAccessibilityPermission ? "✅ 已授予" : "❌ 未授予")")
        
        if permissionManager.hasAccessibilityPermission {
            print("✅ 权限验证通过")
            startGestureRecognition()
        } else {
            print("⚠️ 缺少权限")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showPermissionAlert()
            }
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "SwishMini 需要辅助功能权限来控制窗口。请在系统设置中授予权限。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        
        if alert.runModal() == .alertFirstButtonReturn {
            permissionManager.requestAccessibilityPermission()
        }
    }
    
    // MARK: - 菜单操作
    
    @objc private func showAbout() {
        showAboutWindow()
    }
    
    @objc private func requestPermissions() {
        permissionManager.requestAccessibilityPermission()
    }
    
    @objc private func quit() {
        trackpadGestureManager.stopMonitoring()
        NSApplication.shared.terminate(nil)
    }
}
