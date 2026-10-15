import XCTest
@testable import WerkstattCore

final class ZIPArchiveTests: XCTestCase {
    func testRoundtripPreservesOriginalBytesAndUnicodeNames() throws {
        let entries = ["library.json": Data("{\"schemaVersion\":1}".utf8), "inbox/ä Foto.heic": Data([0, 255, 1, 4, 50]), "bearbeitet/item/photo.jpg": Data(repeating: 123, count: 10_000)]
        let zip = try ZIPArchive.make(entries: entries)
        XCTAssertEqual(try ZIPArchive.read(zip), entries)
        XCTAssertEqual(try ZIPArchive.make(entries: entries), zip)
        XCTAssertEqual(try ZIPArchive.read(ZIPArchive.make(entries: [:])), [:])
    }
    func testTraversalAbsolutePathsAndCaseCollisionsAreRejected() {
        for name in ["../outside", "photos/../../outside", "/etc/file", "C:/outside", "photos\\outside", "photos//file", "photos/./file", "file\u{0000}.jpg"] {
            XCTAssertThrowsError(try ZIPArchive.make(entries: [name: Data()]), name)
        }
        XCTAssertThrowsError(try ZIPArchive.make(entries: ["PHOTO.jpg": Data(), "photo.jpg": Data()]))
    }
    func testCorruptionAndCompressionAreRejected() throws {
        let zip = try ZIPArchive.make(entries: ["photo.jpg": Data([10, 20, 30, 40])])
        var corrupt = zip
        corrupt[30 + "photo.jpg".utf8.count] ^= 1
        XCTAssertThrowsError(try ZIPArchive.read(corrupt))
        var compressed = zip
        let central = compressed.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        compressed[8] = 8
        compressed[central + 10] = 8
        XCTAssertThrowsError(try ZIPArchive.read(compressed)) { XCTAssertTrue($0.localizedDescription.contains("Komprimierte")) }
        XCTAssertThrowsError(try ZIPArchive.read(zip.dropLast()))
    }
    func testReaderRejectsMaliciousPathEvenWhenHeaderIsConsistent() throws {
        var zip = try ZIPArchive.make(entries: ["safe.jpg": Data([1])])
        let bad = Array("../x.jpg".utf8)
        let central = zip.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        for i in bad.indices { zip[30 + i] = bad[i]; zip[central + 46 + i] = bad[i] }
        XCTAssertThrowsError(try ZIPArchive.read(zip)) { XCTAssertTrue($0.localizedDescription.contains("Unsicherer")) }
    }
    func testHugeDeclaredFileIsRejectedBeforeAnyAllocation() throws {
        var zip = try ZIPArchive.make(entries: ["a.jpg": Data()])
        let central = zip.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        let oversized = UInt32(ZIPArchive.maximumEntrySize + 1)
        for base in [central + 20, central + 24] {
            for byte in 0..<4 { zip[base + byte] = UInt8((oversized >> (byte * 8)) & 0xff) }
        }
        XCTAssertThrowsError(try ZIPArchive.read(zip))
    }
    func testEncryptedAndSymlinkEntriesAreRejected() throws {
        var encrypted = try ZIPArchive.make(entries: ["a.jpg": Data()])
        let central = encrypted.range(of: Data([0x50, 0x4b, 0x01, 0x02]))!.lowerBound
        encrypted[central + 8] |= 1
        XCTAssertThrowsError(try ZIPArchive.read(encrypted))
        var symlink = try ZIPArchive.make(entries: ["a.jpg": Data()])
        symlink[central + 41] = 0xa0
        XCTAssertThrowsError(try ZIPArchive.read(symlink))
    }
}
