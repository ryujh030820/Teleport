import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SwitchableApp: Identifiable {
    let runningApplication: NSRunningApplication
    let quickKey: QuickKey
    let isFrontmost: Bool

    var id: String {
        runningApplication.bundleIdentifier ?? "pid-\(runningApplication.processIdentifier)"
    }

    var name: String {
        runningApplication.localizedName ?? "Unknown App"
    }

    var icon: NSImage {
        runningApplication.icon ?? NSImage(size: NSSize(width: 64, height: 64))
    }
}

enum QuickKeyAllocator {
    private static let availableKeys: [QuickKey] = [
        QuickKey(label: "A", keyCode: UInt16(kVK_ANSI_A)),
        QuickKey(label: "S", keyCode: UInt16(kVK_ANSI_S)),
        QuickKey(label: "D", keyCode: UInt16(kVK_ANSI_D)),
        QuickKey(label: "F", keyCode: UInt16(kVK_ANSI_F)),
        QuickKey(label: "G", keyCode: UInt16(kVK_ANSI_G)),
        QuickKey(label: "H", keyCode: UInt16(kVK_ANSI_H)),
        QuickKey(label: "J", keyCode: UInt16(kVK_ANSI_J)),
        QuickKey(label: "K", keyCode: UInt16(kVK_ANSI_K)),
        QuickKey(label: "L", keyCode: UInt16(kVK_ANSI_L)),
        QuickKey(label: "Q", keyCode: UInt16(kVK_ANSI_Q)),
        QuickKey(label: "W", keyCode: UInt16(kVK_ANSI_W)),
        QuickKey(label: "E", keyCode: UInt16(kVK_ANSI_E)),
        QuickKey(label: "R", keyCode: UInt16(kVK_ANSI_R)),
        QuickKey(label: "T", keyCode: UInt16(kVK_ANSI_T)),
        QuickKey(label: "Y", keyCode: UInt16(kVK_ANSI_Y)),
        QuickKey(label: "U", keyCode: UInt16(kVK_ANSI_U)),
        QuickKey(label: "I", keyCode: UInt16(kVK_ANSI_I)),
        QuickKey(label: "O", keyCode: UInt16(kVK_ANSI_O)),
        QuickKey(label: "P", keyCode: UInt16(kVK_ANSI_P)),
        QuickKey(label: "Z", keyCode: UInt16(kVK_ANSI_Z)),
        QuickKey(label: "X", keyCode: UInt16(kVK_ANSI_X)),
        QuickKey(label: "C", keyCode: UInt16(kVK_ANSI_C)),
        QuickKey(label: "V", keyCode: UInt16(kVK_ANSI_V)),
        QuickKey(label: "B", keyCode: UInt16(kVK_ANSI_B)),
        QuickKey(label: "N", keyCode: UInt16(kVK_ANSI_N)),
        QuickKey(label: "M", keyCode: UInt16(kVK_ANSI_M)),
        QuickKey(label: "1", keyCode: UInt16(kVK_ANSI_1)),
        QuickKey(label: "2", keyCode: UInt16(kVK_ANSI_2)),
        QuickKey(label: "3", keyCode: UInt16(kVK_ANSI_3)),
        QuickKey(label: "4", keyCode: UInt16(kVK_ANSI_4)),
        QuickKey(label: "5", keyCode: UInt16(kVK_ANSI_5)),
        QuickKey(label: "6", keyCode: UInt16(kVK_ANSI_6)),
        QuickKey(label: "7", keyCode: UInt16(kVK_ANSI_7)),
        QuickKey(label: "8", keyCode: UInt16(kVK_ANSI_8)),
        QuickKey(label: "9", keyCode: UInt16(kVK_ANSI_9)),
        QuickKey(label: "0", keyCode: UInt16(kVK_ANSI_0))
    ]
    private static let keyLookup = Dictionary(uniqueKeysWithValues: availableKeys.map { ($0.label, $0) })

