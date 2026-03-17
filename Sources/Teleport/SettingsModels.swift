import AppKit
import Carbon.HIToolbox
import Combine

enum SwitcherBackgroundStyle: String, CaseIterable, Codable, Identifiable {
    case glass
    case clear
    case frosted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass:
            return "Glass"
        case .clear:
            return "Clear"
        case .frosted:
            return "Frosted"
        }
    }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let option = ShortcutModifiers(rawValue: 1 << 1)
    static let control = ShortcutModifiers(rawValue: 1 << 2)
    static let shift = ShortcutModifiers(rawValue: 1 << 3)

    static let `default`: ShortcutModifiers = [.command]

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(cgEventFlags flags: CGEventFlags) {
        var modifiers: ShortcutModifiers = []

        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }

        self = modifiers
    }

    init(eventModifiers: NSEvent.ModifierFlags) {
        var modifiers: ShortcutModifiers = []

        if eventModifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if eventModifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if eventModifiers.contains(.control) {
            modifiers.insert(.control)
        }
        if eventModifiers.contains(.shift) {
            modifiers.insert(.shift)
        }

        self = modifiers
    }

    var normalized: ShortcutModifiers {
        isEmpty ? .default : self
    }

    var carbonValue: UInt32 {
        var value: UInt32 = 0

        if contains(.command) {
            value |= UInt32(cmdKey)
        }
        if contains(.option) {
            value |= UInt32(optionKey)
        }
        if contains(.control) {
            value |= UInt32(controlKey)
        }
        if contains(.shift) {
            value |= UInt32(shiftKey)
        }

        return value
    }

    var eventModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []

        if contains(.command) {
            flags.insert(.command)
        }
        if contains(.option) {
            flags.insert(.option)
        }
        if contains(.control) {
            flags.insert(.control)
        }
        if contains(.shift) {
            flags.insert(.shift)
        }

        return flags
    }

    var displayText: String {
        let labels = [
            contains(.command) ? "Command" : nil,
            contains(.option) ? "Option" : nil,
            contains(.control) ? "Control" : nil,
            contains(.shift) ? "Shift" : nil
        ]
        .compactMap { $0 }

        return labels.joined(separator: "+")
    }
}

struct HotKeyShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: ShortcutModifiers

    static let `default` = HotKeyShortcut(
        keyCode: UInt32(kVK_Tab),
        modifiers: .default
    )

    var normalized: HotKeyShortcut {
        HotKeyShortcut(keyCode: keyCode, modifiers: modifiers.normalized)
    }

    var displayText: String {
        let modifierText = normalized.modifiers.displayText
        let keyText = KeyCodeCatalog.label(for: UInt16(keyCode))

        if modifierText.isEmpty {
            return keyText
        }

        return "\(modifierText)+\(keyText)"
    }
}

struct HotKeyChoice: Identifiable, Hashable {
    let keyCode: UInt32
    let label: String

    var id: UInt32 { keyCode }
}

enum KeyCodeCatalog {
    static let profilePickerKeyCode = UInt16(kVK_ANSI_Grave)

    private static let labels: [UInt16: String] = [
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_Escape): "Escape",
        UInt16(kVK_LeftArrow): "Left Arrow",
        UInt16(kVK_RightArrow): "Right Arrow",
        UInt16(kVK_UpArrow): "Up Arrow",
        UInt16(kVK_DownArrow): "Down Arrow",
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\",
        UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'",
        UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_ANSI_Grave): "`",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12"
    ]

    static let hotKeyChoices: [HotKeyChoice] = labels
        .filter { label(for: $0.key) != "Delete" }
        .map { HotKeyChoice(keyCode: UInt32($0.key), label: $0.value) }
        .sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }

    static let preferredProfileSwitchKeys: [UInt16] = [
        UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
        UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
        UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
        UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3), UInt16(kVK_ANSI_4),
        UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6), UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8),
        UInt16(kVK_ANSI_9), UInt16(kVK_ANSI_0)
    ]

    static func label(for keyCode: UInt16) -> String {
        labels[keyCode] ?? "Key \(keyCode)"
    }
}

