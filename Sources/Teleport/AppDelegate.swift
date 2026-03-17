import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore.shared
    private var statusBarController: StatusBarController?
    private var runningAppStore: RunningAppStore?
    private var switcherWindowController: SwitcherWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var hotKeyManager: HotKeyManager?
    private var settingsObservation: AnyCancellable?
    private let updateChecker = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runningAppStore = RunningAppStore(excludingBundleIdentifier: Bundle.main.bundleIdentifier)
        let switcherWindowController = SwitcherWindowController()
        let settingsWindowController = SettingsWindowController(
            store: settingsStore,
            onCheckForUpdates: { [weak self] in
                self?.updateChecker.checkForUpdates()
            }
        )

        self.runningAppStore = runningAppStore
        self.switcherWindowController = switcherWindowController
        switcherWindowController.onActivateApplication = { [weak runningAppStore] app in
            Task { @MainActor in
                runningAppStore?.noteActivation(of: app)
            }
        }
        self.settingsWindowController = settingsWindowController
        self.statusBarController = StatusBarController(
            settingsStore: settingsStore,
            onOpenSwitcher: { [weak self] in
                self?.presentSwitcher(profileID: nil)
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onSelectProfile: { [weak self] profileID in
                self?.settingsStore.activateProfile(id: profileID)
            },
            onCheckForUpdates: { [weak self] in
                self?.updateChecker.checkForUpdates()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
        self.settingsObservation = settingsStore.objectWillChange
            .sink { [weak self] in
                self?.applySettings()
            }

        runningAppStore.start()
        applySettings()
    }

    private func presentSwitcher(profileID: UUID?) {
        guard let runningAppStore, let switcherWindowController else {
            return
        }

        let profile = resolvedProfile(for: profileID)
        let snapshot = runningAppStore.makeSnapshot(profile: profile)
        guard !snapshot.apps.isEmpty else {
            NSSound.beep()
            return
        }

        switcherWindowController.show(
            snapshot: snapshot,
            currentProfileID: profile.id,
            profiles: settingsStore.profiles,
            requiredModifiers: settingsStore.settings.hotKey.normalized.modifiers.eventModifiers,
            backgroundStyle: settingsStore.settings.backgroundStyle,
            onSwitchProfile: { [weak self] newProfileID in
                self?.switchProfileWhileVisible(profileID: newProfileID)
            }
        )
    }

    private func handleHotKey() {
        guard let switcherWindowController else {
            return
        }

        if switcherWindowController.isSwitcherVisible {
            switcherWindowController.moveSelection(forward: true)
            return
        }

        presentSwitcher(profileID: nil)
    }

    private func openSettings() {
        settingsWindowController?.showWindowAndActivate()
    }

    private func applySettings() {
        if let hotKeyManager {
            hotKeyManager.update(shortcut: settingsStore.settings.hotKey)
        } else {
            hotKeyManager = HotKeyManager(
                shortcut: settingsStore.settings.hotKey,
                onPressed: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.handleHotKey()
                    }
                }
            )
        }
        switcherWindowController?.applyBackgroundStyle(settingsStore.settings.backgroundStyle)
        statusBarController?.updateProfiles(
            settingsStore.profiles,
            activeProfileID: settingsStore.activeProfile.id,
            defaultProfileID: settingsStore.settings.defaultProfileID
        )
    }

    private func switchProfileWhileVisible(profileID: UUID) -> SwitcherSnapshot? {
        guard let runningAppStore else {
            return nil
        }

        settingsStore.activateProfile(id: profileID)
        let profile = resolvedProfile(for: profileID)
        return runningAppStore.makeSnapshot(profile: profile)
    }

    private func resolvedProfile(for profileID: UUID?) -> TeleportProfile {
        if let profileID, let profile = settingsStore.profiles.first(where: { $0.id == profileID }) {
            return profile
        }

        return settingsStore.defaultProfile
    }
}

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let actionHandler: StatusBarActionHandler

    init(
        settingsStore: SettingsStore,
        onOpenSwitcher: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSelectProfile: @escaping (UUID) -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon()
            button.toolTip = "Teleport"
        }

        let actionHandler = StatusBarActionHandler(
            onOpenSwitcher: onOpenSwitcher,
            onOpenSettings: onOpenSettings,
            onSelectProfile: onSelectProfile,
            onCheckForUpdates: onCheckForUpdates,
            onQuit: onQuit
        )
        self.actionHandler = actionHandler
        updateProfiles(
            settingsStore.profiles,
            activeProfileID: settingsStore.activeProfile.id,
            defaultProfileID: settingsStore.settings.defaultProfileID
        )
    }

    private static func makeMenuBarIcon() -> NSImage {
        if let image = NSImage(systemSymbolName: "inset.filled.diamond", accessibilityDescription: "Teleport") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            return configured
        }
        // Fallback: empty template image
        let fallback = NSImage(size: NSSize(width: 18, height: 18))
        fallback.isTemplate = true
        return fallback
    }

    func updateProfiles(_ profiles: [TeleportProfile], activeProfileID: UUID, defaultProfileID: UUID) {
        let menu = NSMenu()

        let openSwitcherItem = NSMenuItem(
            title: "Open Switcher",
            action: #selector(StatusBarActionHandler.openSwitcher),
            keyEquivalent: ""
        )
        openSwitcherItem.target = actionHandler
        menu.addItem(openSwitcherItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(StatusBarActionHandler.openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = actionHandler
        menu.addItem(settingsItem)

        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(StatusBarActionHandler.checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = actionHandler
        menu.addItem(checkForUpdatesItem)

        menu.addItem(NSMenuItem.separator())

        let profilesItem = NSMenuItem(title: "Profiles", action: nil, keyEquivalent: "")
        let profilesMenu = NSMenu(title: "Profiles")

        for profile in profiles {
            let item = NSMenuItem(
                title: profile.name,
                action: #selector(StatusBarActionHandler.selectProfile(_:)),
                keyEquivalent: ""
            )
            item.target = actionHandler
            item.representedObject = profile.id.uuidString
            item.state = profile.id == activeProfileID ? .on : .off
            if profile.id == defaultProfileID {
                item.title = "\(profile.name) (Default)"
            }
            profilesMenu.addItem(item)
        }

        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Teleport",
            action: #selector(StatusBarActionHandler.quit),
            keyEquivalent: "q"
        )
        quitItem.target = actionHandler
        menu.addItem(quitItem)

        statusItem.menu = menu
    }
}

@MainActor
private final class StatusBarActionHandler: NSObject {
    private let onOpenSwitcher: () -> Void
    private let onOpenSettings: () -> Void
    private let onSelectProfile: (UUID) -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onOpenSwitcher: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onSelectProfile: @escaping (UUID) -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenSwitcher = onOpenSwitcher
        self.onOpenSettings = onOpenSettings
        self.onSelectProfile = onSelectProfile
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
    }

    @objc
    func openSwitcher() {
        onOpenSwitcher()
    }

    @objc
    func openSettings() {
        onOpenSettings()
    }

    @objc
    func selectProfile(_ sender: NSMenuItem) {
        guard
            let profileIDString = sender.representedObject as? String,
            let profileID = UUID(uuidString: profileIDString)
        else {
            return
        }

        onSelectProfile(profileID)
    }

    @objc
    func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc
    func quit() {
        onQuit()
    }
}