    static func assignKeys(to apps: [SwitchableApp], customKeys: [String: UInt16] = [:]) -> [SwitchableApp] {
        var usedKeys = Set<UInt16>()

        // Reserve custom keys first
        for app in apps {
            if let customKeyCode = customKeys[app.id],
               let quickKey = availableKeys.first(where: { $0.keyCode == customKeyCode }) {
                usedKeys.insert(quickKey.keyCode)
            }
        }

        return apps.map { app in
            // Use custom key if set
            if let customKeyCode = customKeys[app.id],
               let quickKey = availableKeys.first(where: { $0.keyCode == customKeyCode }) {
                return SwitchableApp(
                    runningApplication: app.runningApplication,
                    quickKey: quickKey,
                    isFrontmost: app.isFrontmost
                )
            }

            let preferredKeys = preferredKeys(for: app.name) + availableKeys
            let assignedKey = preferredKeys.first(where: { usedKeys.insert($0.keyCode).inserted }) ?? QuickKey(label: "?", keyCode: UInt16.max)

            return SwitchableApp(
                runningApplication: app.runningApplication,
                quickKey: assignedKey,
                isFrontmost: app.isFrontmost
            )
        }
    }

    private static func preferredKeys(for name: String) -> [QuickKey] {
        var seen = Set<String>()
        let labels = name
            .uppercased()
            .compactMap { character -> String? in
                guard character.isLetter || character.isNumber else {
                    return nil
                }

                let value = String(character)
                guard seen.insert(value).inserted else {
                    return nil
                }
                return value
            }

        return labels.compactMap { keyLookup[$0] }
    }
}

struct QuickKey: Hashable {
    let label: String
    let keyCode: UInt16
}

struct SwitcherLayout {
    let columns: Int
    let rows: Int
    let itemSize: CGFloat
    let spacing: CGFloat
    let padding: CGFloat
    let headerHeight: CGFloat

    var width: CGFloat {
        let gridWidth = padding * 2 + CGFloat(columns) * itemSize + CGFloat(max(columns - 1, 0)) * spacing
        return max(gridWidth, 360)
    }

    var height: CGFloat {
        padding * 2 + headerHeight + CGFloat(rows) * itemSize + CGFloat(max(rows - 1, 0)) * spacing
    }

    static func make(appCount: Int, visibleFrame: NSRect) -> SwitcherLayout {
        let spacing: CGFloat = 12
        let padding: CGFloat = 16
        let headerHeight: CGFloat = 42
        let minItemSize: CGFloat = 54
        let maxItemSize: CGFloat = 76
        let safeCount = max(appCount, 1)
        let availableWidth = max(visibleFrame.width * 0.9, 420)
        let availableHeight = max(visibleFrame.height * 0.82, 240)
        let maxColumns = max(
            1,
            Int((availableWidth - padding * 2 + spacing) / (minItemSize + spacing))
        )

        var bestLayout = SwitcherLayout(
            columns: min(safeCount, maxColumns),
            rows: Int(ceil(Double(safeCount) / Double(min(safeCount, maxColumns)))),
            itemSize: minItemSize,
            spacing: spacing,
            padding: padding,
            headerHeight: headerHeight
        )

        for columns in stride(from: min(safeCount, maxColumns), through: 1, by: -1) {
            let rows = Int(ceil(Double(safeCount) / Double(columns)))
            let itemWidth = floor((availableWidth - padding * 2 - CGFloat(columns - 1) * spacing) / CGFloat(columns))
            let itemHeight = floor((availableHeight - padding * 2 - headerHeight - CGFloat(rows - 1) * spacing) / CGFloat(rows))
            let candidateSize = min(maxItemSize, itemWidth, itemHeight)

            guard candidateSize >= minItemSize else {
                continue
            }

            bestLayout = SwitcherLayout(
                columns: columns,
                rows: rows,
                itemSize: candidateSize,
                spacing: spacing,
                padding: padding,
                headerHeight: headerHeight
            )
            break
        }

        return bestLayout
    }
}

final class SwitcherViewModel: ObservableObject {
    @Published var apps: [SwitchableApp] = []
    @Published var selectionIndex: Int = 0
    @Published var showProfilePicker = false
    @Published var profilePickerIndex = 0
    @Published var profileName: String = ""
    @Published var selectedAppWindows: [SwitchableWindow] = []
    @Published var windowSelectionIndex: Int = -1
    var profiles: [TeleportProfile] = []
    var currentProfileID: UUID?

