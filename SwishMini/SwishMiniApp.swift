//
//  SwishMiniApp.swift
//  SwishMini
//
//  Created by 江志彬 on 2026/1/20.
//

import SwiftUI

@main
struct SwishMiniApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
