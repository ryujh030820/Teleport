import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: SettingsStore
    private let hostingController: NSHostingController<SettingsView>

    private let onCheckForUpdates: () -> Void

    init(store: SettingsStore, onCheckForUpdates: @escaping () -> Void = {}) {
        self.store = store
        self.onCheckForUpdates = onCheckForUpdates
        
        let rootView = SettingsView(
            store: store,
            onBrowseApplications: {},
            onCheckForUpdates: onCheckForUpdates
        )
        
        self.hostingController = NSHostingController(rootView: rootView)

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "Teleport Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        
        // Standard window background for modern macOS look
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = hostingController

        super.init(window: window)

        window.delegate = self
        
        // Update root view with actual callbacks
        hostingController.rootView = SettingsView(
            store: store,
            onBrowseApplications: { [weak self] in
                self?.presentApplicationPicker()
            },
            onCheckForUpdates: onCheckForUpdates
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    private func presentApplicationPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choose Applications"
        panel.message = "Select one or more .app bundles to manage in the active profile."
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]

        if panel.runModal() == .OK {
            store.addApplications(from: panel.urls)
        }
    }
}

private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown,
           firstResponder is CaptureTextField,
           let contentView,
           let hitView = contentView.hitTest(event.locationInWindow),
           !(hitView is CaptureTextField) {
            makeFirstResponder(nil)
        }
        super.sendEvent(event)
    }
}
