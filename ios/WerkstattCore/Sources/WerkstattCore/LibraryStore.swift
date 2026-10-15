import Foundation
import CryptoKit

/// Synchronous local storage. Call from the app's main actor or another serial owner.
/// Files are copied before committing metadata; verified obsolete copies are removed
/// afterwards. A crash therefore leaves a recoverable extra copy, never a lost original.
public final class LibraryStore {
    public let root: URL
    private var value: Library
    private var persistedData: Data?
    private static let lock = NSRecursiveLock()
    private let files = FileManager.default

    public var library: Library {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return value
    }

    public init(root: URL) throws {
        guard root.isFileURL else {
            throw WerkstattError.validation("Die Bibliothek benötigt einen lokalen Dateiordner.")
        }
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.value = Library()
        Self.lock.lock(); defer { Self.lock.unlock() }
        try files.createDirectory(at: self.root, withIntermediateDirectories: true)
        for directory in ["inbox", "bearbeitet", "previews", "backups"] {
            try ensureDirectory(directory)
        }
        let metadata = try safeURL("library.json")
        if files.fileExists(atPath: metadata.path) {
            let data = try Data(contentsOf: metadata)
            value = try Self.decoder().decode(Library.self, from: data)
            persistedData = data
            let migrated = PublicationHistory.migrate(value)
            try validate(migrated)
            // Recovery covers an interrupted move and metadata using an older path.
            let normalized = try prepareFiles(for: migrated, verifyAll: true)
            try validate(normalized)
            if normalized != value {
                try commit(normalized)
            }
        } else {
            try commit(value)
        }
    }

