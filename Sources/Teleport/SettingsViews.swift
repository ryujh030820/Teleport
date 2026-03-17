import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let onBrowseApplications: () -> Void
    let onCheckForUpdates: () -> Void

    @State private var selectedApplicationID: String?
    @State private var pendingRemoveBundleID: String?
    @State private var showDeleteProfileAlert = false
    @State private var navigationSelection: String? = "profile"

    private var activeProfile: TeleportProfile {
        store.activeProfile
    }

    private var unmanagedRunningApplications: [ManagedApplication] {
        let managedBundleIdentifiers = Set(activeProfile.applications.map(\.bundleIdentifier))
        return store.runningApplications.filter { !managedBundleIdentifiers.contains($0.bundleIdentifier) }
    }

    var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        // Settings section
                        SidebarRow(
                            title: "General",
                            icon: "gearshape.fill",
                            iconColor: Color(red: 0.68, green: 0.68, blue: 0.70),
                            isSelected: navigationSelection == "profile"
                        ) { navigationSelection = "profile" }

                        // Spacer + section header
                        SidebarSectionHeader("Settings")

                        SidebarRow(
                            title: "Hotkeys",
                            icon: "keyboard.fill",
                            iconColor: Color(red: 247/255, green: 150/255, blue: 109/255),
                            isSelected: navigationSelection == "shortcut"
                        ) { navigationSelection = "shortcut" }

                        SidebarRow(
                            title: "Appearance",
                            icon: "paintbrush.fill",
                            iconColor: Color(red: 58/255, green: 199/255, blue: 145/255),
                            isSelected: navigationSelection == "appearance"
                        ) { navigationSelection = "appearance" }

                        SidebarRow(
                            title: "Applications",
                            icon: "square.grid.2x2.fill",
                            iconColor: Color(red: 119/255, green: 122/255, blue: 255/255),
                            isSelected: navigationSelection == "apps"
                        ) { navigationSelection = "apps" }

                        // Profiles section
                        SidebarSectionHeader("Profiles") {
                            Button {
                                store.createProfile()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(store.profiles) { profile in
                            let isActive = profile.id == activeProfile.id
                            SidebarProfileRow(
                                title: profile.name,
                                isSelected: isActive && navigationSelection == "profile",
                                isDefault: profile.id == store.settings.defaultProfileID
                            ) {
                                withAnimation(.spring(duration: 0.3)) {
                                    store.activateProfile(id: profile.id)
                                    navigationSelection = "profile"
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer()

                // Sidebar Footer
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Teleport")
                                .font(.headline)
                            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Update") {
                            onCheckForUpdates()
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 270)
        } detail: {
            // MARK: - Detail Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerView
                    
                    Group {
                        switch navigationSelection {
                        case "profile":
                            profileDetailView
                        case "shortcut":
                            shortcutDetailView
                        case "appearance":
                            appearanceDetailView
                        case "apps":
                            appsDetailView
                        default:
                            profileDetailView
                        }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                           removal: .opacity))
                }
                .padding(32)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle(detailTitle)
        }
        .frame(minWidth: 900, minHeight: 650)
    }

    private var detailTitle: String {
        switch navigationSelection {
        case "profile": return "General Settings"
        case "shortcut": return "Hotkeys"
        case "appearance": return "Appearance"
        case "apps": return "Applications"
        default: return "Settings"
        }
    }

    // MARK: - Detail Header
    
    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: iconNameForSelection)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)], 
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(detailTitle)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                
                Text(detailDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.bottom, 8)
    }
    
    private var iconNameForSelection: String {
        switch navigationSelection {
        case "profile": return "person.crop.circle"
        case "shortcut": return "keyboard"
        case "appearance": return "paintbrush"
        case "apps": return "square.grid.2x2"
        default: return "gearshape"
        }
    }
    
    private var detailDescription: String {
        switch navigationSelection {
        case "profile": return "Configure the current profile name and switch behavior."
        case "shortcut": return "Set global shortcuts to invoke Teleport."
        case "appearance": return "Customize how Teleport looks on your screen."
        case "apps": return "Manage which applications are visible in this profile."
        default: return ""
        }
    }

    // MARK: - Profile Detail

    private var profileDetailView: some View {
        VStack(spacing: 24) {
            SettingsCard {
                VStack(spacing: 20) {
                    Form {
                        TextField("Profile Name", text: Binding(
                            get: { activeProfile.name },
                            set: { store.renameActiveProfile($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        
                        Toggle("Default Profile", isOn: Binding(
                            get: { activeProfile.id == store.settings.defaultProfileID },
                            set: { if $0 { store.setDefaultProfile(id: activeProfile.id) } }
                        ))
                        .disabled(activeProfile.id == store.settings.defaultProfileID)
                    }
                }
            }
            
            SettingsCard(title: "Profile Switch Key", icon: "key.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ShortcutCaptureField(
                            title: "Switch Key",
                            value: activeProfile.profileSwitchKeyDisplayText,
                            placeholder: "Not set",
                            allowsModifiers: false,
                            onCaptureShortcut: nil,
                            onCaptureKeyCode: { store.setActiveProfileSwitchKey($0) }
                        )
                        .frame(width: 140)

                        if activeProfile.profileSwitchKeyCode != nil {
                            Button {
                                store.setActiveProfileSwitchKey(nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Text("Directly switch to this profile by pressing this key while Teleport is open.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if store.profiles.count > 1 {
                Button(role: .destructive) {
                    showDeleteProfileAlert = true
                } label: {
                    Label("Delete Profile", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .confirmationDialog("Delete Profile?", isPresented: $showDeleteProfileAlert) {
                    Button("Delete \"\(activeProfile.name)\"", role: .destructive) {
                        store.deleteActiveProfile()
                    }
                } message: {
                    Text("This action cannot be undone.")
                }
            }
        }
    }

    // MARK: - Shortcut Detail

    private var shortcutDetailView: some View {
        SettingsCard(title: "Global Hotkey", icon: "command") {
            VStack(alignment: .leading, spacing: 16) {
                ShortcutCaptureField(
                    title: "Main Shortcut",
                    value: store.settings.hotKey.displayText,
                    placeholder: "Set Hotkey",
                    allowsModifiers: true,
                    onCaptureShortcut: { store.setHotKey($0) },
                    onCaptureKeyCode: nil
                )
                .frame(width: 220)
                
                Text("Use this shortcut to bring up Teleport from anywhere. Requires at least one modifier key (⌘, ⌥, ⌃, or ⇧).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Appearance Detail

    private var appearanceDetailView: some View {
        SettingsCard(title: "Background Style", icon: "square.2.layers.3d") {
            VStack(spacing: 24) {
                Picker("Style", selection: Binding(
                    get: { store.settings.backgroundStyle },
                    set: { store.setBackgroundStyle($0) }
                )) {
                    ForEach(SwitcherBackgroundStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)
                
                HStack(spacing: 24) {
                    ForEach(SwitcherBackgroundStyle.allCases) { style in
                        BackgroundPreviewCard(
                            style: style,
                            isSelected: style == store.settings.backgroundStyle
                        )
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.3)) {
                                store.setBackgroundStyle(style)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Apps Detail

    private var appsDetailView: some View {
        VStack(spacing: 24) {
            SettingsCard(title: "Filter Mode", icon: "line.3.horizontal.decrease.circle") {
                VStack(spacing: 16) {
                    Picker("Mode", selection: Binding(
                        get: { activeProfile.filterMode },
                        set: { store.setActiveProfileFilterMode($0) }
                    )) {
                        ForEach(AppFilterMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    
                    Text(filterModeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Running Applications", systemImage: "apps.iphone")
                        .font(.headline)
                    Spacer()
                    Text("\(unmanagedRunningApplications.count) available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if unmanagedRunningApplications.isEmpty {
                    Text("All running apps are already in this profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                        ForEach(unmanagedRunningApplications) { application in
                            RunningAppButton(application: application) {
                                withAnimation(.spring(duration: 0.2)) {
                                    store.includeRunningApplication(bundleIdentifier: application.bundleIdentifier)
                                }
                            }
                        }
                    }
                }
                
                Button {
                    onBrowseApplications()
                } label: {
                    Label("Browse App Bundle…", systemImage: "plus.viewfinder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Label("Managed Applications", systemImage: "list.bullet.indent")
                    .font(.headline)
                
                managedApplicationsList
            }
        }
    }

    private var managedApplicationsList: some View {
        Group {
            if activeProfile.applications.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No apps managed in this profile")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5]))
                )
            } else {
                VStack(spacing: 1) {
                    ForEach(activeProfile.applications) { application in
                        ManagedApplicationRow(
                            application: resolvedApplication(for: application),
                            isRunning: store.runningApplications.contains(where: { $0.bundleIdentifier == application.bundleIdentifier }),
                            isSelected: selectedApplicationID == application.bundleIdentifier,
                            onToggleSelection: {
                                withAnimation(.spring(duration: 0.2)) {
                                    if selectedApplicationID == application.bundleIdentifier {
                                        selectedApplicationID = nil
                                    } else {
                                        selectedApplicationID = application.bundleIdentifier
                                    }
                                }
                            },
                            onRemove: {
                                pendingRemoveBundleID = application.bundleIdentifier
                            },
                            onSetQuickKey: { keyCode in
                                store.setApplicationQuickKey(bundleIdentifier: application.bundleIdentifier, keyCode: keyCode)
                            }
                        )
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            }
        }
        .alert(
            "Remove Application?",
            isPresented: Binding(
                get: { pendingRemoveBundleID != nil },
                set: { if !$0 { pendingRemoveBundleID = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let id = pendingRemoveBundleID {
                    store.removeApplications(bundleIdentifiers: [id])
                    if selectedApplicationID == id {
                        selectedApplicationID = nil
                    }
                }
                pendingRemoveBundleID = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let id = pendingRemoveBundleID,
               let app = activeProfile.applications.first(where: { $0.bundleIdentifier == id }) {
                Text("Are you sure you want to remove \"\(app.displayName)\" from this profile?")
            }
        }
    }

    private var filterModeDescription: String {
        switch activeProfile.filterMode {
        case .all: return "All running apps will appear in Teleport."
        case .include: return "Only the apps listed below will appear in Teleport."
        case .exclude: return "All running apps will appear except the ones listed below."
        }
    }

    private func resolvedApplication(for application: ManagedApplication) -> ManagedApplication {
        guard let running = store.runningApplications.first(where: { $0.bundleIdentifier == application.bundleIdentifier }) else {
            return application
        }
        var resolved = running
        resolved.customQuickKeyCode = application.customQuickKeyCode
        return resolved
    }
}

// MARK: - Refined Components

private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                HStack(spacing: 8) {
                    if let icon {
                        Image(systemName: icon)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(title)
                        .font(.headline)
                }
            }
            
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }
}

private struct BackgroundPreviewCard: View {
    let style: SwitcherBackgroundStyle
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // Desktop wallpaper simulation
                LinearGradient(
                    colors: [
                        Color(red: 0.4, green: 0.7, blue: 1.0), // 산뜻한 하늘색
                        Color(red: 0.5, green: 0.5, blue: 1.0), // 부드러운 보라색
                        Color(red: 0.8, green: 0.6, blue: 0.9)  // 연한 핑크/라벤더
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Panel preview
                Group {
                    switch style {
                    case .glass:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2), lineWidth: 0.5))
                    case .clear:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.black.opacity(0.2))
                    case .frosted:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                    }
                }
                .frame(width: 50, height: 34)
                .shadow(radius: 4)
            }
            .frame(width: 100, height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: 8)

            Text(style.title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct RunningAppButton: View {
    let application: ManagedApplication
    let action: () -> Void
    @State private var isHovered = false
    @State private var hoverCount = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppIconView(path: application.appPath, size: 28)
                Text(application.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: hoverCount)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { hoverCount += 1 }
        }
    }
}

private struct ManagedApplicationRow: View {
    let application: ManagedApplication
    let isRunning: Bool
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onRemove: () -> Void
    let onSetQuickKey: (UInt16?) -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                AppIconView(path: application.appPath, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(application.displayName)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isRunning ? Color.green : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                        Text(isRunning ? "Running" : "Idle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleSelection)

            if isSelected {
                HStack(spacing: 12) {
                    ShortcutCaptureField(
                        title: "Key",
                        value: application.customQuickKeyDisplayText,
                        placeholder: "Auto",
                        allowsModifiers: false,
                        onCaptureShortcut: nil,
                        onCaptureKeyCode: { onSetQuickKey($0) }
                    )
                    .frame(width: 70)

                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        Divider().padding(.leading, 60).opacity(0.3)
    }
}

private struct AppIconView: View {
    let path: String?
    var size: CGFloat = 32

    var body: some View {
        if let path, !path.isEmpty {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: size, height: size)
                .shadow(radius: 2)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sidebar Components

private struct SidebarRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    let isSelected: Bool
    var badge: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(iconColor.gradient)
                    )

                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()

                if let badge {
                    Image(systemName: badge)
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct SidebarProfileRow: View {
    let title: String
    let isSelected: Bool
    let isDefault: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)

                Spacer()

                if isDefault {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.05) : .clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct SidebarSectionHeader<Trailing: View>: View {
    let title: String
    let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

extension SidebarSectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}
