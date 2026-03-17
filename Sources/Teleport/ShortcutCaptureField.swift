import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutCaptureField: View {
    let title: String
    let value: String
    let placeholder: String
    let allowsModifiers: Bool
    let onCaptureShortcut: ((HotKeyShortcut) -> Void)?
    let onCaptureKeyCode: ((UInt16?) -> Void)?

    @State private var isFocused = false
    @State private var isHovered = false

    var body: some View {
        ShortcutCaptureFieldRepresentable(
            value: value,
            placeholder: placeholder,
            title: title,
            allowsModifiers: allowsModifiers,
            onCaptureShortcut: onCaptureShortcut,
            onCaptureKeyCode: onCaptureKeyCode,
            onFocusChange: { isFocused = $0 }
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocused 
                        ? Color.accentColor.opacity(0.12) 
                        : (isHovered ? Color.primary.opacity(0.06) : Color(nsColor: .controlBackgroundColor)))
                
                if isFocused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .blur(radius: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                }
            }
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.spring(duration: 0.2), value: isFocused)
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .help(title)
    }
}

private struct ShortcutCaptureFieldRepresentable: NSViewRepresentable {
    let value: String
    let placeholder: String
    let title: String
    let allowsModifiers: Bool
    let onCaptureShortcut: ((HotKeyShortcut) -> Void)?
    let onCaptureKeyCode: ((UInt16?) -> Void)?
    let onFocusChange: (Bool) -> Void

    func makeNSView(context: Context) -> CaptureTextField {
        let textField = CaptureTextField()
        textField.placeholderString = placeholder
        textField.captureHandler = { event in
            let modifiers = ShortcutModifiers(eventModifiers: event.modifierFlags)

            if allowsModifiers {
                guard !modifiers.isEmpty else {
                    NSSound.beep()
                    return
                }

                onCaptureShortcut?(
                    HotKeyShortcut(
                        keyCode: UInt32(event.keyCode),
                        modifiers: modifiers
                    )
                )
                return
            }

            onCaptureKeyCode?(UInt16(event.keyCode))
        }
        textField.clearHandler = {
            onCaptureKeyCode?(nil)
        }
        textField.focusChangeHandler = onFocusChange
        return textField
    }

    func updateNSView(_ nsView: CaptureTextField, context: Context) {
        nsView.stringValue = value
        nsView.placeholderString = placeholder
        nsView.toolTip = title
        nsView.focusChangeHandler = onFocusChange
    }
}

final class CaptureTextField: NSTextField {
    var captureHandler: ((NSEvent) -> Void)?
    var clearHandler: (() -> Void)?
    var focusChangeHandler: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    override var acceptsFirstResponder: Bool { true }

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        lineBreakMode = .byTruncatingTail
        alignment = .center
        if let descriptor = NSFont.systemFont(ofSize: 13, weight: .bold).fontDescriptor.withDesign(.rounded) {
            font = NSFont(descriptor: descriptor, size: 13)
        } else {
            font = .systemFont(ofSize: 13, weight: .bold)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            installEventTap()
            focusChangeHandler?(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        removeEventTap()
        focusChangeHandler?(false)
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventTap()
        }
    }

    override func keyDown(with event: NSEvent) {
        handleCapturedKey(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        handleCapturedKey(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        return true
    }

    private func handleCapturedKey(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        switch Int(keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            clearHandler?()
            window?.makeFirstResponder(nil)
        default:
            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window?.windowNumber ?? 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
            if let event {
                captureHandler?(event)
            }
            window?.makeFirstResponder(nil)
        }
    }

    private func installEventTap() {
        removeEventTap()

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

                let field = Unmanaged<CaptureTextField>.fromOpaque(userData).takeUnretainedValue()
                return field.handleTapEvent(type: type, event: event)
            },
            userInfo: userData
        ) else {
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))

        DispatchQueue.main.async { [weak self] in
            self?.handleCapturedKey(keyCode: keyCode, modifierFlags: flags)
        }

        return nil
    }

    private func removeEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }
}
