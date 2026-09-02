import AppKit
import Carbon.HIToolbox
import XCTest
@testable import EchoCopy

final class PasteSupportTests: XCTestCase {
    func testLargeClipboardTextUsesBoundedRowPreviews() {
        let item = ClipboardItem(
            content: String(repeating: "A", count: 20_000) + "\nsecret tail"
        )

        XCTAssertLessThanOrEqual(item.menuPreview.count, 46)
        XCTAssertLessThanOrEqual(item.listPreview.count, 240)
        XCTAssertFalse(item.listPreview.contains("secret tail"))
    }

    func testMenuHistoryIncludesMoreThanTenItemsAndKeepsPinnedItemsFirst() {
        let items = (0..<12).map { index in
            ClipboardItem(
                content: "Item \(index)",
                isPinned: index == 3 || index == 8
            )
        }

        let ordered = MenuBarHistoryPresentation.orderedItems(items)

        XCTAssertEqual(ordered.count, 12)
        XCTAssertEqual(
            ordered.map(\.id),
            [items[3], items[8]]
                .map(\.id)
                + items.enumerated()
                    .filter { $0.offset != 3 && $0.offset != 8 }
                    .map { $0.element.id }
        )
    }

    func testMenuHistoryShowsAtMostTenRowsWithoutTruncatingItsItems() {
        XCTAssertEqual(MenuBarHistoryPresentation.visibleRowCount(for: 0), 0)
        XCTAssertEqual(MenuBarHistoryPresentation.visibleRowCount(for: 6), 6)
        XCTAssertEqual(MenuBarHistoryPresentation.visibleRowCount(for: 10), 10)
        XCTAssertEqual(MenuBarHistoryPresentation.visibleRowCount(for: 98), 10)
        XCTAssertEqual(
            MenuBarHistoryView.contentHeight(for: 98),
            275
        )
    }

    func testPasteEventsAreCommandVDownAndUp() throws {
        let events = try XCTUnwrap(
            PasteKeyboardEventFactory.makeCommandVEvents()
        )

        XCTAssertEqual(events.keyDown.type, .keyDown)
        XCTAssertEqual(events.keyUp.type, .keyUp)
        XCTAssertEqual(
            CGKeyCode(events.keyDown.getIntegerValueField(.keyboardEventKeycode)),
            CGKeyCode(kVK_ANSI_V)
        )
        XCTAssertEqual(events.keyDown.flags, .maskCommand)
        XCTAssertEqual(events.keyUp.flags, .maskCommand)
    }
}
