import AppKit
import Carbon.HIToolbox
import CoreGraphics

final class HotKeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionRetryTimer: Timer?
    private let onPressed: () -> Void
    private var shortcut: HotKeyShortcut

    init(
        shortcut: HotKeyShortcut,
        onPressed: @escaping () -> Void
    ) {
        self.onPressed = onPressed
        self.shortcut = shortcut.normalized
        setupEventTap()
    }

    deinit {
        permissionRetryTimer?.invalidate()
        teardownEventTap()
    }

    func update(shortcut: HotKeyShortcut) {
        self.shortcut = shortcut.normalized
    }

    static func ensureAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    private func setupEventTap() {
        guard eventTap == nil else {
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userData -> Unmanaged<CGEvent>? in
                guard let userData else {
                    return Unmanaged.passUnretained(event)
                }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleEvent(type: type, event: event)
            },
            userInfo: userData
        ) else {
            Self.ensureAccessibility()
            schedulePermissionRetry()
            return
        }

        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = ShortcutModifiers(cgEventFlags: event.flags)

        if keyCode == shortcut.keyCode && flags == shortcut.modifiers {
            onPressed()
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private func teardownEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    private func schedulePermissionRetry() {
        guard permissionRetryTimer == nil else {
            return
        }

        permissionRetryTimer = Timer.scheduledTimer(
            timeInterval: 1,
            target: self,
            selector: #selector(retryEventTapAfterPermissionGrant),
            userInfo: nil,
            repeats: true
        )
    }

    @objc
    private func retryEventTapAfterPermissionGrant() {
        guard Self.isAccessibilityGranted else {
            return
        }

        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        setupEventTap()
    }
}
