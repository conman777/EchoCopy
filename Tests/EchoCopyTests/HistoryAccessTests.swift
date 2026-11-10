import AppKit
import XCTest
@testable import EchoCopy

@MainActor
final class HistoryAccessTests: XCTestCase {
    func testStartsLockedAndRequiresSuccessfulAuthentication() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, observeLifecycle: false, canPresent: { true })
        var presentations = 0
        XCTAssertFalse(access.isUnlocked)
        access.unlock(onFailure: { _ in XCTFail("Unexpected failure") }) { presentations += 1 }
        XCTAssertEqual(presentations, 0)
        XCTAssertFalse(access.isUnlocked)
        auth.reply?(true, nil)
        XCTAssertTrue(access.isUnlocked)
        XCTAssertEqual(presentations, 1)
        access.lock()
        access.unlock(onFailure: { _ in XCTFail("Unexpected failure") }) { presentations += 1 }
        XCTAssertEqual(auth.attempts, 2, "Reopening must require fresh authentication")
        XCTAssertEqual(presentations, 1)
    }

    func testSuccessfulTouchIDDoesNotRequireApplicationFocus() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, observeLifecycle: false)
        var presented = false
        access.unlock(onFailure: { _ in XCTFail("Unexpected failure") }) { presented = true }
        auth.reply?(true, nil)
        XCTAssertTrue(presented, "The system authentication sheet may still own focus")
        XCTAssertTrue(access.isUnlocked)
    }

    func testCancellationOrFailureNeverPresentsHistory() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, observeLifecycle: false, canPresent: { true })
        var failure: String?
        access.unlock(onFailure: { failure = $0 }) { XCTFail("Must remain locked") }
        auth.reply?(false, "Cancelled")
        XCTAssertFalse(access.isUnlocked)
        XCTAssertEqual(failure, "Cancelled")
    }

    func testScreenLockInvalidatesLateSuccessfulReply() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, observeLifecycle: false, canPresent: { true })
        access.unlock(onFailure: { _ in XCTFail("Stale callback") }) { XCTFail("Stale authentication opened history") }
        let staleReply = auth.reply
        access.lock()
        staleReply?(true, nil)
        XCTAssertFalse(access.isUnlocked)
        access.unlock(onFailure: { _ in XCTFail("Unexpected failure") }) {}
        staleReply?(true, nil)
        XCTAssertFalse(access.isUnlocked, "An older reply cannot authorize a newer request")
        auth.reply?(true, nil)
        XCTAssertTrue(access.isUnlocked)
    }

    func testAuthenticationCannotPresentAfterLeavingApp() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, observeLifecycle: false, canPresent: { false })
        access.unlock(onFailure: { _ in }) { XCTFail("App is no longer active") }
        auth.reply?(true, nil)
        XCTAssertFalse(access.isUnlocked)
    }

    func testRepeatedClicksDoNotStartMultipleAuthenticationPrompts() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, observeLifecycle: false, canPresent: { true })
        access.unlock(onFailure: { _ in }) {}
        access.unlock(onFailure: { _ in }) { XCTFail("Duplicate presentation") }
        XCTAssertEqual(auth.attempts, 1)
    }

    func testLeavingAppRevokesAuthorization() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, canPresent: { true })
        access.unlock(onFailure: { _ in XCTFail("Unexpected failure") }) {}
        auth.reply?(true, nil)
        XCTAssertTrue(access.isUnlocked)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertFalse(access.isUnlocked)
    }

    func testSleepCancelsPendingAuthentication() {
        let auth = StubHistoryAuthenticator()
        let access = HistoryAccessController(authenticator: auth, canPresent: { true })
        access.unlock(onFailure: { _ in }) { XCTFail("Sleeping must revoke authentication") }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        auth.reply?(true, nil)
        XCTAssertFalse(access.isUnlocked)
    }

    func testHistorySurvivesLockAndRestartIncludingPinnedAndRichText() throws {
        let suite = "EchoCopyTests.Access.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = EncryptedHistoryStore(defaults: defaults, storageKey: "history",
            encryptionVersionKey: "version", keyProvider: AccessTestKeyProvider())
        let items = [ClipboardItem(content: "example secret", isPinned: true,
                                   rtfContent: Data("example rich text".utf8).base64EncodedString()),
                     ClipboardItem(content: "https://example.com", contentType: .url)]
        try store.save(items, maximumPlaintextBytes: ClipboardPolicy.maxHistoryBytes)
        let original = defaults.data(forKey: "history")
        let history = ClipboardHistory(historyStore: store)
        let access = HistoryAccessController(authenticator: StubHistoryAuthenticator(), observeLifecycle: false)
        access.lock()
        XCTAssertEqual(defaults.data(forKey: "history"), original, "Locking must not rewrite history")
        history.flushPersistence()
        let restarted = ClipboardHistory(historyStore: store)
        XCTAssertEqual(restarted.items.map(\.id), items.map(\.id))
        XCTAssertEqual(restarted.items.map(\.content), items.map(\.content))
        XCTAssertEqual(restarted.items.first?.rtfContent, items.first?.rtfContent)
        XCTAssertTrue(restarted.items.first?.isPinned == true)
        XCTAssertFalse(HistoryAccessController(authenticator: StubHistoryAuthenticator(), observeLifecycle: false).isUnlocked)
    }
}

@MainActor
private final class StubHistoryAuthenticator: HistoryAuthenticating {
    var reply: ((Bool, String?) -> Void)?
    var attempts = 0
    func authenticate(_ reply: @escaping (Bool, String?) -> Void) {
        attempts += 1
        self.reply = reply
    }
    func cancel() {}
}

private final class AccessTestKeyProvider: HistoryKeyProviding {
    func loadKeyData() throws -> Data? { Data(repeating: 17, count: 32) }
    func createKeyData() throws -> Data { Data(repeating: 17, count: 32) }
}