enum AppFilterMode: String, CaseIterable, Codable, Identifiable {
    case all
    case include
    case exclude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .include:
            return "Include"
        case .exclude:
            return "Exclude"
        }
    }
}

struct ManagedApplication: Identifiable, Codable, Equatable {
    let bundleIdentifier: String
    var displayName: String
    var appPath: String?
    var customQuickKeyCode: UInt16?

    var id: String { bundleIdentifier }

    var customQuickKeyDisplayText: String {
        guard let customQuickKeyCode else { return "" }
        return KeyCodeCatalog.label(for: customQuickKeyCode)
    }
}

struct TeleportProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var profileSwitchKeyCode: UInt16?
    var filterMode: AppFilterMode
    var applications: [ManagedApplication]

    // Legacy decoding support
    private enum CodingKeys: String, CodingKey {
        case id, name, hotKey, profileSwitchKeyCode, filterMode, applications
    }

    init(id: UUID, name: String, profileSwitchKeyCode: UInt16?, filterMode: AppFilterMode, applications: [ManagedApplication]) {
        self.id = id
        self.name = name
        self.profileSwitchKeyCode = profileSwitchKeyCode
        self.filterMode = filterMode
        self.applications = applications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Ignore legacy hotKey field if present
        profileSwitchKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .profileSwitchKeyCode)
        filterMode = try container.decode(AppFilterMode.self, forKey: .filterMode)
        applications = try container.decode([ManagedApplication].self, forKey: .applications)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(profileSwitchKeyCode, forKey: .profileSwitchKeyCode)
        try container.encode(filterMode, forKey: .filterMode)
        try container.encode(applications, forKey: .applications)
    }

    static func makeDefault(name: String = "Default") -> TeleportProfile {
        TeleportProfile(
            id: UUID(),
            name: name,
            profileSwitchKeyCode: UInt16(kVK_F1),
            filterMode: .all,
            applications: []
        )
    }

    var profileSwitchKeyDisplayText: String {
        guard let profileSwitchKeyCode else {
            return "Not Set"
        }

        return KeyCodeCatalog.label(for: profileSwitchKeyCode)
    }
}

struct TeleportSettings: Codable, Equatable {
    var activeProfileID: UUID
    var defaultProfileID: UUID
    var backgroundStyle: SwitcherBackgroundStyle
    var hotKey: HotKeyShortcut
    var profiles: [TeleportProfile]

    // Support decoding old format where hotKey lived per-profile
    private enum CodingKeys: String, CodingKey {
        case activeProfileID, defaultProfileID, backgroundStyle, hotKey, profiles
    }

    init(activeProfileID: UUID, defaultProfileID: UUID, backgroundStyle: SwitcherBackgroundStyle, hotKey: HotKeyShortcut = .default, profiles: [TeleportProfile]) {
        self.activeProfileID = activeProfileID
        self.defaultProfileID = defaultProfileID
        self.backgroundStyle = backgroundStyle
        self.hotKey = hotKey
        self.profiles = profiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProfileID = try container.decode(UUID.self, forKey: .activeProfileID)
        defaultProfileID = try container.decode(UUID.self, forKey: .defaultProfileID)
        backgroundStyle = try container.decode(SwitcherBackgroundStyle.self, forKey: .backgroundStyle)
        hotKey = try container.decodeIfPresent(HotKeyShortcut.self, forKey: .hotKey) ?? .default
        profiles = try container.decode([TeleportProfile].self, forKey: .profiles)
    }

    static func makeDefault() -> TeleportSettings {
        let profile = TeleportProfile.makeDefault()
        return TeleportSettings(
            activeProfileID: profile.id,
            defaultProfileID: profile.id,
            backgroundStyle: .glass,
            hotKey: .default,
            profiles: [profile]
        )
    }

