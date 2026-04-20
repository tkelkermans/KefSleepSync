import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

private enum MenuBarIcon {
    static func makeSpeakerImage(isEnabled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        let cabinetRect = NSRect(x: 4.5, y: 1.8, width: 8.8, height: 14.4)
        let cabinetPath = NSBezierPath(roundedRect: cabinetRect, xRadius: 2.3, yRadius: 2.3)
        NSColor.labelColor.setFill()
        cabinetPath.fill()

        let tweeterRect = NSRect(x: 7.0, y: 11.0, width: 3.8, height: 3.8)
        let wooferRect = NSRect(x: 6.2, y: 4.1, width: 5.4, height: 5.4)
        let portRect = NSRect(x: 7.8, y: 12.2, width: 1.4, height: 1.4)

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setBlendMode(.clear)
            context.fillEllipse(in: tweeterRect)
            context.fillEllipse(in: wooferRect)
            context.fillEllipse(in: portRect)
            context.restoreGState()
        }

        if !isEnabled {
            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 3.0, y: 3.2))
            slash.line(to: NSPoint(x: 15.0, y: 15.0))
            slash.lineWidth = 1.8
            slash.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            slash.stroke()
        }

        return image
    }
}

private enum PowerMessage {
    static let canSystemSleep: natural_t = 0xE000_0270
    static let systemWillSleep: natural_t = 0xE000_0280
    static let systemHasPoweredOn: natural_t = 0xE000_0300
    static let systemWillPowerOn: natural_t = 0xE000_0320
}

private final class PowerEventMonitor {
    var onWillSleep: ((@escaping () -> Void) -> Void)?
    var onDidWake: (() -> Void)?

    private var notificationPort: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var rootPort: io_connect_t = IO_OBJECT_NULL

    deinit {
        stop()
    }

    func start() {
        guard rootPort == IO_OBJECT_NULL else { return }

        var portRef: IONotificationPortRef?
        var notifierObject: io_object_t = IO_OBJECT_NULL
        let connection = IORegisterForSystemPower(
            Unmanaged.passUnretained(self).toOpaque(),
            &portRef,
            { refcon, _, messageType, messageArgument in
                guard let refcon else { return }
                let monitor = Unmanaged<PowerEventMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(messageType: messageType, messageArgument: messageArgument)
            },
            &notifierObject
        )

        guard connection != IO_OBJECT_NULL, let portRef else {
            AppLogger.power.error("Failed to register for IOKit power notifications.")
            return
        }

        rootPort = connection
        notificationPort = portRef
        notifier = notifierObject

        if let runLoopSource = IONotificationPortGetRunLoopSource(portRef)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        AppLogger.power.info("Registered IOKit power notifications.")
    }

    func stop() {
        guard rootPort != IO_OBJECT_NULL || notificationPort != nil || notifier != IO_OBJECT_NULL else {
            return
        }

        if notifier != IO_OBJECT_NULL {
            IODeregisterForSystemPower(&notifier)
            notifier = IO_OBJECT_NULL
        }

        if let notificationPort {
            if let runLoopSource = IONotificationPortGetRunLoopSource(notificationPort)?.takeUnretainedValue() {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            }
            IONotificationPortDestroy(notificationPort)
            self.notificationPort = nil
        }

        if rootPort != IO_OBJECT_NULL {
            IOServiceClose(rootPort)
            rootPort = IO_OBJECT_NULL
        }

        AppLogger.power.info("Stopped IOKit power notifications.")
    }

    private func handle(messageType: natural_t, messageArgument: UnsafeMutableRawPointer?) {
        switch messageType {
        case PowerMessage.canSystemSleep:
            AppLogger.power.debug("Received kIOMessageCanSystemSleep.")
            allowPowerChange(messageArgument)

        case PowerMessage.systemWillSleep:
            AppLogger.power.info("Received kIOMessageSystemWillSleep.")
            onWillSleep? { [weak self] in
                self?.allowPowerChange(messageArgument)
            } ?? allowPowerChange(messageArgument)

        case PowerMessage.systemWillPowerOn:
            AppLogger.power.debug("Received kIOMessageSystemWillPowerOn.")

        case PowerMessage.systemHasPoweredOn:
            AppLogger.power.info("Received kIOMessageSystemHasPoweredOn.")
            onDidWake?()

        default:
            AppLogger.power.debug("Received IOKit power message type \(messageType).")
        }
    }