    var isInWindowSelection: Bool { windowSelectionIndex >= 0 }

    var hasMultipleWindows: Bool { selectedAppWindows.count >= 2 }

    var selectedApp: SwitchableApp? {
        guard apps.indices.contains(selectionIndex) else {
            return nil
        }
        return apps[selectionIndex]
    }

    var selectedWindow: SwitchableWindow? {
        guard selectedAppWindows.indices.contains(windowSelectionIndex) else {
            return nil
        }
        return selectedAppWindows[windowSelectionIndex]
    }

    func update(snapshot: SwitcherSnapshot) {
        apps = snapshot.apps
        selectionIndex = min(max(snapshot.initialSelectionIndex, 0), max(apps.count - 1, 0))
        selectedAppWindows = []
        windowSelectionIndex = -1
    }

    func switchProfile(snapshot: SwitcherSnapshot) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            apps = snapshot.apps
            selectionIndex = min(max(snapshot.initialSelectionIndex, 0), max(apps.count - 1, 0))
        }
    }

    func moveSelection(forward: Bool) {
        guard !apps.isEmpty else {
            return
        }

        let direction = forward ? 1 : -1
        selectionIndex = (selectionIndex + direction + apps.count) % apps.count
        windowSelectionIndex = -1
    }

    func setSelection(index: Int) {
        guard apps.indices.contains(index) else {
            return
        }

        selectionIndex = index
        windowSelectionIndex = -1
    }

    func selectApp(forKeyCode keyCode: UInt16) -> SwitchableApp? {
        guard let index = apps.firstIndex(where: { $0.quickKey.keyCode == keyCode }) else {
            return nil
        }

        selectionIndex = index
        return apps[index]
    }

    func updateWindows(_ windows: [SwitchableWindow]) {
        selectedAppWindows = windows
        windowSelectionIndex = -1
    }

    func enterWindowSelection() {
        guard hasMultipleWindows else { return }
        windowSelectionIndex = 0
    }

    func exitWindowSelection() {
        windowSelectionIndex = -1
    }

    func moveWindowSelection(forward: Bool) {
        guard !selectedAppWindows.isEmpty else { return }
        if windowSelectionIndex < 0 {
            windowSelectionIndex = forward ? 0 : selectedAppWindows.count - 1
            return
        }
        let direction = forward ? 1 : -1
        windowSelectionIndex = (windowSelectionIndex + direction + selectedAppWindows.count) % selectedAppWindows.count
    }

    func selectWindow(at index: Int) {
        guard selectedAppWindows.indices.contains(index) else { return }
        windowSelectionIndex = index
    }
}

