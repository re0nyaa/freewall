import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?
    weak var mainWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }
    
    @objc func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window.canBecomeMain else { return }
        if self.mainWindow !== window {
            self.mainWindow = window
            window.delegate = self
        }
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }
    
    func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            if let window = self?.mainWindow {
                window.makeKeyAndOrderFront(nil)
            } else if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        SpoofDPIManager.shared.stop()
    }
}

@main
struct freewallApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = SpoofDPIManager.shared
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("freewall 정보") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [NSApplication.AboutPanelOptionKey.version: "1.0"]
                    )
                }
            }
        }
        
        MenuBarExtra("freewall", systemImage: manager.isRunning ? "shield.fill" : "shield") {
            Text(manager.isRunning ? "상태: DPI 우회 활성화됨" : "상태: DPI 우회 비활성화됨")
                .font(.headline)
            
            Divider()
            
            Button(manager.isRunning ? "보호 중지" : "보호 시작") {
                manager.toggle()
            }
            .keyboardShortcut("s")
            
            Divider()
            
            Button("대시보드 열기") {
                appDelegate.showMainWindow()
            }
            
            Divider()
            
            Button("종료") {
                manager.stop()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}



