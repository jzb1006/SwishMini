//
//  PermissionManager.swift
//  SwishMini
//
//  Created by SwishMini on 2026/1/21.
//

import Foundation
import Combine
import AppKit
import ApplicationServices

/// 权限管理器
/// 负责检查和请求 macOS 系统权限（主要是辅助功能权限）
class PermissionManager: ObservableObject {

    static let shared = PermissionManager()

    // MARK: - Published Properties

    @Published var hasAccessibilityPermission: Bool = false

    // MARK: - 辅助功能授权事件

    /// 当辅助功能权限从未授权跃迁为已授权时发布事件，供 AppDelegate 订阅以触发退出流程
    let onAccessibilityGranted = PassthroughSubject<Void, Never>()

    // MARK: - Private Properties

    /// 启动时的权限状态，用于判断是否为进程内跃迁
    private let wasGrantedAtLaunch: Bool

    /// 是否已请求终止（门闩），确保仅触发一次退出流程
    private var didRequestTermination = false

    private init() {
        // 同步初始化权限状态，避免竞态条件
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        self.wasGrantedAtLaunch = accessEnabled
        self.hasAccessibilityPermission = accessEnabled

        // 未授权时自动启动权限监控
        if !accessEnabled {
            startPermissionCheckTimer()
        }
    }
    
    
    // MARK: - 辅助功能权限
    
    /// 检查是否拥有辅助功能权限
    func checkAccessibilityPermission() -> Bool {
        // 不弹出提示，只检查
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = accessEnabled
        }
        
        // 如果权限刚被授予，可能需要短暂延迟才能生效
        if !accessEnabled {
            // 0.5秒后再检查一次
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let recheckOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false]
                let recheckResult = AXIsProcessTrustedWithOptions(recheckOptions)
                self.hasAccessibilityPermission = recheckResult
            }
        }
        
        return accessEnabled
    }
    
    /// 请求辅助功能权限（会打开系统设置）
    func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let _ = AXIsProcessTrustedWithOptions(options)

        // 启动定时器检查权限状态
        startPermissionCheckTimer()
    }
    
    /// 打开系统偏好设置 - 隐私与安全性 - 辅助功能
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    // MARK: - 权限监控

    private var permissionCheckTimer: Timer?

    /// 启动权限检查定时器
    private func startPermissionCheckTimer() {
        // 取消现有定时器
        permissionCheckTimer?.invalidate()

        // 记录上一次检查的权限状态，用于检测跃迁
        var lastAccessEnabled = hasAccessibilityPermission

        // 每秒检查一次权限状态
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let currentAccessEnabled = self.checkAccessibilityPermission()
            defer { lastAccessEnabled = currentAccessEnabled }

            // 权限未获得，继续等待
            guard currentAccessEnabled else { return }

            // 获得权限后停止定时器
            self.permissionCheckTimer?.invalidate()
            self.permissionCheckTimer = nil

            // 检测是否为 false -> true 跃迁
            let didTransitionToGranted = !lastAccessEnabled && currentAccessEnabled
            guard didTransitionToGranted else { return }

            // 防御性检查：启动时已授权则不触发（理论上不会到达此处）
            guard !self.wasGrantedAtLaunch else { return }

            // 门闩检查：确保仅触发一次退出流程
            guard !self.didRequestTermination else { return }
            self.didRequestTermination = true

            self.onAccessibilityGranted.send(())
        }
    }
}
