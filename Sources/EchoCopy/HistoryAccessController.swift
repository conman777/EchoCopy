import AppKit
import Combine
import LocalAuthentication
import OSLog

@MainActor
protocol HistoryAuthenticating: AnyObject {
    func authenticate(_ reply: @escaping (Bool, String?) -> Void)
    func cancel()
}

@MainActor
final class TouchIDHistoryAuthenticator: HistoryAuthenticating {
    private var context: LAContext?

    func authenticate(_ reply: @escaping (Bool, String?) -> Void) {
        let context = LAContext()
        self.context = context
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            reply(false, "Touch ID is unavailable. Enable Touch ID in System Settings, or unlock your Mac to re-enable it after a lockout. Your saved history is unchanged.")
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Access your EchoCopy clipboard history."
        ) { success, error in
            let cancelled = (error as? LAError).map {
                [.userCancel, .systemCancel, .appCancel].contains($0.code)
            } ?? false
            DispatchQueue.main.async {
                reply(success, success || cancelled ? nil : "History remains locked. Try again with Touch ID.")
            }
        }
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }
}

/// An ephemeral UI authorization, independent of clipboard capture and storage.
/// Never persisted: each app launch starts locked. Locking invalidates in-flight
/// replies so an authentication completed after sleep/dismissal cannot reopen UI.
@MainActor
final class HistoryAccessController: ObservableObject {
    private static let logger = Logger(subsystem: "com.yourcompany.echocopy", category: "history-access")
    @Published private(set) var isUnlocked = false
    private(set) var isAuthenticating = false
    private var requestID: UUID?
    private let authenticator: HistoryAuthenticating
    private let canPresent: @MainActor () -> Bool
    private var observers: [AnyCancellable] = []

    init(
        authenticator: HistoryAuthenticating? = nil,
        observeLifecycle: Bool = true,
        // The native Touch ID sheet may own focus when its reply arrives.
        // Request invalidation, rather than NSApp.isActive, guards late replies.
        canPresent: @escaping @MainActor () -> Bool = { true }
    ) {
        self.authenticator = authenticator ?? TouchIDHistoryAuthenticator()
        self.canPresent = canPresent
        guard observeLifecycle else { return }
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                // LocalAuthentication may temporarily take application focus.
                MainActor.assumeIsolated {
                    guard let self, !self.isAuthenticating else { return }
                    self.lock()
                }
            }.store(in: &observers)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated { self?.lock() }
                }.store(in: &observers)
        }
        DistributedNotificationCenter.default().publisher(
            for: Notification.Name("com.apple.screenIsLocked")
        ).receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.lock() }
        }.store(in: &observers)
    }

    func unlock(onFailure: @escaping (String) -> Void, then action: @escaping () -> Void) {
        if isUnlocked { action(); return }
        guard !isAuthenticating else { return }
        let id = UUID()
        requestID = id
        isAuthenticating = true
        Self.logger.notice("History authentication requested")
        authenticator.authenticate { [weak self] success, message in
            guard let self, self.requestID == id else { return }
            self.requestID = nil
            self.isAuthenticating = false
            self.authenticator.cancel()
            guard success else {
                Self.logger.notice("History authentication cancelled or failed")
                if let message { onFailure(message) }
                return
            }
            guard self.canPresent() else { return }
            Self.logger.notice("History authentication succeeded")
            self.isUnlocked = true
            action()
        }
    }

    private var isLocking = false

    func lock() {
        guard !isLocking else { return }
        isLocking = true
        defer { isLocking = false }
        requestID = nil
        isAuthenticating = false
        authenticator.cancel()
        if isUnlocked { isUnlocked = false }
        Self.logger.debug("History access locked")
    }
}
