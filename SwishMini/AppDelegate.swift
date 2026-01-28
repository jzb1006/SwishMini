//
//  AppDelegate.swift
//  SwishMini
//
//  标题栏双指下滑菜单功能
//

import Cocoa
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {

    var statusItem: NSStatusItem?

    private let permissionManager = PermissionManager.shared
    private let trackpadGestureManager = TrackpadGestureManager.shared
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 SwishMini 正在启动...")

        // 订阅首次授权事件，用于触发退出重启流程
        subscribeToFirstTimeGranted()

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

    /// 订阅首次授权事件，触发退出重启流程
    private func subscribeToFirstTimeGranted() {
        permissionManager.onFirstTimeGranted
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self = self else { return }
                self.showFirstTimeGrantedAlertAndQuit()
            }
            .store(in: &cancellables)
    }

    /// 显示首次授权成功提示并退出应用
    private func showFirstTimeGrantedAlertAndQuit() {
        // 激活应用到前台，确保用户能看到提示
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "权限已授予"
        alert.informativeText = "为确保辅助功能权限完全生效，SwishMini 将退出。\n请重新启动应用以开始使用。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "退出并重启")
        _ = alert.runModal()

        quit()
    }

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