    func normalized() -> TeleportSettings {
        var normalizedProfiles = profiles
        let normalizedHotKey = hotKey.normalized

        if normalizedProfiles.isEmpty {
            let profile = TeleportProfile.makeDefault()
            return TeleportSettings(
                activeProfileID: profile.id,
                defaultProfileID: profile.id,
                backgroundStyle: backgroundStyle,
                hotKey: normalizedHotKey,
                profiles: [profile]
            )
        }

        for index in normalizedProfiles.indices {
            normalizedProfiles[index].name = normalizedProfiles[index].name.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedProfiles[index].name.isEmpty {
                normalizedProfiles[index].name = "Profile \(index + 1)"
            }

            normalizedProfiles[index].applications = Self.deduplicatedApplications(normalizedProfiles[index].applications)
        }

        var usedSwitchKeys = Set<UInt16>()
        for index in normalizedProfiles.indices {
            let switchKey = normalizedProfiles[index].profileSwitchKeyCode
            if let switchKey,
               switchKey != KeyCodeCatalog.profilePickerKeyCode,
               usedSwitchKeys.insert(switchKey).inserted {
                continue
            }

            normalizedProfiles[index].profileSwitchKeyCode = Self.nextAvailableProfileSwitchKey(usedKeys: usedSwitchKeys)
            if let assignedKey = normalizedProfiles[index].profileSwitchKeyCode {
                usedSwitchKeys.insert(assignedKey)
            }
        }

        let validActiveProfileID = normalizedProfiles.contains(where: { $0.id == activeProfileID })
            ? activeProfileID
            : normalizedProfiles[0].id
        let validDefaultProfileID = normalizedProfiles.contains(where: { $0.id == defaultProfileID })
            ? defaultProfileID
            : normalizedProfiles[0].id

        return TeleportSettings(
            activeProfileID: validActiveProfileID,
            defaultProfileID: validDefaultProfileID,
            backgroundStyle: backgroundStyle,
            hotKey: normalizedHotKey,
            profiles: normalizedProfiles
        )
    }

    private static func deduplicatedApplications(_ applications: [ManagedApplication]) -> [ManagedApplication] {
        var seenBundleIdentifiers = Set<String>()
        var deduplicated: [ManagedApplication] = []

        for application in applications {
            guard seenBundleIdentifiers.insert(application.bundleIdentifier).inserted else {
                continue
            }

            var normalizedApplication = application
            normalizedApplication.displayName = normalizedApplication.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

            if normalizedApplication.displayName.isEmpty {
                normalizedApplication.displayName = normalizedApplication.bundleIdentifier
            }

            deduplicated.append(normalizedApplication)
        }

        return deduplicated
    }