    /// Replaces a complete local catalogue, for settings and validated backup restore.
    /// A stale store never silently replaces metadata written by a newer instance.
    public func save(_ library: Library) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try assertCurrent()
        try validate(library)
        let normalized = try prepareFiles(for: library)
        try commit(normalized)
    }

    public func importPhoto(data: Data, filename: String, previewData: Data) throws -> Photo {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try assertCurrent()
        guard !data.isEmpty, !previewData.isEmpty else {
            throw WerkstattError.validation("Das Foto oder seine Vorschau ist leer.")
        }
        let id = Self.digest(data)
        if let existing = value.photos.first(where: { $0.id == id }) {
            // Never replace an original or a seller's existing photo assignment.
            _ = try imageURL(photoID: id)
            return existing
        }
        let cleanName = Self.cleanFilename(filename)
        let photo = Photo(id: id, filename: cleanName,
                          relativePath: "inbox/\(id.prefix(12))-\(cleanName)",
                          previewRelativePath: "previews/\(id).jpg")
        try writeIfAbsent(data, relativePath: photo.relativePath, expectedHash: id)
        try writeIfAbsent(previewData, relativePath: photo.previewRelativePath, expectedHash: nil)
        var next = value
        next.photos.append(photo)
        try validate(next)
        try commit(next)
        return photo
    }

    public func createItem(photoIDs: [String], kind: ProductKind) throws -> Item {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try assertCurrent()
        guard !photoIDs.isEmpty, Set(photoIDs).count == photoIDs.count else {
            throw WerkstattError.validation("Bitte verschiedene Fotos für den Artikel auswählen.")
        }
        for id in photoIDs {
            guard let photo = value.photos.first(where: { $0.id == id }) else {
                throw WerkstattError.missing(id)
            }
            guard photo.itemID == nil else {
                throw WerkstattError.validation("Ein Foto gehört bereits zu einem Artikel. Bitte zuerst umordnen.")
            }
        }
        let item = Item(kind: kind, coverPhotoID: nil,
                        coverReason: "Alle Bilder vergleichen und ein Titelbild auswählen.",
                        photoOrder: photoIDs)
        var next = value
        next.items.append(item)
        for index in next.photos.indices where photoIDs.contains(next.photos[index].id) {
            next.photos[index].itemID = item.id
            next.photos[index].isSelected = true
        }
        try validate(next)
        try commit(prepareFiles(for: next))
        return item
    }

    public func updateItem(_ item: Item, expectedRevision: Int) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try assertCurrent()
        guard let index = value.items.firstIndex(where: { $0.id == item.id }) else {
            throw WerkstattError.missing(item.id)
        }
        let existing = value.items[index]
        guard existing.revision == expectedRevision, item.revision == expectedRevision else {
            throw WerkstattError.conflict
        }
        var updated = item
        updated.createdAt = existing.createdAt
        updated.updatedAt = Date()
        updated.revision = existing.revision + 1
        var next = value
        next.items[index] = updated
        try validate(next)
        try commit(prepareFiles(for: next))
    }

    public func regroup(photoIDs: [String], destinationID: String?) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        try assertCurrent()
        guard !photoIDs.isEmpty, Set(photoIDs).count == photoIDs.count else {
            throw WerkstattError.validation("Bitte verschiedene Fotos zum Umordnen auswählen.")
        }
        if let destinationID, !value.items.contains(where: { $0.id == destinationID }) {
            throw WerkstattError.missing(destinationID)
        }
        for id in photoIDs where !value.photos.contains(where: { $0.id == id }) {
            throw WerkstattError.missing(id)
        }
        var next = value
        var affected = Set<String>()
        for index in next.photos.indices where photoIDs.contains(next.photos[index].id) {
            let old = next.photos[index].itemID
            if old == destinationID { continue }
            if let old { affected.insert(old) }
            next.photos[index].itemID = destinationID
            next.photos[index].isSelected = true
            if let destinationID { affected.insert(destinationID) }
        }
        guard !affected.isEmpty else { return }
        for index in next.items.indices where affected.contains(next.items[index].id) {
            let ids = next.photos.filter { $0.itemID == next.items[index].id }.map(\.id)
            let available = Set(ids)
            let ordered = next.items[index].photoOrder.filter { available.contains($0) }
            next.items[index].photoOrder = ordered + ids.filter { !ordered.contains($0) }
            if let cover = next.items[index].coverPhotoID, !available.contains(cover) {
                next.items[index].coverPhotoID = nil
                next.items[index].coverReason = "Nach dem Umordnen bitte das Titelbild erneut prüfen."
            }
            // Changed evidence requires a fresh review, including previously published items.
            next.items[index].status = .draft
            next.items[index].revision += 1
            next.items[index].updatedAt = Date()
        }
        try validate(next)
        try commit(prepareFiles(for: next))
    }

    public func imageURL(photoID: String, preview: Bool = false) throws -> URL {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let photo = value.photos.first(where: { $0.id == photoID }) else {
            throw WerkstattError.missing(photoID)
        }
        let url = try safeURL(preview ? photo.previewRelativePath : photo.relativePath)
        guard files.fileExists(atPath: url.path) else {
            throw WerkstattError.missing(photo.filename)
        }
        if !preview, try Self.digest(Data(contentsOf: url)) != photo.id {
            throw WerkstattError.validation("Die Originaldatei stimmt nicht mit dem gespeicherten Foto überein.")
        }
        return url
    }

    private func validate(_ library: Library) throws {
        guard library.schemaVersion == 1 else {
            throw WerkstattError.validation("Diese Sicherung verwendet ein unbekanntes Datenformat.")
        }
        guard Set(library.items.map(\.id)).count == library.items.count,
              Set(library.photos.map(\.id)).count == library.photos.count else {
            throw WerkstattError.validation("Artikel oder Fotos sind doppelt eingetragen.")
        }
        let itemIDs = Set(library.items.map(\.id))
        for photo in library.photos {
            guard photo.id.count == 64, photo.id.allSatisfy({ "0123456789abcdef".contains($0) }),
                  photo.filename == Self.cleanFilename(photo.filename) else {
                throw WerkstattError.validation("Ein Foto hat eine ungültige Kennung oder einen ungültigen Dateinamen.")
            }
            _ = try safeURL(photo.relativePath)
            _ = try safeURL(photo.previewRelativePath)
            let originalParts = photo.relativePath.split(separator: "/")
            let previewParts = photo.previewRelativePath.split(separator: "/")
            guard (originalParts.first == "inbox" && originalParts.count == 2) ||
                    (originalParts.first == "bearbeitet" && originalParts.count == 3),
                  previewParts.first == "previews", previewParts.count == 2 else {
                throw WerkstattError.validation("Fotos müssen in den verwalteten Bildordnern liegen.")
            }
            if let id = photo.itemID, !itemIDs.contains(id) {
                throw WerkstattError.validation("Ein Foto verweist auf einen unbekannten Artikel.")
            }
        }
        for item in library.items {
            guard Set(item.publications.map(\.id)).count == item.publications.count,
                  item.publications.allSatisfy({ $0.platform != .both && ($0.url.isEmpty || ListingPublication.isPublicURL($0.url)) }) else {
                throw WerkstattError.validation("Veröffentlichungen benötigen einzelne Plattformen und gültige öffentliche HTTPS-Links.")
            }
            guard Self.safeComponent(item.id), item.revision > 0 else {
                throw WerkstattError.validation("Ein Artikel hat eine ungültige Kennung oder Version.")
            }
            let photos = library.photos.filter { $0.itemID == item.id }
            let ids = Set(photos.map(\.id))
            guard Set(item.photoOrder).count == item.photoOrder.count,
                  Set(item.photoOrder) == ids else {
                throw WerkstattError.validation("Die Bildreihenfolge muss genau die Fotos dieses Artikels enthalten.")
            }
            if let cover = item.coverPhotoID,
               !photos.contains(where: { $0.id == cover && $0.isSelected }) {
                throw WerkstattError.validation("Das Titelbild muss ein ausgewähltes Foto dieses Artikels sein.")
            }
            if let price = item.price, !price.isFinite || price < 0 || price > 1_000_000 {
                throw WerkstattError.validation("Bitte einen gültigen Preis bis 1.000.000 € eingeben.")
            }
            if item.priceType == .free {
                guard item.platform == .kleinanzeigen, item.price == nil || item.price == 0 else {
                    throw WerkstattError.validation("Verschenken ist nur auf Kleinanzeigen mit 0 € möglich.")
                }
            } else if item.price == 0 {
                throw WerkstattError.validation("Bei einem Verkauf muss der Preis größer als 0 € sein.")
            }
            if [.ready, .published, .sold].contains(item.status) {
                let blockers = Questionnaire.blockers(item: item, photos: photos)
                guard blockers.isEmpty else {
                    throw WerkstattError.validation(blockers.joined(separator: "\n"))
                }
            }
        }
    }

    /// Materializes destinations while leaving all source originals intact until commit.
    private func prepareFiles(for library: Library, verifyAll: Bool = false) throws -> Library {
        var normalized = library
        for index in normalized.photos.indices {
            let photo = normalized.photos[index]
            let directory: String
            if let itemID = photo.itemID {
                guard Self.safeComponent(itemID) else {
                    throw WerkstattError.validation("Ungültiger Artikelordner.")
                }
                directory = "bearbeitet/\(itemID)"
            } else { directory = "inbox" }
            let desired = "\(directory)/\(photo.id.prefix(12))-\(photo.filename)"
            let oldURL = try safeURL(photo.relativePath)
            let targetURL = try safeURL(desired)
            let preview = try safeURL(photo.previewRelativePath)
            guard files.fileExists(atPath: preview.path) else {
                throw WerkstattError.missing("Vorschau für \(photo.filename)")
            }
            // Answering one question must not hash the entire photo library again.
            // Restart recovery and original image exports perform full hash checks.
            if !verifyAll, photo.relativePath == desired,
               value.photos.contains(where: { $0.id == photo.id && $0.relativePath == desired }),
               files.fileExists(atPath: targetURL.path) {
                continue
            }
            // If an old implementation moved before committing metadata, locate the
            // byte-identical original by hash within our own two managed directories.
            let source: URL
            if files.fileExists(atPath: oldURL.path) {
                source = oldURL
            } else if files.fileExists(atPath: targetURL.path) {
                source = targetURL
            } else if let recovered = try findOriginal(photo: photo) {
                source = recovered
            } else {
                throw WerkstattError.missing(photo.filename)
            }
            let data = try Data(contentsOf: source)
            guard Self.digest(data) == photo.id else {
                throw WerkstattError.validation("Das Original \(photo.filename) wurde verändert; die Datei bleibt erhalten.")
            }
            try ensureDirectory(directory)
            try writeIfAbsent(data, relativePath: desired, expectedHash: photo.id)
            normalized.photos[index].relativePath = desired
        }
        return normalized
    }

    private func commit(_ library: Library) throws {
        try assertCurrent()
        let data = try Self.encoder().encode(library)
        if let old = persistedData {
            let backup = try safeURL("backups/catalog-\(UUID().uuidString).json")
            try writeNew(old, destination: backup)
        }
        let previous = value
        try data.write(to: safeURL("library.json"), options: .atomic)
        value = library
        persistedData = data
        pruneMetadataBackups()
        // Cleanup is deliberately post-commit and best-effort. If interrupted, the
        // extra original is harmless and can be recovered without changing facts.
        for old in previous.photos {
            guard let new = library.photos.first(where: { $0.id == old.id }),
                  old.relativePath != new.relativePath,
                  let oldURL = try? safeURL(old.relativePath),
                  let oldData = try? Data(contentsOf: oldURL),
                  Self.digest(oldData) == old.id else { continue }
            let referenced = library.photos.contains { $0.relativePath == old.relativePath }
            if !referenced { try? files.removeItem(at: oldURL) }
        }
    }

    private func assertCurrent() throws {
        let metadata = try safeURL("library.json")
        let diskData: Data?
        if files.fileExists(atPath: metadata.path) { diskData = try Data(contentsOf: metadata) }
        else { diskData = nil }
        guard diskData == persistedData else { throw WerkstattError.conflict }
    }

    private func pruneMetadataBackups() {
        guard let directory = try? safeURL("backups"),
              let candidates = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else { return }
        let snapshots = candidates.filter {
            $0.lastPathComponent.hasPrefix("catalog-") && $0.pathExtension == "json"
        }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left > right
        }
        for old in snapshots.dropFirst(30) {
            guard let checked = try? safeURL("backups/\(old.lastPathComponent)") else { continue }
            try? files.removeItem(at: checked)
        }
    }

    private func writeIfAbsent(_ data: Data, relativePath: String, expectedHash: String?) throws {
        let url = try safeURL(relativePath)
        if files.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            let identical = expectedHash.map { Self.digest(existing) == $0 } ?? (existing == data)
            guard identical else {
                throw WerkstattError.validation("Eine andere Datei liegt bereits unter \(relativePath). Sie wird nicht überschrieben.")
            }
            return
        }
        try writeNew(data, destination: url)
    }

    private func writeNew(_ data: Data, destination: URL) throws {
        try ensureDirectory(".staging")
        let temporary = try safeURL(".staging/\(UUID().uuidString)")
        defer { try? files.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        // moveItem refuses to replace an existing destination. An interrupted write
        // can only leave a staging file, not a partial destination original.
        try files.moveItem(at: temporary, to: destination)
    }

    private func findOriginal(photo: Photo) throws -> URL? {
        for directory in ["inbox", "bearbeitet"] {
            let url = try safeURL(directory)
            // Relative enumerator paths avoid macOS /var versus /private/var URL
            // aliases; removing a raw absolute-path prefix could truncate a name.
            guard let enumerator = files.enumerator(atPath: url.path) else { continue }
            for case let relative as String in enumerator {
                let candidate = try safeURL("\(directory)/\(relative)")
                guard candidate.lastPathComponent.hasPrefix(String(photo.id.prefix(12))),
                      let values = try? candidate.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
                if Self.digest(try Data(contentsOf: candidate)) == photo.id { return candidate }
            }
        }
        return nil
    }

    private func ensureDirectory(_ path: String) throws {
        try files.createDirectory(at: safeURL(path), withIntermediateDirectories: true)
    }

    private func safeURL(_ relative: String) throws -> URL {
        let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.isEmpty, !relative.hasPrefix("/"),
              !relative.contains("\\"), !relative.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw WerkstattError.validation("Ungültiger relativer Dateipfad.")
        }
        let target = root.appendingPathComponent(relative).standardizedFileURL
        let resolved = target.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw WerkstattError.validation("Der Dateipfad führt aus der lokalen Bibliothek heraus.")
        }
        return target
    }

    private static func safeComponent(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
    }

    private static func cleanFilename(_ filename: String) -> String {
        let base = (filename as NSString).lastPathComponent
        let scalars = base.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0.value != 47 && $0.value != 92
        }
        let filtered = String(String.UnicodeScalarView(scalars))
        let safe = filtered.isEmpty || filtered == "." || filtered == ".." ? "Foto.jpg" : filtered
        var shortened = safe
        while shortened.utf8.count > 180 { shortened.removeLast() }
        return shortened
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
