import AppKit
import XCTest
@testable import EchoCopy

@MainActor
final class WindowLifecycleTests: XCTestCase {
    func testMinimizeClosesWindowAndClearsDelegateOwnership() {
        let appDelegate = AppDelegate()
        for useAction in [false, true] {
            let window = MenuBarWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            appDelegate.applyWindowBehavior(to: window)

            if useAction {
                window.performMiniaturize(nil)
            } else {
                window.miniaturize(nil)
            }

            XCTAssertNil(appDelegate.mainWindow)
            XCTAssertFalse(window.isMiniaturized)
        }
    }

    func testCommandMClosesHistoryWindow() throws {
        let appDelegate = AppDelegate()
        let window = MenuBarWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        appDelegate.applyWindowBehavior(to: window)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "m",
            charactersIgnoringModifiers: "m",
            isARepeat: false,
            keyCode: 46
        ))

        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertNil(appDelegate.mainWindow)
        XCTAssertFalse(window.isMiniaturized)
    }

    func testConfiguredWindowDoesNotSelfReleaseWhenClosed() {
        let appDelegate = AppDelegate()
        let window = MenuBarWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        appDelegate.applyWindowBehavior(to: window)

        XCTAssertFalse(
            window.isReleasedWhenClosed,
            "Swift ARC must remain the sole owner of the window lifecycle"
        )
    }
}