    private static func nextAvailableProfileSwitchKey(usedKeys: Set<UInt16>) -> UInt16? {
        KeyCodeCatalog.preferredProfileSwitchKeys.first(where: { !usedKeys.contains($0) })
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    private(set) var settings: TeleportSettings {
        didSet { objectWillChange.send() }
    }

    @Published private(set) var runningApplications: [ManagedApplication] = []

    private static let storageKey = "Teleport.Settings"
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private var observerTokens: [NSObjectProtocol] = []

    init(
        defaults: UserDefaults = .standard,
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.defaults = defaults
        self.workspace = workspace
        self.notificationCenter = notificationCenter

        if
            let data = defaults.data(forKey: Self.storageKey),
            let decoded = try? decoder.decode(TeleportSettings.self, from: data)
        {
            settings = decoded.normalized()
        } else {
            settings = TeleportSettings.makeDefault()
        }

        refreshRunningApplications()
        startObservingWorkspace()
    }

    var profiles: [TeleportProfile] {
        settings.profiles
    }

    var activeProfile: TeleportProfile {
        settings.profiles.first(where: { $0.id == settings.activeProfileID }) ?? settings.profiles[0]
    }

    var defaultProfile: TeleportProfile {
        settings.profiles.first(where: { $0.id == settings.defaultProfileID }) ?? settings.profiles[0]
    }

    func activateProfile(id: UUID) {
        mutate { settings in
            guard settings.profiles.contains(where: { $0.id == id }) else {
                return
            }

            settings.activeProfileID = id
        }
    }

    func setDefaultProfile(id: UUID) {
        mutate { settings in
            guard settings.profiles.contains(where: { $0.id == id }) else {
                return
            }

            settings.defaultProfileID = id
        }
    }

    func createProfile() {
        mutate { settings in
            var newProfile = activeProfile
            newProfile.id = UUID()
            newProfile.name = makeUniqueProfileName(basedOn: "\(activeProfile.name) Copy", profiles: settings.profiles)
            newProfile.profileSwitchKeyCode = nextProfileSwitchKey(for: settings.profiles)
            settings.profiles.append(newProfile)
            settings.activeProfileID = newProfile.id
        }
    }

    func deleteActiveProfile() {
        guard settings.profiles.count > 1 else {
            return
        }

        mutate { settings in
            let deletedProfileID = settings.activeProfileID
            settings.profiles.removeAll { $0.id == deletedProfileID }
            settings.activeProfileID = settings.profiles[0].id

            if settings.defaultProfileID == deletedProfileID {
                settings.defaultProfileID = settings.profiles[0].id
            }
        }
    }

    func renameActiveProfile(_ name: String) {
        updateActiveProfile { profile in
            profile.name = name
        }
    }

    func setBackgroundStyle(_ style: SwitcherBackgroundStyle) {
        mutate { settings in
            settings.backgroundStyle = style
        }
    }

    func setHotKey(_ shortcut: HotKeyShortcut) {
        mutate { settings in
            settings.hotKey = shortcut
        }
    }

    func setActiveProfileSwitchKey(_ keyCode: UInt16?) {
        mutate { settings in
            guard let index = settings.profiles.firstIndex(where: { $0.id == settings.activeProfileID }) else {
                return
            }

            if keyCode == KeyCodeCatalog.profilePickerKeyCode {
                settings.profiles[index].profileSwitchKeyCode = nextProfileSwitchKey(
                    for: settings.profiles,
                    excludingProfileAt: index
                )
                return
            }

            let oldValue = settings.profiles[index].profileSwitchKeyCode
            settings.profiles[index].profileSwitchKeyCode = keyCode

            let duplicateIndices = settings.profiles.indices.filter {
                $0 != index && settings.profiles[$0].profileSwitchKeyCode == keyCode && keyCode != nil
            }

            for duplicateIndex in duplicateIndices {
                settings.profiles[duplicateIndex].profileSwitchKeyCode = oldValue
            }
        }
    }

    func setActiveProfileFilterMode(_ mode: AppFilterMode) {
        updateActiveProfile { profile in
            profile.filterMode = mode
        }
    }

    func addApplications(_ applications: [ManagedApplication]) {
        guard !applications.isEmpty else {
            return
        }

        updateActiveProfile { profile in
            for application in applications {
                if let existingIndex = profile.applications.firstIndex(where: { $0.bundleIdentifier == application.bundleIdentifier }) {
                    profile.applications[existingIndex].displayName = application.displayName
                    profile.applications[existingIndex].appPath = application.appPath
                    continue
                }

                profile.applications.append(application)
            }
        }
    }

    func addApplications(from urls: [URL]) {
        addApplications(urls.compactMap(Self.makeApplication(from:)))
    }

    func setApplicationQuickKey(bundleIdentifier: String, keyCode: UInt16?) {
        updateActiveProfile { profile in
            guard let index = profile.applications.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                return
            }

            // Clear duplicate if another app has this key
            if let keyCode {
                for i in profile.applications.indices where i != index {
                    if profile.applications[i].customQuickKeyCode == keyCode {
                        profile.applications[i].customQuickKeyCode = nil
                    }
                }
            }

            profile.applications[index].customQuickKeyCode = keyCode
        }
    }