struct SwitcherOverlayView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    let layout: SwitcherLayout
    let backgroundStyle: SwitcherBackgroundStyle
    let onAppTapped: (SwitchableApp) -> Void
    let onAppHovered: (Int) -> Void
    var onWindowTapped: ((SwitchableWindow) -> Void)?
    var onWindowHovered: ((Int) -> Void)?

    /// Clamp offset so the list stays within the panel width.
    private func clampOffset(_ offset: CGFloat, listWidth: CGFloat, panelWidth: CGFloat) -> CGFloat {
        let halfList = listWidth / 2
        let halfPanel = panelWidth / 2
        let minOffset = -halfPanel + halfList
        let maxOffset = halfPanel - halfList
        return min(max(offset, minOffset), maxOffset)
    }

    /// X center of the selected app card relative to the panel's leading edge.
    private var selectedCardCenterX: CGFloat {
        let col = viewModel.selectionIndex % layout.columns
        return layout.padding + CGFloat(col) * (layout.itemSize + layout.spacing) + layout.itemSize / 2
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        if !viewModel.profileName.isEmpty {
                            Text(viewModel.profileName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(0.12))
                                )
                                .foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.profileName)
                        }

                        Spacer()

                        Text(viewModel.selectedApp?.name ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: viewModel.selectedApp?.name)
                    }

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(layout.itemSize), spacing: layout.spacing),
                            count: layout.columns
                        ),
                        alignment: .leading,
                        spacing: layout.spacing
                    ) {
                        ForEach(Array(viewModel.apps.enumerated()), id: \.element.id) { index, app in
                            SwitcherAppCard(
                                app: app,
                                itemSize: layout.itemSize,
                                isSelected: index == viewModel.selectionIndex,
                                onTap: { onAppTapped(app) },
                                onHoverChanged: { isHovering in
                                    guard isHovering else {
                                        return
                                    }

                                    onAppHovered(index)
                                }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        }
                    }
                }
                .padding(layout.padding)
                .frame(width: layout.width, height: layout.height, alignment: .topLeading)
                .modifier(SwitcherBackgroundModifier(style: backgroundStyle))

                if viewModel.showProfilePicker {
                    ProfilePickerView(
                        profiles: viewModel.profiles,
                        currentProfileID: viewModel.currentProfileID,
                        pickerIndex: viewModel.profilePickerIndex
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }

            // 180 = card width (160 + 12 padding + 8 scroll padding)
            let listWidth: CGFloat = 180
            let offsetX = selectedCardCenterX - layout.width / 2

            WindowPreviewList(
                windows: viewModel.selectedAppWindows,
                selectionIndex: viewModel.windowSelectionIndex,
                onWindowTapped: { window in onWindowTapped?(window) },
                onWindowHovered: { index in onWindowHovered?(index) }
            )
            .frame(width: listWidth)
            .offset(x: clampOffset(offsetX, listWidth: listWidth, panelWidth: layout.width))
            .animation(nil, value: offsetX)
            .opacity(viewModel.hasMultipleWindows ? 1 : 0)
            .animation(viewModel.hasMultipleWindows ? .easeOut(duration: 0.15) : nil, value: viewModel.hasMultipleWindows)
        }
    }

}

private struct SwitcherBackgroundModifier: ViewModifier {
    let style: SwitcherBackgroundStyle
    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), style == .glass {
            content
                .glassEffect(.regular, in: shape)
                .compositingGroup()
                .clipShape(shape, style: FillStyle(antialiased: false))
        } else if #available(macOS 26.0, *), style == .clear {
            content
                .glassEffect(.clear, in: shape)
                .compositingGroup()
                .clipShape(shape, style: FillStyle(antialiased: false))
        } else {
            content
                .background(
                    shape
                        .fill(.regularMaterial)
                        .overlay(
                            shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        )
                )
                .shadow(
                    color: Color(red: 0.25, green: 0.32, blue: 0.38).opacity(0.25),
                    radius: 30,
                    y: 20
                )
                .compositingGroup()
                .clipShape(shape, style: FillStyle(antialiased: false))
        }
    }
}

struct SwitcherAppCard: View {
    let app: SwitchableApp
    let itemSize: CGFloat
    let isSelected: Bool
    let onTap: () -> Void
    let onHoverChanged: (Bool) -> Void
    @State private var isHovered = false
    private let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    private let iconShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    iconShape
                        .fill(Color.white.opacity(0.04))

                    Image(nsImage: app.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: itemSize * 0.80, height: itemSize * 0.80)
                }
                .frame(width: itemSize * 0.80, height: itemSize * 0.80)
                .compositingGroup()
                .clipShape(iconShape, style: FillStyle(antialiased: true))

                Text(app.quickKey.label)
                    .font(.system(size: max(itemSize * 0.16, 11), weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(isSelected || isHovered ? 0.22 : 0.14))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .offset(x: 4, y: -4)
            }
            .frame(width: itemSize, height: itemSize)
            .background(
                cardShape
                    .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.black.opacity(isHovered ? 0.16 : 0.10))
            )
            .overlay(
                cardShape
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(cardShape, style: FillStyle(antialiased: true))
            .contentShape(cardShape)
            .background(
                cardShape
                    .fill(Color.cyan)
                    .blur(radius: 24)
                    .opacity(isSelected ? 0.8 : 0)
            )
            .background(
                cardShape
                    .fill(Color.cyan.opacity(0.5))
                    .blur(radius: 48)
                    .scaleEffect(1.3)
                    .opacity(isSelected ? 0.6 : 0)
            )
            .compositingGroup()
            .scaleEffect(isSelected || isHovered ? 1.04 : 1.0)
        }
        .buttonStyle(.plain)
        .help(app.name)
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isSelected)
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isHovered)
    }
}

