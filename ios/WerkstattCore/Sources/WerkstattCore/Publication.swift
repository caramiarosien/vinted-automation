import Foundation

/// A seller-confirmed public listing is independent of work on the next draft.
public struct ListingPublication: Codable, Equatable, Identifiable {
    public enum Origin: String, Codable { case seller, macImport }
    public var platform: Platform?
    public var url: String
    public var origin: Origin
    public var confirmedAt: Date?
    public var id: String { platform?.rawValue ?? "unknown" }
    public init(platform: Platform? = nil, url: String = "", origin: Origin = .seller, confirmedAt: Date? = nil) {
        self.platform = platform; self.url = url; self.origin = origin; self.confirmedAt = confirmedAt
    }
    public static func isPublicURL(_ value: String) -> Bool {
        guard !value.isEmpty, let parts = URLComponents(string: value),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil else { return false }
        return !parts.path.contains("p-anzeige-aufgeben") && !parts.path.contains("/items/new") &&
            !(parts.queryItems ?? []).contains { $0.name.lowercased() == "draftid" }
    }
}

/// Missing publication fields in existing backups decode as an empty list.
@propertyWrapper public struct PublicationList: Codable, Equatable {
    public var wrappedValue: [ListingPublication]
    public init(wrappedValue: [ListingPublication] = []) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws { wrappedValue = try decoder.singleValueContainer().decode([ListingPublication].self) }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(wrappedValue) }
}
extension KeyedDecodingContainer {
    func decode(_ type: PublicationList.Type, forKey key: Key) throws -> PublicationList {
        try decodeIfPresent(type, forKey: key) ?? PublicationList()
    }
}

public extension Item {
    var hasPublicListing: Bool { !publications.isEmpty || status == .published }
    var displayStatus: ItemStatus {
        if status == .sold || status == .archived { return status }
        return hasPublicListing ? .published : status
    }
}

public enum PublicationHistory {
    /// Recover only the exact marker written by the original Mac importer.
    /// A ready item or a draft URL never proves publication.
    public static func migrate(_ library: Library) -> Library {
        var result = library
        for index in result.items.indices {
            var item = result.items[index]
            guard item.publications.isEmpty, item.answers["_publicationMigrated"] != "1",
                  item.notes.contains("Mac-Fortschritt vor dem Umzug: published.") else { continue }
            let link = ListingPublication.isPublicURL(item.listingURL) ? item.listingURL : ""
            var platform: Platform? = item.platform == .both ? nil : item.platform
            if let host = URL(string: link)?.host {
                if host.contains("vinted.") { platform = .vinted }
                if host == "kleinanzeigen.de" || host == "www.kleinanzeigen.de" { platform = .kleinanzeigen }
            }
            item.publications = [ListingPublication(platform: platform, url: link, origin: .macImport)]
            item.answers["_publicationMigrated"] = "1"
            item.revision += 1
            result.items[index] = item
        }
        return result
    }
}