    func includeRunningApplication(bundleIdentifier: String) {
        guard let application = runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            return
        }

        addApplications([application])
    }

    func removeApplications(bundleIdentifiers: [String]) {
        let identifiers = Set(bundleIdentifiers)

        updateActiveProfile { profile in
            profile.applications.removeAll { identifiers.contains($0.bundleIdentifier) }
        }
    }

    func moveApplication(bundleIdentifier: String, by offset: Int) {
        updateActiveProfile { profile in
            guard let index = profile.applications.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                return
            }

            let destination = index + offset
            guard profile.applications.indices.contains(destination) else {
                return
            }

            let application = profile.applications.remove(at: index)
            profile.applications.insert(application, at: destination)
        }
    }

    private func startObservingWorkspace() {
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        for name in names {
            let token = notificationCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshRunningApplications()
                }
            }
            observerTokens.append(token)
        }
    }

    private func refreshRunningApplications() {
        let excludingBundleIdentifier = Bundle.main.bundleIdentifier
        runningApplications = workspace.runningApplications
            .filter { application in
                guard
                    !application.isTerminated,
                    application.activationPolicy == .regular,
                    application.bundleIdentifier != excludingBundleIdentifier
                else {
                    return false
                }

                return application.localizedName?.isEmpty == false
            }
            .map(Self.makeApplication(from:))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func updateActiveProfile(_ update: (inout TeleportProfile) -> Void) {
        mutate { settings in
            guard let index = settings.profiles.firstIndex(where: { $0.id == settings.activeProfileID }) else {
                return
            }

            update(&settings.profiles[index])
        }
    }

    private func mutate(_ update: (inout TeleportSettings) -> Void) {
        var updatedSettings = settings
        update(&updatedSettings)
        updatedSettings = updatedSettings.normalized()
        settings = updatedSettings
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(settings) else {
            return
        }

        defaults.set(data, forKey: Self.storageKey)
    }

    private func makeUniqueProfileName(basedOn baseName: String, profiles: [TeleportProfile]) -> String {
        if !profiles.contains(where: { $0.name == baseName }) {
            return baseName
        }

        for suffix in 2...1000 {
            let candidate = "\(baseName) \(suffix)"
            if !profiles.contains(where: { $0.name == candidate }) {
                return candidate
            }
        }

        return "\(baseName) \(UUID().uuidString.prefix(4))"
    }

    private func nextProfileSwitchKey(for profiles: [TeleportProfile], excludingProfileAt excludedIndex: Int? = nil) -> UInt16? {
        let usedKeys: Set<UInt16> = Set(
            profiles.enumerated().compactMap { index, profile in
                guard index != excludedIndex else {
                    return nil
                }

                guard let keyCode = profile.profileSwitchKeyCode,
                      keyCode != KeyCodeCatalog.profilePickerKeyCode else {
                    return nil
                }

                return keyCode
            }
        )
        return KeyCodeCatalog.preferredProfileSwitchKeys.first(where: { !usedKeys.contains($0) })
    }

    private static func makeApplication(from url: URL) -> ManagedApplication? {
        guard let bundle = Bundle(url: url) else {
            return nil
        }

        guard let bundleIdentifier = bundle.bundleIdentifier else {
            return nil
        }

        let displayName =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
            url.deletingPathExtension().lastPathComponent

        return ManagedApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName,
            appPath: url.path
        )
    }

    private static func makeApplication(from runningApplication: NSRunningApplication) -> ManagedApplication {
        ManagedApplication(
            bundleIdentifier: runningApplication.bundleIdentifier ?? "pid-\(runningApplication.processIdentifier)",
            displayName: runningApplication.localizedName ?? "Unknown App",
            appPath: runningApplication.bundleURL?.path
        )
    }
}
