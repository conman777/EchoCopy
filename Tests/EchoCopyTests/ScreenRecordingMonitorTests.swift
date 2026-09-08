import AppKit
import AVFoundation
import XCTest
@testable import EchoCopy

final class ScreenCaptureFileMonitorTests: XCTestCase {
    func testIgnoresExistingMoviesAndWaitsForNewFileToStopGrowing() {
        var tracker = ScreenRecordingTracker()
        let now = Date()
        let old = candidate("old", size: 10, date: now)
        let fresh = candidate("new", size: 10, date: now)
        XCTAssertTrue(tracker.update([old], now: now).isEmpty)
        XCTAssertTrue(tracker.update([old, fresh], now: now).isEmpty)
        let growing = candidate("new", size: 20, date: now.addingTimeInterval(2))
        XCTAssertTrue(tracker.update([old, growing], now: now.addingTimeInterval(3)).isEmpty)
        XCTAssertTrue(tracker.update([old, growing], now: now.addingTimeInterval(5)).isEmpty)
        XCTAssertEqual(tracker.update([old, growing], now: now.addingTimeInterval(7)), [growing])
        tracker.markCopied(growing.url)
        XCTAssertTrue(tracker.update([old, growing], now: now.addingTimeInterval(15)).isEmpty)
    }

    func testDeletedPendingRecordingIsNotCopied() {
        var tracker = ScreenRecordingTracker()
        let now = Date()
        _ = tracker.update([], now: now)
        _ = tracker.update([candidate("deleted", size: 10, date: now)], now: now)
        XCTAssertTrue(tracker.update([], now: now.addingTimeInterval(10)).isEmpty)
    }

    func testFolderScanIgnoresUnrelatedMoviesAndSymbolicLinks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recording = folder.appendingPathComponent("Screen Recording test.mov")
        try Data([1, 2, 3]).write(to: recording)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("unrelated.mov"))
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("Screen Recording test.png"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Screen Recording link.mov"), withDestinationURL: recording)
        XCTAssertEqual(try ScreenRecordingCandidate.scan(directory: folder).map { $0.url.resolvingSymlinksInPath() }, [recording.resolvingSymlinksInPath()])
    }

    @MainActor
    func testRecordingCopiesAsFileAttachmentRatherThanText() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let url = URL(fileURLWithPath: "/private/tmp/Screen Recording synthetic.mov")
        XCTAssertTrue(PasteboardWriter.write(
            ClipboardItem(content: url.absoluteString, contentType: .file, filename: url.lastPathComponent),
            to: pasteboard, writeTracker: PasteboardWriteTracker()
        ))
        let urls = try XCTUnwrap(pasteboard.readObjects(forClasses: [NSURL.self]) as? [NSURL])
        XCTAssertEqual(urls.first as URL?, url)
        XCTAssertTrue(pasteboard.types?.contains(.fileURL) == true)
    }

    @MainActor
    func testLiveMonitorCopiesFinishedVideoAndStopsWhenDisabled() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "EchoCopyRecordingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ScreenCaptureFileMonitor.preferenceKey)
        let copied = expectation(description: "Finished recording copied")
        let recording = folder.appendingPathComponent("Screen Recording synthetic.mov")
        var received: [URL] = []
        let monitor = ScreenCaptureFileMonitor(defaults: defaults, destination: { folder }) { url in
            received.append(url)
            copied.fulfill()
            return true
        }
        monitor.start()
        defer { monitor.stop() }
        // Allow the initial inventory to complete before producing a new file.
        for _ in 0..<50 where !monitor.status.hasPrefix("Watching") {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(monitor.status.hasPrefix("Watching"))
        try await makeVideo(at: recording)
        await fulfillment(of: [copied], timeout: 15)
        XCTAssertEqual(received.map { $0.resolvingSymlinksInPath() }, [recording.resolvingSymlinksInPath()])
        defaults.set(false, forKey: ScreenCaptureFileMonitor.preferenceKey)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(monitor.status, "")
        try await makeVideo(at: folder.appendingPathComponent("Screen Recording disabled.mov"))
        try await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertEqual(received.count, 1)
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var optionalBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64,
            kCVPixelFormatType_32ARGB, nil, &optionalBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(adaptor.append(buffer, withPresentationTime: .zero))
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 30))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    @MainActor
    func testScreenshotMonitorCopiesOnlyNewSavedImages() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "EchoCopyScreenshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ScreenshotCaptureCoordinator.automaticClipboardPreferenceKey)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: folder.appendingPathComponent("Screenshot old.png"))
        let copied = expectation(description: "New saved screenshot")
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var copyAttempts = 0
        var savedAt = Date()
        let monitor = ScreenCaptureFileMonitor(defaults: defaults, screenshots: true, destination: { folder }) { url in
            copyAttempts += 1
            // A temporary read/pasteboard failure must retry the same file.
            if copyAttempts == 1 { return false }
            XCTAssertEqual(url.lastPathComponent, "Screenshot new.png")
            XCTAssertLessThan(Date().timeIntervalSince(savedAt), 1.5,
                              "Folder events should bypass the two-second polling interval")
            let item = ClipboardItem(content: data.base64EncodedString(), contentType: .image)
            XCTAssertTrue(PasteboardWriter.write(item, to: pasteboard))
            copied.fulfill()
            return true
        }
        monitor.start()
        defer { monitor.stop() }
        for _ in 0..<50 where !monitor.status.hasPrefix("Watching") {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(monitor.status.hasPrefix("Watching"))
        try data.write(to: folder.appendingPathComponent("unrelated.png"))
        savedAt = Date()
        try data.write(to: folder.appendingPathComponent("Screenshot new.png"))
        await fulfillment(of: [copied], timeout: 15)
        XCTAssertEqual(pasteboard.data(forType: .png), data)
        XCTAssertEqual(copyAttempts, 2)
        XCTAssertEqual(monitor.status, "Screenshot copied. Ready to paste.")
    }

    private func candidate(_ name: String, size: Int, date: Date) -> ScreenRecordingCandidate {
        ScreenRecordingCandidate(url: URL(fileURLWithPath: "/private/tmp/\(name).mov"), size: size, modified: date)
    }
}
