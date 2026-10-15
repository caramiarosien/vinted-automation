import Foundation

/// Small dependency-free standard ZIP implementation for packages produced by Werkstatt.
/// Only stored entries (method 0) are supported. Compressed third-party ZIPs fail explicitly.
public enum ZIPArchive {
    public static let maximumEntrySize = 64 * 1_024 * 1_024
    public static let maximumTotalSize = 256 * 1_024 * 1_024
    public static let maximumEntries = 5_000

    public static func make(entries: [String: Data]) throws -> Data {
        guard entries.count <= maximumEntries else { throw error("Zu viele Dateien im ZIP.") }
        var output = Data(), central = Data(), seen = Set<String>(), total = 0
        for name in entries.keys.sorted() {
            try validate(name: name, seen: &seen)
            let payload = entries[name]!
            guard payload.count <= maximumEntrySize, total <= maximumTotalSize - payload.count else {
                throw error("ZIP zu groß: höchstens 64 MB je Datei und 256 MB insgesamt.")
            }
            total += payload.count
            let path = Data(name.utf8), crc = checksum(payload), offset = UInt32(output.count)
            output.u32(0x04034b50); output.u16(20); output.u16(0x0800); output.u16(0)
            output.u16(0); output.u16(0x0021); output.u32(crc)
            output.u32(UInt32(payload.count)); output.u32(UInt32(payload.count))
            output.u16(UInt16(path.count)); output.u16(0); output.append(path); output.append(payload)
            central.u32(0x02014b50); central.u16(20); central.u16(20); central.u16(0x0800); central.u16(0)
            central.u16(0); central.u16(0x0021); central.u32(crc)
            central.u32(UInt32(payload.count)); central.u32(UInt32(payload.count))
            central.u16(UInt16(path.count)); central.u16(0); central.u16(0)
            central.u16(0); central.u16(0); central.u32(0); central.u32(offset); central.append(path)
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.u32(0x06054b50); output.u16(0); output.u16(0)
        output.u16(UInt16(entries.count)); output.u16(UInt16(entries.count))
        output.u32(UInt32(central.count)); output.u32(centralOffset); output.u16(0)
        return output
    }

    public static func read(_ data: Data) throws -> [String: Data] {
        // Bounding encoded size also prevents a huge untrusted central directory.
        guard data.count >= 22, data.count <= maximumTotalSize + 12 * 1_024 * 1_024 else { throw error("Ungültiges oder zu großes ZIP.") }
        let b = [UInt8](data)
        let end = b.count - 22
        // Our packages carry no archive comment. Accepting arbitrary trailing data is unnecessary.
        guard try number(b, end, 4) == 0x06054b50,
              try number(b, end + 20, 2) == 0 else { throw error("ZIP-Endverzeichnis fehlt oder enthält einen nicht unterstützten Kommentar.") }
        guard try number(b, end + 4, 2) == 0, try number(b, end + 6, 2) == 0 else { throw error("Mehrteilige ZIPs werden nicht unterstützt.") }
        let count = Int(try number(b, end + 10, 2))
        guard count <= maximumEntries, try number(b, end + 8, 2) == UInt32(count) else { throw error("Ungültige Anzahl ZIP-Dateien.") }
        let centralSize = Int(try number(b, end + 12, 4)), centralOffset = Int(try number(b, end + 16, 4))
        guard centralOffset <= end, centralSize == end - centralOffset else { throw error("Ungültiges ZIP-Verzeichnis.") }
        var cursor = centralOffset, seen = Set<String>(), result: [String: Data] = [:], total = 0
        var ranges: [Range<Int>] = []
        for _ in 0..<count {
            guard cursor <= end - 46, try number(b, cursor, 4) == 0x02014b50 else { throw error("Ungültiger ZIP-Eintrag.") }
            let flags = try number(b, cursor + 8, 2), method = try number(b, cursor + 10, 2)
            try validate(flags: flags, method: method)
            let crc = try number(b, cursor + 16, 4)
            let compressed = Int(try number(b, cursor + 20, 4)), size = Int(try number(b, cursor + 24, 4))
            let nameSize = Int(try number(b, cursor + 28, 2)), extra = Int(try number(b, cursor + 30, 2)), comment = Int(try number(b, cursor + 32, 2))
            let external = try number(b, cursor + 38, 4)
            let unixMode = (external >> 16) & 0xf000
            guard unixMode != 0xa000, try number(b, cursor + 34, 2) == 0 else { throw error("Verknüpfungen oder mehrteilige ZIP-Einträge sind nicht erlaubt.") }
            guard size <= maximumEntrySize, total <= maximumTotalSize - size, compressed == size else { throw error("Ungültige Dateigröße oder ZIP zu groß.") }
            guard nameSize > 0, nameSize <= 1_024, cursor + 46 <= end - nameSize - extra - comment else { throw error("Ungültiger ZIP-Dateiname.") }
            let pathBytes = Array(b[(cursor + 46)..<(cursor + 46 + nameSize)])
            guard let name = String(bytes: pathBytes, encoding: .utf8) else { throw error("ZIP-Dateinamen müssen UTF-8 sein.") }
            try validate(name: name, seen: &seen)
            let offset = Int(try number(b, cursor + 42, 4))
            guard offset <= centralOffset - 30, try number(b, offset, 4) == 0x04034b50 else { throw error("Lokaler ZIP-Dateikopf fehlt.") }
            guard try number(b, offset + 6, 2) == flags,
                  try number(b, offset + 8, 2) == method,
                  try number(b, offset + 14, 4) == crc,
                  try number(b, offset + 18, 4) == UInt32(compressed),
                  try number(b, offset + 22, 4) == UInt32(size),
                  try number(b, offset + 26, 2) == UInt32(nameSize) else { throw error("ZIP-Dateiköpfe widersprechen sich.") }
            let localExtra = Int(try number(b, offset + 28, 2))
            let start = offset + 30 + nameSize + localExtra
            guard start <= centralOffset, size <= centralOffset - start else { throw error("ZIP-Datei ist abgeschnitten.") }
            guard Array(b[(offset + 30)..<(offset + 30 + nameSize)]) == pathBytes else { throw error("ZIP-Dateinamen widersprechen sich.") }
            let range = offset..<(start + size)
            guard !ranges.contains(where: { $0.overlaps(range) }) else { throw error("ZIP-Einträge überlappen sich.") }
            ranges.append(range)
            let payload = Data(b[start..<(start + size)])
            guard checksum(payload) == crc else { throw error("ZIP-Prüfsumme stimmt nicht: \(name)") }
            result[name] = payload
            total += size
            cursor += 46 + nameSize + extra + comment
        }
        guard cursor == end else { throw error("ZIP-Verzeichnis enthält unerwartete Daten.") }
        return result
    }
    private static func validate(name: String, seen: inout Set<String>) throws {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty, name.utf8.count <= 1_024,
              !name.contains("\\"), !name.contains(":"),
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
              !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { throw error("Unsicherer ZIP-Pfad: \(name)") }
        let key = name.precomposedStringWithCanonicalMapping.lowercased()
        guard seen.insert(key).inserted else { throw error("Doppelter ZIP-Pfad: \(name)") }
    }
    private static func validate(flags: UInt32, method: UInt32) throws {
        guard flags & 1 == 0 else { throw error("Verschlüsselte ZIPs werden nicht unterstützt.") }
        guard method == 0 else { throw error("Komprimierte ZIPs werden nicht unterstützt. Bitte als unkomprimiertes Werkstatt-ZIP exportieren.") }
        guard flags & ~UInt32(0x0800) == 0 else { throw error("Nicht unterstützte ZIP-Optionen.") }
    }
    private static func number(_ bytes: [UInt8], _ offset: Int, _ width: Int) throws -> UInt32 {
        guard offset >= 0, offset <= bytes.count - width else { throw error("ZIP ist abgeschnitten.") }
        var value: UInt32 = 0
        for i in 0..<width { value |= UInt32(bytes[offset + i]) << UInt32(i * 8) }
        return value
    }
    private static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = (crc >> 8) ^ crcTable[Int((crc ^ UInt32(byte)) & 0xff)] }
        return crc ^ 0xffffffff
    }
    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb88320 : 0) }
        return value
    }
    private static func error(_ message: String) -> WerkstattError { .validation(message) }
}

private extension Data {
    mutating func u16(_ value: UInt16) { append(UInt8(value & 0xff)); append(UInt8((value >> 8) & 0xff)) }
    mutating func u32(_ value: UInt32) { for offset in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> offset) & 0xff)) } }
}