    private func allowPowerChange(_ messageArgument: UnsafeMutableRawPointer?) {
        guard rootPort != IO_OBJECT_NULL else { return }
        let notificationID = Int(bitPattern: messageArgument)
        IOAllowPowerChange(rootPort, notificationID)
    }
}

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var speakers: [DiscoveredSpeaker] = []
    @Published private(set) var selectedSpeaker: DiscoveredSpeaker?
    @Published private(set) var automationState: AutomationState
    @Published private(set) var isWorking = false
    @Published var launchAtLoginEnabled: Bool
    @Published private(set) var loginItemStatusMessage: String

    private enum DefaultsKey {
        static let selectedSpeakerIdentity = "selectedSpeakerIdentity"
        static let automationState = "automationState"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }

    private enum Timing {
        static let selectionTimeout: TimeInterval = 2
        static let rediscoveryTimeout: TimeInterval = 20
        static let duplicateEventWindow: TimeInterval = 10
        static let shortRetryDelay: TimeInterval = 0.5
        static let standardRetryDelay: TimeInterval = 0.75
        static let wakeRetryDelay: TimeInterval = 1.0
    }

    private enum DistributedNotificationName {
        static let screenLocked = Notification.Name("com.apple.screenIsLocked")
        static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    }

    private enum PowerEventKind {
        case sleep(trigger: String)
        case wake(trigger: String)

        var logLabel: String {
            switch self {
            case .sleep:
                return "sleep sync"
            case .wake:
                return "wake sync"
            }
        }
    }

    private enum DuplicateEventKind {
        case sleepLike
        case wakeLike

        var logLabel: String {
            switch self {
            case .sleepLike:
                return "sleep-like"
            case .wakeLike:
                return "wake-like"
            }
        }
    }

    private let defaults: UserDefaults
    private let discoveryService: SpeakerDiscoveryService
    private let apiClient: KefAPIClient
    private let loginItemService: LoginItemService
    private let powerEventMonitor = PowerEventMonitor()
    private var selectedIdentity: SelectedSpeakerIdentity?
    private var cancellables: Set<AnyCancellable> = []
    private var hasStarted = false
    private var willSleepObserver: NSObjectProtocol?
    private var didWakeObserver: NSObjectProtocol?
    private var screensDidSleepObserver: NSObjectProtocol?
    private var screensDidWakeObserver: NSObjectProtocol?
    private var sessionDidResignActiveObserver: NSObjectProtocol?
    private var sessionDidBecomeActiveObserver: NSObjectProtocol?
    private var screenLockObserver: NSObjectProtocol?
    private var screenUnlockObserver: NSObjectProtocol?
    private var lastSleepLikeEventAt: Date?
    private var lastWakeLikeEventAt: Date?

    private init(
        defaults: UserDefaults = .standard,
        discoveryService: SpeakerDiscoveryService = SpeakerDiscoveryService(),
        apiClient: KefAPIClient = KefAPIClient(),
        loginItemService: LoginItemService = LoginItemService()
    ) {
        self.defaults = defaults
        self.discoveryService = discoveryService
        self.apiClient = apiClient
        self.loginItemService = loginItemService
        self.automationState = Self.loadAutomationState(from: defaults)
        self.launchAtLoginEnabled = defaults.object(forKey: DefaultsKey.launchAtLoginEnabled) as? Bool ?? true
        self.loginItemStatusMessage = loginItemService.statusDescription
        self.selectedIdentity = Self.loadSelectedIdentity(from: defaults)

        bindDiscovery()
    }

    static func makeReadmeDemoModel() -> AppModel {
        let model = AppModel()
        let speaker = DiscoveredSpeaker(
            id: "demo-ls50w2",
            name: "Living Room",
            modelName: "LS50 Wireless II",
            serialNumber: "DEMO-0001",
            host: "speaker-demo.local",
            port: 80,
            serviceName: "Living Room",
            lastSeenAt: Date()
        )

        model.speakers = [speaker]
        model.selectedSpeaker = speaker
        model.selectedIdentity = speaker.identity
        model.automationState = AutomationState(
            isEnabled: true,
            originalStandbyMode: .standby20Minutes,
            lastSyncDescription: "Speaker powered on and switched to Optical after display wake.",
            lastSyncAt: Date(timeIntervalSince1970: 1_713_600_000)
        )
        model.launchAtLoginEnabled = true
        model.loginItemStatusMessage = "Enabled"
        return model
    }

    deinit {
        unregisterPowerObservers()
        powerEventMonitor.stop()
    }

    var menuBarImage: NSImage {
        if isWorking {
            let image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Working")
                ?? MenuBarIcon.makeSpeakerImage(isEnabled: automationState.isEnabled)
            image.isTemplate = true
            return image
        }
        return MenuBarIcon.makeSpeakerImage(isEnabled: automationState.isEnabled)
    }

    var selectedSpeakerName: String {
        selectedSpeaker?.name ?? "No speaker selected"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        powerEventMonitor.onWillSleep = { [weak self] allowSleep in
            guard let self else {
                allowSleep()
                return
            }
            self.handlePowerEvent(
                .sleep(trigger: "System sleep"),
                source: "IOKit",
                acknowledgement: allowSleep
            )
        }
        powerEventMonitor.onDidWake = { [weak self] in
            self?.handlePowerEvent(.wake(trigger: "System wake"), source: "IOKit")
        }
        powerEventMonitor.start()

        registerPowerObservers()

        discoveryService.start()

        Task {
            await syncLaunchAtLoginPreference()
        }
    }

    func selectSpeaker(id: String?) {
        guard let id else {
            selectedIdentity = nil
            selectedSpeaker = nil
            saveSelectedIdentity()
            return
        }

        guard let speaker = speakers.first(where: { $0.id == id }) else { return }
        selectedSpeaker = speaker
        selectedIdentity = speaker.identity
        saveSelectedIdentity()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.launchAtLoginEnabled)

        Task {
            await syncLaunchAtLoginPreference()
        }
    }

    func requestAutomationChange(_ enabled: Bool) {
        guard enabled != automationState.isEnabled else { return }

        runExclusiveOperation {
            await self.setAutomation(enabled: enabled)
        }
    }

    func testSleep() {
        runExclusiveOperation {
            await self.performSleepSync(trigger: "Manual test")
        }
    }

    func testWakeToOptical() {
        runExclusiveOperation {
            await self.performWakeSync(trigger: "Manual test")
        }
    }

    func requestQuit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        guard automationState.isEnabled, automationState.originalStandbyMode != nil else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Restore the KEF standby setting before quitting?"
        alert.informativeText = "KefSleepSync changed the speaker standby mode to Never while automation is enabled."
        alert.addButton(withTitle: "Restore & Quit")
        alert.addButton(withTitle: "Quit Without Restoring")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            isWorking = true

            Task { [weak self] in
                guard let self else { return }
                let restored = await self.restoreOriginalStandbyForQuit()
                await MainActor.run {
                    self.isWorking = false
                    NSApplication.shared.reply(toApplicationShouldTerminate: restored)
                }
            }

            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    private func bindDiscovery() {
        discoveryService.$speakers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speakers in
                self?.handleDiscoveredSpeakers(speakers)
            }
            .store(in: &cancellables)
    }

    private func handleDiscoveredSpeakers(_ speakers: [DiscoveredSpeaker]) {
        self.speakers = speakers

        if let selectedIdentity,
           let matchingSpeaker = speakers.first(where: { matchesStoredIdentity($0, selectedIdentity: selectedIdentity) }) {
            selectedSpeaker = matchingSpeaker
            if self.selectedIdentity != matchingSpeaker.identity {
                self.selectedIdentity = matchingSpeaker.identity
                saveSelectedIdentity()
            }
            return
        }

        if speakers.count == 1, let onlySpeaker = speakers.first {
            selectedSpeaker = onlySpeaker
            selectedIdentity = onlySpeaker.identity
            saveSelectedIdentity()
            return
        }

        if let currentSelection = selectedSpeaker,
           let refreshedSpeaker = speakers.first(where: { $0.id == currentSelection.id }) {
            selectedSpeaker = refreshedSpeaker
        } else if speakers.isEmpty {
            selectedSpeaker = nil
        }
    }

    private func runExclusiveOperation(_ operation: @escaping () async -> Void) {
        Task { [weak self] in
            guard let self, await self.beginExclusiveOperation() else { return }
            await operation()
            await self.endExclusiveOperation()
        }
    }

    private func registerPowerObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        // Locking a Mac often blanks the display without entering full system sleep,
        // so observe both workspace/session notifications and IOKit power transitions.
        willSleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received NSWorkspace.willSleepNotification.")
            self?.handlePowerEvent(.sleep(trigger: "System sleep"), source: "NSWorkspace")
        }

        didWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received NSWorkspace.didWakeNotification.")
            self?.handlePowerEvent(.wake(trigger: "System wake"), source: "NSWorkspace")
        }

        screensDidSleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received NSWorkspace.screensDidSleepNotification.")
            self?.handlePowerEvent(.sleep(trigger: "Display sleep"), source: "DisplaySleep")
        }

        screensDidWakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received NSWorkspace.screensDidWakeNotification.")
            self?.handlePowerEvent(.wake(trigger: "Display wake"), source: "DisplayWake")
        }

        sessionDidResignActiveObserver = notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received NSWorkspace.sessionDidResignActiveNotification.")
            self?.handlePowerEvent(.sleep(trigger: "Session inactive"), source: "SessionInactive")
        }

        sessionDidBecomeActiveObserver = notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received NSWorkspace.sessionDidBecomeActiveNotification.")
            self?.handlePowerEvent(.wake(trigger: "Session active"), source: "SessionActive")
        }

        let distributedCenter = DistributedNotificationCenter.default()
        screenLockObserver = distributedCenter.addObserver(
            forName: DistributedNotificationName.screenLocked,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received com.apple.screenIsLocked.")
            self?.handlePowerEvent(.sleep(trigger: "Screen lock"), source: "ScreenLock")
        }

        screenUnlockObserver = distributedCenter.addObserver(
            forName: DistributedNotificationName.screenUnlocked,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLogger.power.info("Received com.apple.screenIsUnlocked.")
            self?.handlePowerEvent(.wake(trigger: "Screen unlock"), source: "ScreenUnlock")
        }
    }

    private func unregisterPowerObservers() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        [willSleepObserver,
         didWakeObserver,
         screensDidSleepObserver,
         screensDidWakeObserver,
         sessionDidResignActiveObserver,
         sessionDidBecomeActiveObserver]
            .compactMap { $0 }
            .forEach(notificationCenter.removeObserver(_:))

        let distributedCenter = DistributedNotificationCenter.default()
        [screenLockObserver, screenUnlockObserver]
            .compactMap { $0 }
            .forEach(distributedCenter.removeObserver(_:))
    }

    private func handlePowerEvent(
        _ kind: PowerEventKind,
        source: String,
        acknowledgement: (() -> Void)? = nil
    ) {
        Task { [weak self] in
            guard let self else {
                acknowledgement?()
                return
            }

            guard await self.shouldHandlePowerEvent(kind, source: source) else {
                acknowledgement?()
                return
            }

            guard await self.beginExclusiveOperation() else {
                AppLogger.power.notice("Skipped \(kind.logLabel, privacy: .public) from \(source, privacy: .public) because another operation is already running.")
                acknowledgement?()
                return
            }

            switch kind {
            case let .sleep(trigger):
                await self.performSleepSync(trigger: trigger)
            case let .wake(trigger):
                await self.performWakeSync(trigger: trigger)
            }

            await self.endExclusiveOperation()
            acknowledgement?()
        }
    }

    private func setAutomation(enabled: Bool) async {
        guard let speaker = await waitForSelectedSpeaker(timeout: Timing.selectionTimeout) else {
            await recordFailure("Choose a KEF speaker before enabling automation.")
            return
        }

        do {
            if enabled {
                await recordProgress("Reading the speaker standby setting...")
                let originalMode = try await retryValue(times: 3, delay: Timing.shortRetryDelay) {
                    let currentSpeaker = await self.currentSpeaker() ?? speaker
                    return try await self.apiClient.readStandbyMode(from: currentSpeaker)
                }
                try await retryValue(times: 3, delay: Timing.shortRetryDelay) {
                    let currentSpeaker = await self.currentSpeaker() ?? speaker
                    try await self.apiClient.setStandbyMode(.standbyNone, on: currentSpeaker)
                }

                await MainActor.run {
                    self.automationState.isEnabled = true
                    self.automationState.originalStandbyMode = originalMode
                    self.saveAutomationState()
                }

                await recordSuccess("Automation enabled. Saved \(originalMode.displayName) and set the KEF standby mode to Never.")
            } else {
                let originalMode = automationState.originalStandbyMode
                if let originalMode {
                    await recordProgress("Restoring the KEF standby setting...")
                    try await retryValue(times: 3, delay: Timing.shortRetryDelay) {
                        let currentSpeaker = await self.currentSpeaker() ?? speaker
                        try await self.apiClient.setStandbyMode(originalMode, on: currentSpeaker)
                    }
                }

                await MainActor.run {
                    self.automationState.isEnabled = false
                    self.automationState.originalStandbyMode = nil
                    self.saveAutomationState()
                }

                if let originalMode {
                    await recordSuccess("Automation disabled. Restored \(originalMode.displayName).")
                } else {
                    await recordSuccess("Automation disabled.")
                }
            }
        } catch {
            await recordFailure("Automation change failed: \(describe(error)).")
        }
    }

    private func performSleepSync(trigger: String) async {
        guard let speaker = await waitForSelectedSpeaker(timeout: Timing.selectionTimeout) else {
            await recordFailure("No KEF speaker was available for \(trigger.lowercased()).")
            return
        }

        await recordProgress("Switching the KEF speaker to standby for \(trigger.lowercased())...")

        let lastError = await retry(times: 3, delay: Timing.standardRetryDelay) {
            let currentSpeaker = await self.currentSpeaker() ?? speaker
            try await self.apiClient.setPhysicalSource(.standby, on: currentSpeaker)
        }

        if let lastError {
            await recordFailure("Standby sync failed: \(describe(lastError)).")
        } else {
            await recordSuccess("Speaker switched to standby for \(trigger.lowercased()).")
        }
    }

    private func performWakeSync(trigger: String) async {
        await recordProgress("Waiting for the KEF speaker after \(trigger.lowercased())...")

        guard let initialSpeaker = await waitForSelectedSpeaker(timeout: Timing.rediscoveryTimeout) else {
            await recordFailure("The KEF speaker did not reappear after \(trigger.lowercased()).")
            return
        }

        let powerRequestError = await retry(times: 5, delay: Timing.wakeRetryDelay) {
            let currentSpeaker = await self.currentSpeaker() ?? initialSpeaker
            try await self.apiClient.setPhysicalSource(.optical, on: currentSpeaker)
        }

        if let powerRequestError {
            await recordFailure("Wake sync failed: \(describe(powerRequestError)).")
            return
        }

        await recordProgress("Waiting for the KEF speaker HTTP API to respond...")

        guard let responsiveSpeaker = await waitUntilResponsive(timeout: Timing.rediscoveryTimeout) else {
            await recordFailure("The KEF speaker never became responsive after wake.")
            return
        }

        let setSourceError = await retry(times: 4, delay: Timing.standardRetryDelay) {
            let currentSpeaker = await self.currentSpeaker() ?? responsiveSpeaker
            try await self.apiClient.setPhysicalSource(.optical, on: currentSpeaker)
        }

        if let setSourceError {
            await recordFailure("The speaker woke up, but switching to Optical failed: \(describe(setSourceError)).")
            return
        }

        let verificationError = await retry(times: 4, delay: Timing.standardRetryDelay) {
            let currentSpeaker = await self.currentSpeaker() ?? responsiveSpeaker
            let source = try await self.apiClient.readPhysicalSource(from: currentSpeaker)
            guard source == .optical else {
                throw NSError(
                    domain: "KefSleepSync.VerifyOptical",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Current source is \(source.displayName)"]
                )
            }
        }

        if let verificationError {
            await recordFailure("The speaker woke up, but Optical could not be confirmed: \(describe(verificationError)).")
        } else {
            await recordSuccess("Speaker powered on and switched to Optical after \(trigger.lowercased()).")
        }
    }

    private func restoreOriginalStandbyForQuit() async -> Bool {
        guard let originalMode = automationState.originalStandbyMode else {
            return true
        }

        guard let speaker = await waitForSelectedSpeaker(timeout: Timing.selectionTimeout) else {
            await recordFailure("Quit was cancelled because the speaker is unavailable and the original standby mode could not be restored.")
            return false
        }

        do {
            try await retryValue(times: 3, delay: Timing.shortRetryDelay) {
                let currentSpeaker = await self.currentSpeaker() ?? speaker
                try await self.apiClient.setStandbyMode(originalMode, on: currentSpeaker)
            }

            await MainActor.run {
                self.automationState.isEnabled = false
                self.automationState.originalStandbyMode = nil
                self.saveAutomationState()
            }

            await recordSuccess("Restored \(originalMode.displayName) before quitting.")
            return true
        } catch {
            await recordFailure("Quit was cancelled because restoring \(originalMode.displayName) failed: \(describe(error)).")
            return false
        }
    }

    private func syncLaunchAtLoginPreference() async {
        do {
            try loginItemService.setEnabled(launchAtLoginEnabled)
            await MainActor.run {
                self.loginItemStatusMessage = loginItemService.statusDescription
            }
        } catch {
            AppLogger.login.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.loginItemStatusMessage = "macOS could not update launch at login for this build. Install the app in /Applications for the most reliable behavior."
            }
        }
    }

    private func retry(
        times: Int,
        delay: TimeInterval,
        operation: @escaping () async throws -> Void
    ) async -> Error? {
        var lastError: Error?

        for attempt in 1 ... times {
            do {
                try await operation()
                return nil
            } catch {
                lastError = error
                if attempt < times {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        return lastError
    }

    private func retryValue<T>(
        times: Int,
        delay: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1 ... times {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < times {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NSError(
            domain: "KefSleepSync.Retry",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The KEF request failed."]
        )
    }

    private func waitForSelectedSpeaker(timeout: TimeInterval) async -> DiscoveredSpeaker? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let speaker = await currentSpeaker() {
                return speaker
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        return nil
    }

    private func waitUntilResponsive(timeout: TimeInterval) async -> DiscoveredSpeaker? {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let speaker = await currentSpeaker() {
                do {
                    _ = try await apiClient.readSpeakerStatusRaw(from: speaker)
                    return speaker
                } catch {
                    AppLogger.api.debug("Speaker is not responsive yet: \(error.localizedDescription, privacy: .public)")
                }
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        return nil
    }

    private func currentSpeaker() async -> DiscoveredSpeaker? {
        await MainActor.run {
            self.selectedSpeaker
        }
    }

    private func beginExclusiveOperation() async -> Bool {
        await MainActor.run {
            guard !self.isWorking else { return false }
            self.isWorking = true
            return true
        }
    }

    private func endExclusiveOperation() async {
        await MainActor.run {
            self.isWorking = false
        }
    }

    private func shouldHandlePowerEvent(_ kind: PowerEventKind, source: String) async -> Bool {
        switch kind {
        case .sleep:
            return await shouldHandleDuplicateSensitiveEvent(.sleepLike, source: source)
        case .wake:
            return await shouldHandleDuplicateSensitiveEvent(.wakeLike, source: source)
        }
    }

    private func shouldHandleDuplicateSensitiveEvent(_ kind: DuplicateEventKind, source: String) async -> Bool {
        await MainActor.run {
            guard self.automationState.isEnabled else {
                AppLogger.power.debug("Ignoring \(kind.logLabel, privacy: .public) event from \(source, privacy: .public) because automation is disabled.")
                return false
            }

            let now = Date()
            let lastEventAt: Date?
            switch kind {
            case .sleepLike:
                lastEventAt = self.lastSleepLikeEventAt
            case .wakeLike:
                lastEventAt = self.lastWakeLikeEventAt
            }

            if let lastEventAt, now.timeIntervalSince(lastEventAt) < Timing.duplicateEventWindow {
                AppLogger.power.debug("Ignoring duplicate \(kind.logLabel, privacy: .public) event from \(source, privacy: .public).")
                return false
            }

            switch kind {
            case .sleepLike:
                self.lastSleepLikeEventAt = now
            case .wakeLike:
                self.lastWakeLikeEventAt = now
            }

            return true
        }
    }

    private func recordProgress(_ message: String) async {
        await MainActor.run {
            self.updateStatus(message)
        }
        AppLogger.app.info("\(message, privacy: .public)")
    }

    private func recordSuccess(_ message: String) async {
        await MainActor.run {
            self.updateStatus(message)
        }
        AppLogger.app.info("\(message, privacy: .public)")
    }

    private func recordFailure(_ message: String) async {
        await MainActor.run {
            self.updateStatus(message)
        }
        AppLogger.app.error("\(message, privacy: .public)")
    }

    private func updateStatus(_ message: String) {
        automationState.lastSyncDescription = message
        automationState.lastSyncAt = Date()
        saveAutomationState()
    }

    private func saveSelectedIdentity() {
        guard let selectedIdentity else {
            defaults.removeObject(forKey: DefaultsKey.selectedSpeakerIdentity)
            return
        }

        if let data = try? JSONEncoder().encode(selectedIdentity) {
            defaults.set(data, forKey: DefaultsKey.selectedSpeakerIdentity)
        }
    }

    private func saveAutomationState() {
        if let data = try? JSONEncoder().encode(automationState) {
            defaults.set(data, forKey: DefaultsKey.automationState)
        }
    }

    private static func loadSelectedIdentity(from defaults: UserDefaults) -> SelectedSpeakerIdentity? {
        guard let data = defaults.data(forKey: DefaultsKey.selectedSpeakerIdentity) else {
            return nil
        }

        return try? JSONDecoder().decode(SelectedSpeakerIdentity.self, from: data)
    }

    private static func loadAutomationState(from defaults: UserDefaults) -> AutomationState {
        guard let data = defaults.data(forKey: DefaultsKey.automationState),
              let state = try? JSONDecoder().decode(AutomationState.self, from: data) else {
            return AutomationState()
        }

        return state
    }

    private func matchesStoredIdentity(_ speaker: DiscoveredSpeaker, selectedIdentity: SelectedSpeakerIdentity) -> Bool {
        if speaker.id == selectedIdentity.kefId {
            return true
        }

        if let serialNumber = selectedIdentity.serialNumber,
           speaker.serialNumber == serialNumber {
            return true
        }

        return speaker.name == selectedIdentity.name && speaker.modelName == selectedIdentity.modelName
    }

    private func describe(_ error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}
