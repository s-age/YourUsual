import XCTest
@testable import YourUsual

/// Verifies the scroll-buffer accumulator: blank-line preservation, partial-line
/// assembly across chunks, keep-newest-N-lines eviction, and the dropped-lines marker.
final class BoundedLineBufferTests: XCTestCase {

    func testText_underLimit_joinsLinesWithoutTrailingNewline() {
        var sut = BoundedLineBuffer(maxLines: 100)
        sut.append("a\nb\nc")
        XCTAssertEqual(sut.text, "a\nb\nc")
    }

    func testText_assemblesPartialLineSplitAcrossChunks() {
        var sut = BoundedLineBuffer(maxLines: 100)
        sut.append("hel")
        sut.append("lo\nworld")
        XCTAssertEqual(sut.text, "hello\nworld")
    }

    func testText_preservesBlankLines() {
        var sut = BoundedLineBuffer(maxLines: 100)
        sut.append("a\n\nb")
        XCTAssertEqual(sut.text, "a\n\nb")
    }

    func testText_trailingNewlineDoesNotAddEmptyPending() {
        var sut = BoundedLineBuffer(maxLines: 100)
        sut.append("a\nb\n")
        XCTAssertEqual(sut.text, "a\nb")
    }

    func testText_keepsOnlyNewestLines_whenOverLineLimit() {
        var sut = BoundedLineBuffer(maxLines: 2)
        sut.append("1\n2\n3\n4\n")   // four completed lines, keep last two
        XCTAssertEqual(sut.text, "… (earlier output dropped; keeping the last 2 lines)\n3\n4")
    }

    func testText_partialTailIsShownButNotCountedTowardTheLimit() {
        var sut = BoundedLineBuffer(maxLines: 2)
        sut.append("1\n2\n3")        // "1","2" completed (== limit, no eviction) + "3" pending
        XCTAssertEqual(sut.text, "1\n2\n3")
    }

    func testText_evictsCompletedLines_thenAppendsPartialTail() {
        var sut = BoundedLineBuffer(maxLines: 2)
        sut.append("1\n2\n3\n4")     // "1","2","3" completed (evicts "1") + "4" pending
        XCTAssertEqual(sut.text, "… (earlier output dropped; keeping the last 2 lines)\n2\n3\n4")
    }

    func testText_noMarker_whenExactlyAtLimit() {
        var sut = BoundedLineBuffer(maxLines: 3)
        sut.append("1\n2\n3")
        XCTAssertEqual(sut.text, "1\n2\n3")
    }

    func testAppend_overlongNewlineFreeLine_isFlushedTruncated() {
        var sut = BoundedLineBuffer(maxLines: 100)
        // 2 MiB with no newline — must not be retained whole; it is flushed truncated.
        sut.append(String(repeating: "x", count: 2 << 20))
        XCTAssertTrue(sut.text.hasSuffix("… (line truncated)"))
        XCTAssertLessThan(sut.text.utf8.count, (1 << 20) + 64)
    }

    func testInit_clampsNonPositiveLinesToAtLeastOne() {
        var sut = BoundedLineBuffer(maxLines: 0)
        sut.append("1\n2\n")
        XCTAssertEqual(sut.text, "… (earlier output dropped; keeping the last 1 lines)\n2")
    }
}
