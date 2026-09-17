import AppKit

enum FilePicker {
    static func choose(
        files: Bool,
        folders: Bool,
        multiple: Bool,
        message: String
    ) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = files
        panel.canChooseDirectories = folders
        panel.allowsMultipleSelection = multiple
        panel.canCreateDirectories = folders && !files
        panel.message = message
        panel.prompt = "选择"
        panel.appearance = NSAppearance(named: .aqua)

        if folders, !files, FileManager.default.fileExists(atPath: "/Volumes") {
            panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        }

        // Hide our custom window so the system picker is not attached as a
        // sheet (macOS 26 glass sheets punch transparent holes in this layout).
        let hosts = NSApp.windows.filter { $0.isVisible && $0 !== panel && !($0 is NSPanel) }
        hosts.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true)

        let response = panel.runModal()

        hosts.forEach { $0.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        return response == .OK ? panel.urls : []
    }
}
