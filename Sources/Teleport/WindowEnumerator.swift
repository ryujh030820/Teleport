import AppKit
import CoreGraphics
import Darwin

struct SwitchableWindow: Identifiable, @unchecked Sendable {
    let windowID: CGWindowID?
    let axElement: AXUIElement?
    let title: String
    let bounds: CGRect?
    var thumbnail: NSImage?
    let index: Int
    let pid: pid_t

    var id: Int { index }
}

enum WindowEnumerator {
    /// Fast enumeration — no thumbnail capture.
    static func windows(for app: NSRunningApplication) -> [SwitchableWindow] {
        let pid = app.processIdentifier
        let axWindows = filteredAXWindows(buildAXWindowList(pid: pid, appName: app.localizedName))
        let cgWindows = buildCGWindowList(pid: pid)

        if axWindows.isEmpty {
            // When falling back to CG-only, filter out unnamed helper windows
            // if named ones exist.
            let hasNamedWindows = cgWindows.contains { $0.name != nil }
            let filtered = hasNamedWindows
                ? cgWindows.filter { $0.name != nil }
                : cgWindows
            return filtered.enumerated().map { index, cgWindow in
                SwitchableWindow(
                    windowID: cgWindow.id,
                    axElement: nil,
                    title: cgWindow.name ?? app.localizedName ?? "Window \(index + 1)",
                    bounds: cgWindow.bounds,
                    thumbnail: nil,
                    index: index,
                    pid: pid
                )
            }
        }

        var windows: [SwitchableWindow] = []
        var usedCGIDs = Set<CGWindowID>()
        var index = 0

        for axWindow in axWindows {
            let match = cgWindows.first { cgWindow in
                guard !usedCGIDs.contains(cgWindow.id) else {
                    return false
                }
                if let axWindowID = axWindow.windowID {
                    return axWindowID == cgWindow.id
                }
                guard let bounds = axWindow.bounds else {
                    return false
                }
                if let cgName = cgWindow.name,
                   cgName == axWindow.title,
                   boundsMatch(bounds, cgWindow.bounds) {
                    return true
                }
                return boundsMatch(bounds, cgWindow.bounds)
            }

            if let match {
                usedCGIDs.insert(match.id)
            }

            windows.append(SwitchableWindow(
                windowID: match?.id,
                axElement: axWindow.element,
                title: axWindow.title,
                bounds: axWindow.bounds ?? match?.bounds,
                thumbnail: nil,
                index: index,
                pid: pid
            ))
            index += 1
        }

        if axWindows.contains(where: \.isFullScreen) {
            return windows
        }

        // If AX missed some windows, append the remaining CG windows so the list is still usable.
        for cgWindow in cgWindows where !usedCGIDs.contains(cgWindow.id) {
            guard shouldIncludeFallbackCGWindow(cgWindow, appName: app.localizedName, existingAXWindows: axWindows) else {
                continue
            }

            // Validate fallback-only windows with an actual capture so helper/empty windows do not pollute the list.
            let fallbackThumbnail = captureThumbnail(windowID: cgWindow.id)
            guard fallbackThumbnail != nil else {
                continue
            }

            windows.append(SwitchableWindow(
                windowID: cgWindow.id,
                axElement: nil,
                title: cgWindow.name ?? app.localizedName ?? "Window \(index + 1)",
                bounds: cgWindow.bounds,
                thumbnail: fallbackThumbnail,
                index: index,
                pid: pid
            ))
            index += 1
        }

        return windows
    }

    /// Capture thumbnails for already-enumerated windows (can be slow).
    static func withThumbnails(_ windows: [SwitchableWindow]) -> [SwitchableWindow] {
        windows.map { window in
            guard let windowID = window.windowID else { return window }
            var copy = window
            copy.thumbnail = captureThumbnail(windowID: windowID)
            return copy
        }
    }

