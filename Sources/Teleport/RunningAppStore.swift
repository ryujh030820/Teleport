import AppKit

@MainActor
final class RunningAppStore: NSObject {
    private let workspace: NSWorkspace
    private let notificationCenter: NotificationCenter
    private let excludingBundleIdentifier: String?
    private var activationHistory: [String] = []
    init(
        workspace: NSWorkspace = .shared,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        excludingBundleIdentifier: String?
    ) {
        self.workspace = workspace
        self.notificationCenter = notificationCenter
        self.excludingBundleIdentifier = excludingBundleIdentifier
        super.init()
    }

    func start() {
        seedHistory()

        notificationCenter.addObserver(
            self,
            selector: #selector(handleDidActivateApplication(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func makeSnapshot(profile: TeleportProfile) -> SwitcherSnapshot {
        let frontmostBundleIdentifier = workspace.frontmostApplication?.bundleIdentifier
        let runningApplications = workspace.runningApplications
            .filter(shouldInclude)
        let apps = sortedApplications(
            from: runningApplications,
            profile: profile,
            frontmostBundleIdentifier: frontmostBundleIdentifier
        )
            .map { app in
                SwitchableApp(
                    runningApplication: app,
                    quickKey: QuickKey(label: "", keyCode: UInt16.max),
                    isFrontmost: app.bundleIdentifier == frontmostBundleIdentifier
                )
            }

        let customKeys = Dictionary(
            uniqueKeysWithValues: profile.applications
                .compactMap { app -> (String, UInt16)? in
                    guard let keyCode = app.customQuickKeyCode else { return nil }
                    return (app.bundleIdentifier, keyCode)
                }
        )
        let assignedApps = QuickKeyAllocator.assignKeys(to: Array(apps), customKeys: customKeys)
        return SwitcherSnapshot(
            apps: assignedApps,
            initialSelectionIndex: initialSelectionIndex(
                for: assignedApps,
                profile: profile,
                frontmostBundleIdentifier: frontmostBundleIdentifier
            )
        )
    }

    func noteActivation(of app: NSRunningApplication) {
        guard
            let bundleIdentifier = app.bundleIdentifier,
            shouldInclude(app: app)
        else {
            return
        }

        recordActivation(bundleIdentifier)
    }

    private func seedHistory() {
        let currentApps = workspace.runningApplications
            .filter(shouldInclude)
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        activationHistory = currentApps.compactMap(\.bundleIdentifier)

        if let frontmostBundleIdentifier = workspace.frontmostApplication?.bundleIdentifier,
           activationHistory.contains(frontmostBundleIdentifier) {
            recordActivation(frontmostBundleIdentifier)
        }
    }

    @objc
    private func handleDidActivateApplication(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleIdentifier = app.bundleIdentifier,
            shouldInclude(app: app)
        else {
            return
        }

        recordActivation(bundleIdentifier)
    }

    private func shouldInclude(app: NSRunningApplication) -> Bool {
        guard
            !app.isTerminated,
            app.activationPolicy == .regular,
            let bundleIdentifier = app.bundleIdentifier,
            bundleIdentifier != excludingBundleIdentifier
        else {
            return false
        }

        return app.localizedName?.isEmpty == false
    }

    private func recordActivation(_ bundleIdentifier: String) {
        activationHistory.removeAll { $0 == bundleIdentifier }
        activationHistory.insert(bundleIdentifier, at: 0)
    }

    private func sortedApplications(
        from runningApplications: [NSRunningApplication],
        profile: TeleportProfile,
        frontmostBundleIdentifier: String?
    ) -> [NSRunningApplication] {
        let managedBundleIdentifiers = Set(profile.applications.map(\.bundleIdentifier))

        // Filter based on filter mode
        let filteredApplications: [NSRunningApplication]
        switch profile.filterMode {
        case .all:
            filteredApplications = runningApplications
        case .include:
            if profile.applications.isEmpty {
                filteredApplications = runningApplications
            } else {
                filteredApplications = runningApplications.filter { app in
                    guard let bundleIdentifier = app.bundleIdentifier else {
                        return false
                    }
                    return managedBundleIdentifiers.contains(bundleIdentifier)
                }
            }
        case .exclude:
            if profile.applications.isEmpty {
                filteredApplications = runningApplications
            } else {
                filteredApplications = runningApplications.filter { app in
                    guard let bundleIdentifier = app.bundleIdentifier else {
                        return true
                    }
                    return !managedBundleIdentifiers.contains(bundleIdentifier)
                }
            }
        }

        // MRU order
        return filteredApplications.sorted {
            compareByActivationHistory(
                lhs: $0,
                rhs: $1,
                frontmostBundleIdentifier: frontmostBundleIdentifier
            )
        }
    }

    private func compareByActivationHistory(
        lhs: NSRunningApplication,
        rhs: NSRunningApplication,
        frontmostBundleIdentifier: String?
    ) -> Bool {
        let lhsIsFrontmost = lhs.bundleIdentifier == frontmostBundleIdentifier
        let rhsIsFrontmost = rhs.bundleIdentifier == frontmostBundleIdentifier

        if lhsIsFrontmost != rhsIsFrontmost {
            return lhsIsFrontmost
        }

        let lhsRank = activationHistory.firstIndex(of: lhs.bundleIdentifier ?? "") ?? Int.max
        let rhsRank = activationHistory.firstIndex(of: rhs.bundleIdentifier ?? "") ?? Int.max

        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        return lhs.localizedName ?? "" < rhs.localizedName ?? ""
    }

    private func initialSelectionIndex(
        for apps: [SwitchableApp],
        profile: TeleportProfile,
        frontmostBundleIdentifier: String?
    ) -> Int {
        guard !apps.isEmpty else {
            return 0
        }

        guard
            let frontmostBundleIdentifier,
            let currentIndex = apps.firstIndex(where: { $0.runningApplication.bundleIdentifier == frontmostBundleIdentifier })
        else {
            return 0
        }

        return currentIndex
    }
}

struct SwitcherSnapshot {
    let apps: [SwitchableApp]
    let initialSelectionIndex: Int
}
