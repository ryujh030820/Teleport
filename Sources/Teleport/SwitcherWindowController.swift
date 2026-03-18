import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

final class SwitcherWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel = SwitcherViewModel()
    private let hostingView = SwitcherHostingView(rootView: AnyView(EmptyView()))
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var sessionModifiers: NSEvent.ModifierFlags = []
    private var backgroundStyle: SwitcherBackgroundStyle = .glass
    private var currentProfileID: UUID?
    private var profiles: [TeleportProfile] = []
    private var onSwitchProfile: ((UUID) -> SwitcherSnapshot?)?
    private var suppressHover = false
    private var lastMouseLocation: NSPoint?
    private var mouseMonitor: Any?
    private var thumbnailGeneration: Int = 0
    private var currentPanelLayout: SwitcherLayout?
    var onActivateApplication: ((NSRunningApplication) -> Void)?
    var isSwitcherVisible: Bool {
        window?.isVisible == true
    }
    var visibleProfileID: UUID? {
        isSwitcherVisible ? currentProfileID : nil
    }

    init() {
        let panel = SwitcherPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 248),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.delegate = nil

        super.init(window: panel)

        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        if #available(macOS 14.0, *) {
            hostingView.sceneBridgingOptions = []
        }

        panel.contentView = hostingView
        panel.delegate = self
        panel.onEscape = { [weak self] in
            self?.hide()
        }
        hostingView.onEscape = { [weak self] in
            self?.hide()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        snapshot: SwitcherSnapshot,
        currentProfileID: UUID,
        profiles: [TeleportProfile],
        requiredModifiers: NSEvent.ModifierFlags,
        backgroundStyle: SwitcherBackgroundStyle,
        onSwitchProfile: @escaping (UUID) -> SwitcherSnapshot?
    ) {
        self.currentProfileID = currentProfileID
        self.profiles = profiles
        self.sessionModifiers = requiredModifiers
        self.backgroundStyle = backgroundStyle
        self.onSwitchProfile = onSwitchProfile
        viewModel.profiles = profiles
        viewModel.currentProfileID = currentProfileID
        viewModel.profileName = profiles.first(where: { $0.id == currentProfileID })?.name ?? ""
        viewModel.showProfilePicker = false
        viewModel.update(snapshot: snapshot)
        applyLayout()
        positionWindow()
        refreshWindowsForSelectedApp()
        beginSuppressHover()
        installEventMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.makeFirstResponder(hostingView)
    }

    func moveSelection(forward: Bool) {
        guard isSwitcherVisible else {
            return
        }

        viewModel.moveSelection(forward: forward)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func applyBackgroundStyle(_ style: SwitcherBackgroundStyle) {
        backgroundStyle = style

        if isSwitcherVisible {
            applyLayout()
        }
    }

    /// Position so the app grid panel is always centered on screen;
    /// the window preview list hangs below.
    private func positionWindow() {
        guard
            let screen = NSScreen.main ?? window?.screen ?? NSScreen.screens.first,
            let window,
            let layout = currentPanelLayout
        else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let totalHeight = window.frame.height

        // Center the panel portion; list extends below
        let panelCenterY = visibleFrame.midY
        let windowTop = panelCenterY + layout.height / 2
        let originY = windowTop - totalHeight

        let origin = NSPoint(
            x: visibleFrame.midX - layout.width / 2,
            y: max(originY, visibleFrame.minY)
        )
        window.setFrameOrigin(origin)
    }

    private func applyLayout() {
        guard
            let window,
            let screen = NSScreen.main ?? window.screen ?? NSScreen.screens.first
        else {
            return
        }

        let layout = SwitcherLayout.make(appCount: viewModel.apps.count, visibleFrame: screen.visibleFrame)
        currentPanelLayout = layout
        hostingView.rootView = AnyView(
            SwitcherOverlayView(
                viewModel: viewModel,
                layout: layout,
                backgroundStyle: backgroundStyle,
                onAppTapped: { [weak self] app in
                    self?.activate(app: app)
                },
                onAppHovered: { [weak self] index in
                    self?.handleAppHovered(index: index)
                },
                onWindowTapped: { [weak self] window in
                    guard let self, let app = self.viewModel.selectedApp else { return }
                    self.activateWindow(window, for: app)
                },
                onWindowHovered: { [weak self] index in
                    guard let self, !self.suppressHover else { return }
                    self.viewModel.selectWindow(at: index)
                }
            )
        )

        let previewHeight = windowListHeight()
        window.setContentSize(NSSize(width: layout.width, height: layout.height + previewHeight))
    }

    private func windowListHeight() -> CGFloat {
        // Always reserve max space so the panel doesn't jump when the list appears/disappears.
        let maxVisible = CGFloat(WindowPreviewList.maxVisibleCards)
        let gap: CGFloat = 10
        return gap + maxVisible * WindowPreviewList.cardHeight + (maxVisible - 1) * WindowPreviewList.spacing
    }

    private func handleAppHovered(index: Int) {
        guard !suppressHover else { return }
        guard index != viewModel.selectionIndex else { return }
        viewModel.setSelection(index: index)
        refreshWindowsForSelectedApp()
    }

    private func beginSuppressHover() {
        suppressHover = true
        lastMouseLocation = NSEvent.mouseLocation
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                guard let self else { return event }
                let current = NSEvent.mouseLocation
                if let last = self.lastMouseLocation,
                   abs(current.x - last.x) > 3 || abs(current.y - last.y) > 3 {
                    self.suppressHover = false
                    if let monitor = self.mouseMonitor {
                        NSEvent.removeMonitor(monitor)
                        self.mouseMonitor = nil
                    }
                }
                return event
            }
        }
    }

    private func refreshWindowsForSelectedApp() {
        guard let app = viewModel.selectedApp else {
            viewModel.updateWindows([])
            return
        }

        // Fast: enumerate windows without thumbnails
        let windows = WindowEnumerator.windows(for: app.runningApplication)
        viewModel.updateWindows(windows)

        // Async: load thumbnails in background
        guard viewModel.hasMultipleWindows else { return }
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        let windowsCopy = windows
        DispatchQueue.global(qos: .userInitiated).async {
            let withThumbs = WindowEnumerator.withThumbnails(windowsCopy)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.thumbnailGeneration == generation else { return }
                self.viewModel.updateWindows(withThumbs)
            }
        }
    }

    private func installEventMonitor() {
        removeEventMonitor()
        installEventTap()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else {
                return event
            }

            switch event.type {
            case .keyDown:
                return self.handleKeyDown(event)
            case .flagsChanged:
                return self.handleFlagsChanged(event)
            default:
                return event
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return }

            switch event.type {
            case .keyDown:
                if Int(event.keyCode) == kVK_Escape {
                    self.hide()
                }
            case .flagsChanged:
                if !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(self.sessionModifiers) {
                    self.activateSelectedApp()
                }
            default:
                break
            }
        }
    }

    private func removeEventMonitor() {
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private func installEventTap() {
        let eventMask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userData -> Unmanaged<CGEvent>? in
                guard let userData else {
                    return Unmanaged.passUnretained(event)
                }

                let controller = Unmanaged<SwitcherWindowController>.fromOpaque(userData).takeUnretainedValue()
                return controller.handleInterceptedEvent(type: type, event: event)
            },
            userInfo: userData
        ) else {
            return
        }

        self.eventTap = eventTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handleInterceptedEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isSwitcherVisible else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == UInt16(kVK_Escape) {
                Task { @MainActor [weak self] in
                    self?.hide()
                }
                return nil
            }
            if keyCode == UInt16(kVK_Tab) {
                let shiftHeld = event.flags.contains(.maskShift)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.beginSuppressHover()
                    self.viewModel.moveSelection(forward: !shiftHeld)
                    self.refreshWindowsForSelectedApp()
                }
                return nil
            }
        case .flagsChanged:
            break
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Window selection mode — user navigating window thumbnails
        if viewModel.isInWindowSelection {
            return handleWindowSelectionKeyDown(event)
        }

        // Profile picker mode
        if viewModel.showProfilePicker {
            return handleProfilePickerKeyDown(event)
        }

        if Int(event.keyCode) == kVK_ANSI_Grave {
            openProfilePicker()
            return nil
        }

        if handleProfileSwitchKey(event) {
            return nil
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
            return nil
        case kVK_Return:
            activateSelectedApp()
            return nil
        case kVK_Tab:
            beginSuppressHover()
            viewModel.moveSelection(forward: !event.modifierFlags.contains(.shift))
            refreshWindowsForSelectedApp()
            return nil
        case kVK_RightArrow:
            beginSuppressHover()
            viewModel.moveSelection(forward: true)
            refreshWindowsForSelectedApp()
            return nil
        case kVK_LeftArrow:
            beginSuppressHover()
            viewModel.moveSelection(forward: false)
            refreshWindowsForSelectedApp()
            return nil
        case kVK_DownArrow:
            if viewModel.hasMultipleWindows {
                beginSuppressHover()
                viewModel.enterWindowSelection()
            }
            return nil
        case kVK_UpArrow:
            return nil
        default:
            break
        }

        // Number keys 1-9 for quick window selection
        if viewModel.hasMultipleWindows, let windowIndex = windowIndexForKeyCode(event.keyCode) {
            viewModel.selectWindow(at: windowIndex)
            activateSelectedApp()
            return nil
        }

        guard let app = viewModel.selectApp(forKeyCode: event.keyCode) else {
            return event
        }

        activate(app: app)
        return nil
    }

    private func openProfilePicker() {
        guard profiles.count > 1 else { return }
        viewModel.profilePickerIndex = profiles.firstIndex(where: { $0.id == currentProfileID }) ?? 0
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            viewModel.showProfilePicker = true
        }
    }

    private func handleProfilePickerKeyDown(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case kVK_Escape, kVK_ANSI_Grave:
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                viewModel.showProfilePicker = false
            }
            return nil
        case kVK_UpArrow:
            if viewModel.profilePickerIndex > 0 {
                viewModel.profilePickerIndex -= 1
            }
            return nil
        case kVK_DownArrow:
            if viewModel.profilePickerIndex < profiles.count - 1 {
                viewModel.profilePickerIndex += 1
            }
            return nil
        case kVK_Return:
            let selectedProfile = profiles[viewModel.profilePickerIndex]
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                viewModel.showProfilePicker = false
            }
            if selectedProfile.id != currentProfileID, let snapshot = onSwitchProfile?(selectedProfile.id) {
                currentProfileID = selectedProfile.id
                viewModel.currentProfileID = selectedProfile.id
                viewModel.profileName = selectedProfile.name
                viewModel.switchProfile(snapshot: snapshot)
                refreshWindowsForSelectedApp()
                applyLayout()
                positionWindow()
            }
            return nil
        default:
            // Close picker and fall through to normal handling
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                viewModel.showProfilePicker = false
            }
            return handleKeyDown(event)
        }
    }

    private func handleWindowSelectionKeyDown(_ event: NSEvent) -> NSEvent? {
        switch Int(event.keyCode) {
        case kVK_Escape:
            viewModel.exitWindowSelection()
            return nil
        case kVK_Return:
            activateSelectedApp()
            return nil
        case kVK_Tab:
            viewModel.exitWindowSelection()
            beginSuppressHover()
            viewModel.moveSelection(forward: !event.modifierFlags.contains(.shift))
            refreshWindowsForSelectedApp()
            return nil
        case kVK_DownArrow:
            beginSuppressHover()
            viewModel.moveWindowSelection(forward: true)
            return nil
        case kVK_UpArrow:
            beginSuppressHover()
            if viewModel.windowSelectionIndex <= 0 {
                viewModel.exitWindowSelection()
            } else {
                viewModel.moveWindowSelection(forward: false)
            }
            return nil
        case kVK_RightArrow:
            viewModel.exitWindowSelection()
            beginSuppressHover()
            viewModel.moveSelection(forward: true)
            refreshWindowsForSelectedApp()
            return nil
        case kVK_LeftArrow:
            viewModel.exitWindowSelection()
            beginSuppressHover()
            viewModel.moveSelection(forward: false)
            refreshWindowsForSelectedApp()
            return nil
        default:
            if let windowIndex = windowIndexForKeyCode(event.keyCode) {
                viewModel.selectWindow(at: windowIndex)
                activateSelectedApp()
                return nil
            }
            return event
        }
    }

    private func windowIndexForKeyCode(_ keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        if !event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(sessionModifiers) {
            activateSelectedApp()
            return nil
        }

        return event
    }

    private func handleProfileSwitchKey(_ event: NSEvent) -> Bool {
        guard
            let profileID = profiles.first(where: { $0.profileSwitchKeyCode == UInt16(event.keyCode) })?.id,
            profileID != currentProfileID,
            let snapshot = onSwitchProfile?(profileID)
        else {
            return false
        }

        currentProfileID = profileID
        viewModel.currentProfileID = profileID
        viewModel.profileName = profiles.first(where: { $0.id == profileID })?.name ?? ""
        viewModel.switchProfile(snapshot: snapshot)
        refreshWindowsForSelectedApp()
        applyLayout()
        positionWindow()
        return true
    }

    private func activateSelectedApp() {
        guard let app = viewModel.selectedApp else {
            hide()
            return
        }

        if let window = viewModel.selectedWindow {
            activateWindow(window, for: app)
        } else {
            activate(app: app)
        }
    }

    private func activate(app: SwitchableApp) {
        hide()
        onActivateApplication?(app.runningApplication)
        activateRunningApplication(app.runningApplication)
    }

    private func activateWindow(_ window: SwitchableWindow, for app: SwitchableApp) {
        hide()
        onActivateApplication?(app.runningApplication)
        activateRunningApplication(app.runningApplication)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            WindowEnumerator.focusWindow(window, in: app.runningApplication)
            self.activateRunningApplication(app.runningApplication)
        }
    }

    private func activateRunningApplication(_ application: NSRunningApplication) {
        NSApp.yieldActivation(to: application)
        _ = application.activate(from: NSRunningApplication.current, options: [])
    }

    private func hide() {
        removeEventMonitor()
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        suppressHover = false
        onSwitchProfile = nil
        window?.orderOut(nil)
    }
}

private final class SwitcherPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return true
        }
        if Int(event.keyCode) == kVK_Tab {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class SwitcherHostingView<Content: View>: NSHostingView<Content> {
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = .clear
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Int(event.keyCode) == kVK_Escape {
            onEscape?()
            return true
        }
        if Int(event.keyCode) == kVK_Tab {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
