import AppKit
import SwiftUI

@main
struct Copy2exFATApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didPlaceWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NSApp.windows.forEach(configure)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        configure(window)
    }

    private func configure(_ window: NSWindow) {
        guard isMainAppWindow(window) else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.11, alpha: 1)
        window.styleMask.insert(.fullSizeContentView)
        window.hasShadow = true
        window.toolbarStyle = .unifiedCompact
        window.isRestorable = false
        window.identifier = NSUserInterfaceItemIdentifier("Copy2exFAT.main")
        guard !didPlaceWindow else { return }
        didPlaceWindow = true
        window.setContentSize(NSSize(width: 520, height: 740))
        let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.max(by: {
                $0.visibleFrame.width * $0.visibleFrame.height < $1.visibleFrame.width * $1.visibleFrame.height
            })
            ?? window.screen
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: 520, height: min(740, max(640, visible.height - 24)))
        let x = visible.midX - size.width / 2
        let y = visible.midY - size.height / 2
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private func isMainAppWindow(_ window: NSWindow) -> Bool {
        if window is NSPanel {
            return false
        }
        let name = String(describing: type(of: window))
        if name.contains("NSNav") || name.contains("Finder") || name.contains("OpenPanel") || name.contains("SavePanel") {
            return false
        }
        return true
    }
}

enum Format {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: max(value, 0))
    }
}

extension Color {
    static let appAccent = Color(red: 0.36, green: 0.85, blue: 0.76)
    static let appBgTop = Color(red: 0.07, green: 0.09, blue: 0.11)
    static let appBgBottom = Color(red: 0.04, green: 0.05, blue: 0.07)
    static let appCard = Color.white.opacity(0.045)
    static let appStroke = Color.white.opacity(0.08)
    static let appWarning = Color(red: 0.98, green: 0.75, blue: 0.28)
    static let appDanger = Color(red: 0.97, green: 0.45, blue: 0.45)
    static let appSuccess = Color(red: 0.42, green: 0.86, blue: 0.66)
}