    static func focusWindow(_ window: SwitchableWindow, in app: NSRunningApplication) {
        if let axElement = resolvedAXWindow(for: window, pid: app.processIdentifier) ?? window.axElement {
            makeWindowFront(axElement)
            return
        }

        if let windowID = window.windowID {
            _ = CGWindowListCreateDescriptionFromArray([windowID] as CFArray)
        }
    }

    // MARK: - CG Window Matching

    private struct CGWindowInfo {
        let id: CGWindowID
        let bounds: CGRect
        let name: String?
    }

    private struct AXWindowInfo {
        let element: AXUIElement
        let windowID: CGWindowID?
        let bounds: CGRect?
        let title: String
        let hasExplicitTitle: Bool
        let isFullScreen: Bool
    }

    private static func buildAXWindowList(pid: pid_t, appName: String?) -> [AXWindowInfo] {
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXWindowsAttribute as CFString, &windowsRef
        ) == .success,
            let axWindows = windowsRef as? [AXUIElement]
        else {
            return []
        }

        return axWindows.compactMap { axWindow in
            var roleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleRef)
            let role = roleRef as? String
            if role != nil && role != "AXWindow" { return nil }

            var subroleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = subroleRef as? String
            if let subrole, subrole != "AXStandardWindow" && subrole != "AXDialog" { return nil }

            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedRef)
            if let minimized = minimizedRef as? Bool, minimized {
                return nil
            }

            let bounds = getAXWindowBounds(axWindow)
            if let bounds, bounds.width < 50 || bounds.height < 50 {
                return nil
            }

            let windowID = cgWindowID(for: axWindow)

            var fullScreenRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, "AXFullScreen" as CFString, &fullScreenRef)
            let isFullScreen = fullScreenRef as? Bool ?? false

            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            let rawTitle = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if rawTitle.isEmpty && windowID == nil {
                return nil
            }

            let title = rawTitle.isEmpty ? (appName ?? "Window") : rawTitle
            return AXWindowInfo(
                element: axWindow,
                windowID: windowID,
                bounds: bounds,
                title: title,
                hasExplicitTitle: !rawTitle.isEmpty,
                isFullScreen: isFullScreen
            )
        }
    }

    private static func filteredAXWindows(_ windows: [AXWindowInfo]) -> [AXWindowInfo] {
        guard windows.count > 1 else { return windows }

        let hasExplicitlyTitledWindows = windows.contains(where: \.hasExplicitTitle)

        if hasExplicitlyTitledWindows {
            // Remove untitled phantom windows when titled ones exist.
            let filtered = windows.filter(\.hasExplicitTitle)
            return filtered.isEmpty ? windows : filtered
        }

        // All windows are untitled — common for fullscreen apps that report a phantom helper.
        // Keep only the fullscreen one(s), or if none are fullscreen, the largest by area.
        let fullScreenWindows = windows.filter(\.isFullScreen)
        if !fullScreenWindows.isEmpty {
            return fullScreenWindows
        }

        // No fullscreen flag — keep only the largest window (likely the real one).
        if let largest = windows.max(by: {
            ($0.bounds?.width ?? 0) * ($0.bounds?.height ?? 0) <
            ($1.bounds?.width ?? 0) * ($1.bounds?.height ?? 0)
        }) {
            // Only deduplicate if windows share the same fallback title (app name).
            let allSameTitle = windows.allSatisfy { $0.title == windows.first?.title }
            if allSameTitle {
                return [largest]
            }
        }

        return windows
    }

    private static func buildCGWindowList(pid: pid_t) -> [CGWindowInfo] {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var results: [CGWindowInfo] = []
        for info in infoList {
            guard
                let windowPID = info[kCGWindowOwnerPID as String] as? pid_t,
                windowPID == pid,
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                (info[kCGWindowAlpha as String] as? CGFloat ?? 1) > 0,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let x = boundsDict["X"] as? CGFloat,
                let y = boundsDict["Y"] as? CGFloat,
                let w = boundsDict["Width"] as? CGFloat,
                let h = boundsDict["Height"] as? CGFloat
            else {
                continue
            }
            guard w >= 50, h >= 50 else { continue }
            let name = info[kCGWindowName as String] as? String
            results.append(CGWindowInfo(
                id: windowID,
                bounds: CGRect(x: x, y: y, width: w, height: h),
                name: name?.isEmpty == true ? nil : name
            ))
        }
        return results
    }

    private static func getAXWindowBounds(_ axWindow: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posRef) == .success,
            AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef) == .success
        else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(posRef as! AXValue, .cgPoint, &position),
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func boundsMatch(_ ax: CGRect, _ cg: CGRect) -> Bool {
        abs(ax.origin.x - cg.origin.x) < 2 &&
        abs(ax.origin.y - cg.origin.y) < 2 &&
        abs(ax.width - cg.width) < 2 &&
        abs(ax.height - cg.height) < 2
    }

    private static func shouldIncludeFallbackCGWindow(
        _ cgWindow: CGWindowInfo,
        appName: String?,
        existingAXWindows: [AXWindowInfo]
    ) -> Bool {
        guard !existingAXWindows.isEmpty else { return true }

        if let name = cgWindow.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            if let appName, name == appName {
                return false
            }

            let duplicatesAXTitle = existingAXWindows.contains { $0.title == name }
            if duplicatesAXTitle {
                return false
            }

            return true
        }

        return false
    }

    private static func resolvedAXWindow(for window: SwitchableWindow, pid: pid_t) -> AXUIElement? {
        let axWindows = buildAXWindowList(pid: pid, appName: nil)

        if let original = window.axElement {
            for candidate in axWindows where CFEqual(candidate.element, original) {
                return candidate.element
            }
        }

        if let windowID = window.windowID,
           let exactID = axWindows.first(where: { $0.windowID == windowID }) {
            return exactID.element
        }

        if let bounds = window.bounds {
            if let exactTitleAndBounds = axWindows.first(where: { candidate in
                candidate.title == window.title && candidate.bounds.map { boundsMatch($0, bounds) } == true
            }) {
                return exactTitleAndBounds.element
            }

            if let exactBounds = axWindows.first(where: { candidate in
                candidate.bounds.map { boundsMatch($0, bounds) } == true
            }) {
                return exactBounds.element
            }
        }

        if let exactTitle = axWindows.first(where: { $0.title == window.title }) {
            return exactTitle.element
        }

        return nil
    }

    private static func makeWindowFront(_ axElement: AXUIElement) {
        let falseValue: CFTypeRef = kCFBooleanFalse
        AXUIElementSetAttributeValue(axElement, kAXMinimizedAttribute as CFString, falseValue)
        AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axElement, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private typealias AXUIElementGetWindowFunc =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let axUIElementGetWindow: AXUIElementGetWindowFunc? = {
        let handles = [
            dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
            dlopen("/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices", RTLD_LAZY),
            dlopen(nil, RTLD_LAZY)
        ]

        for handle in handles.compactMap({ $0 }) {
            for symbol in ["AXUIElementGetWindow", "_AXUIElementGetWindow"] {
                if let function = dlsym(handle, symbol) {
                    return unsafeBitCast(function, to: AXUIElementGetWindowFunc.self)
                }
            }
        }

        return nil
    }()

    private static func cgWindowID(for axWindow: AXUIElement) -> CGWindowID? {
        guard let axUIElementGetWindow else { return nil }
        var windowID: CGWindowID = 0
        let error = axUIElementGetWindow(axWindow, &windowID)
        guard error == .success, windowID != 0 else { return nil }
        return windowID
    }

    // MARK: - Thumbnail

    private static func captureThumbnail(windowID: CGWindowID) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        guard cgImage.width > 1 && cgImage.height > 1 else { return nil }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