struct WindowPreviewList: View {
    let windows: [SwitchableWindow]
    let selectionIndex: Int
    let onWindowTapped: (SwitchableWindow) -> Void
    let onWindowHovered: (Int) -> Void

    static let maxVisibleCards = 3
    static let cardHeight: CGFloat = 110
    static let spacing: CGFloat = 5

    private var needsScroll: Bool { windows.count > Self.maxVisibleCards }
    // With center-anchor scrolling and 3 visible slots:
    // first item scrolls out when selectionIndex >= 2, last item scrolls out when selectionIndex <= count - 3
    private var hasScrollUp: Bool { needsScroll && selectionIndex >= Self.maxVisibleCards - 1 }
    private var hasScrollDown: Bool { needsScroll && selectionIndex <= windows.count - Self.maxVisibleCards }

    private var listHeight: CGFloat {
        let count = CGFloat(min(windows.count, Self.maxVisibleCards))
        return count * Self.cardHeight + max(count - 1, 0) * Self.spacing
    }

    var body: some View {
        VStack(spacing: 4) {
            if needsScroll {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(hasScrollUp ? 1 : 0)
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Self.spacing) {
                        ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                            WindowPreviewCard(
                                window: window,
                                index: index,
                                isSelected: index == selectionIndex,
                                onTap: { onWindowTapped(window) },
                                onHover: { onWindowHovered(index) }
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: listHeight)
                .onChange(of: selectionIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }

            if needsScroll {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .opacity(hasScrollDown ? 1 : 0)
                    .foregroundStyle(.secondary)
                    .frame(height: 12)
            }
        }
    }
}

private struct WindowPreviewCard: View {
    let window: SwitchableWindow
    let index: Int
    let isSelected: Bool
    let onTap: () -> Void
    let onHover: () -> Void
    @State private var isHovered = false
    private let cardShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    private let thumbShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    if let thumbnail = window.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 160, alignment: .center)
                            .frame(maxHeight: 80)
                            .clipShape(thumbShape)
                            .transition(.opacity)
                    } else {
                        SkeletonView()
                            .frame(width: 160, height: 80)
                            .clipShape(thumbShape)
                            .transition(.opacity)
                    }

                    Text("\(index + 1)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1.5)
                        .background(Capsule(style: .continuous).fill(Color.black.opacity(0.55)))
                        .foregroundStyle(.white)
                        .padding(3)
                }
                .animation(.easeIn(duration: 0.25), value: window.thumbnail != nil)

                Text(window.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 148, alignment: .leading)
            }
            .padding(6)
            .background(
                cardShape
                    .fill(.ultraThinMaterial)
            )
            .background(
                cardShape
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
            )
            .overlay(
                cardShape
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 8, y: 4)
            .compositingGroup()
            .clipShape(cardShape, style: FillStyle(antialiased: false))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { onHover() }
        }
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: isSelected)
    }
}

private struct SkeletonView: View {
    @State private var shimmerOffset: CGFloat = -1

    var body: some View {
        Color.white.opacity(0.06)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.08), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .scaleEffect(x: 0.5)
                .offset(x: shimmerOffset * 160)
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1
                }
            }
    }
}

struct ProfilePickerView: View {
    let profiles: [TeleportProfile]
    let currentProfileID: UUID?
    let pickerIndex: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("Switch Profile")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                HStack(spacing: 10) {
                    Text(profile.name)
                        .font(.system(size: 14, weight: index == pickerIndex ? .semibold : .regular))
                        .lineLimit(1)

                    Spacer()

                    if profile.id == currentProfileID {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(index == pickerIndex ? Color.accentColor.opacity(0.25) : Color.clear)
                )
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.3), radius: 20, y: 10)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous), style: FillStyle(antialiased: false))
    }
}
