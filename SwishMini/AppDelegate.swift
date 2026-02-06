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
        // 订阅辅助功能授权事件，授权后静默退出以确保权限生效
        subscribeToAccessibilityGranted()

        // 监听屏幕配置变化（热插拔、分辨率调整等）
        setupScreenChangeObserver()

        // 创建菜单栏图标
        setupMenuBar()

        // 检查权限并启动
        checkPermissionsAndStart()
    }

    // MARK: - 屏幕配置监听

    /// 监听屏幕配置变化，触发缓存失效和监控重启
    private func setupScreenChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenConfigurationChanged()
        }
    }

    /// 处理屏幕配置变化
    private func handleScreenConfigurationChanged() {
        // 1. 使屏幕缓存失效
        WindowManager.shared.invalidateScreenCache()

        // 2. 请求重启监控
        TrackpadGestureManager.shared.requestRestartMonitoring(reason: .screenConfigurationChanged)
    }

    // MARK: - 手势识别

    private func startGestureRecognition() {
        trackpadGestureManager.startMonitoring()
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

    /// 订阅辅助功能授权事件，授权后静默退出以确保权限生效
    private func subscribeToAccessibilityGranted() {
        permissionManager.onAccessibilityGranted
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.quit()
            }
            .store(in: &cancellables)
    }

    private func checkPermissionsAndStart() {
        if permissionManager.hasAccessibilityPermission {
            startGestureRecognition()
        } else {
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
