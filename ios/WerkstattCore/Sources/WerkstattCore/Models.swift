import Foundation

public enum ProductKind: String, Codable, CaseIterable {
    case smartwatch, headphones, chair, supplies, other
    public var label: String {
        switch self {
        case .smartwatch: return "Smartwatch"
        case .headphones: return "Kopfhörer"
        case .chair: return "Stuhl"
        case .supplies: return "Bastelmaterial"
        case .other: return "Anderer Artikel"
        }
    }
}

public enum Platform: String, Codable, CaseIterable {
    case vinted, kleinanzeigen, both
    public var label: String {
        switch self {
        case .vinted: return "Vinted"
        case .kleinanzeigen: return "Kleinanzeigen"
        case .both: return "Beide Plattformen"
        }
    }
}

public enum PriceType: String, Codable, CaseIterable {
    case fixed, negotiable, free
    public var label: String {
        switch self {
        case .fixed: return "Festpreis"
        case .negotiable: return "Verhandlungsbasis"
        case .free: return "Zu verschenken"
        }
    }
}

public enum ItemStatus: String, Codable, CaseIterable {
    case draft, ready, published, sold, archived
    public var label: String {
        switch self {
        case .draft: return "In Prüfung"
        case .ready: return "Bereit"
        case .published: return "Eingestellt"
        case .sold: return "Verkauft"
        case .archived: return "Archiv"
        }
    }
}

public struct Photo: Codable, Equatable, Identifiable {
    public var id: String
    public var filename: String
    public var relativePath: String
    public var previewRelativePath: String
    public var itemID: String?
    public var isSelected: Bool
    public var importedAt: Date

    public init(id: String = "", filename: String = "", relativePath: String = "", previewRelativePath: String = "", itemID: String? = nil, isSelected: Bool = true, importedAt: Date = Date()) {
        self.id = id; self.filename = filename; self.relativePath = relativePath
        self.previewRelativePath = previewRelativePath; self.itemID = itemID
        self.isSelected = isSelected; self.importedAt = importedAt
    }
}

public struct PriceSource: Codable, Equatable {
    public var title: String
    public var url: String
    public var checked: String
    public var price: Double?
    public var note: String
    public var kind: String

    public init(title: String = "", url: String = "", checked: String = "", price: Double? = nil, note: String = "", kind: String = "asking") {
        self.title = title; self.url = url; self.checked = checked
        self.price = price; self.note = note; self.kind = kind
    }
}

public struct Item: Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var description: String
    public var brand: String
    public var category: String
    public var color: String
    public var variant: String
    public var kind: ProductKind
    public var condition: String
    public var price: Double?
    public var platform: Platform
    public var priceType: PriceType
    public var status: ItemStatus
    public var coverPhotoID: String?
    public var coverReason: String
    public var photoOrder: [String]
    public var answers: [String: String]
    public var facts: [String]
    public var questions: [String]
    public var sources: [PriceSource]
    public var pricingNote: String
    public var notes: String
    public var listingURL: String
    @PublicationList public var publications: [ListingPublication] = []
    public var revision: Int
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String = "", description: String = "", brand: String = "", category: String = "", color: String = "", variant: String = "", kind: ProductKind = .other, condition: String = "", price: Double? = nil, platform: Platform = .kleinanzeigen, priceType: PriceType = .negotiable, status: ItemStatus = .draft, coverPhotoID: String? = nil, coverReason: String = "", photoOrder: [String] = [], answers: [String: String] = [:], facts: [String] = [], questions: [String] = [], sources: [PriceSource] = [], pricingNote: String = "", notes: String = "", listingURL: String = "", publications: [ListingPublication] = [], revision: Int = 1, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id; self.title = title; self.description = description
        self.brand = brand; self.category = category; self.color = color; self.variant = variant
        self.kind = kind; self.condition = condition; self.price = price
        self.platform = platform; self.priceType = priceType; self.status = status
        self.coverPhotoID = coverPhotoID; self.coverReason = coverReason; self.photoOrder = photoOrder
        self.answers = answers; self.facts = facts; self.questions = questions; self.sources = sources
        self.pricingNote = pricingNote; self.notes = notes; self.listingURL = listingURL
        self.publications = publications
        self.revision = revision; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct Library: Codable, Equatable {
    public var schemaVersion: Int
    public var photos: [Photo]
    public var items: [Item]
    public var defaultLocation: String

    public init(schemaVersion: Int = 1, photos: [Photo] = [], items: [Item] = [], defaultLocation: String = "Konstanz") {
        self.schemaVersion = schemaVersion; self.photos = photos
        self.items = items; self.defaultLocation = defaultLocation
    }
}

public enum WerkstattError: Error, LocalizedError, Equatable {
    case validation(String)
    case conflict
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .validation(let message): return message
        case .conflict: return "Der Artikel wurde inzwischen geändert. Bitte erneut öffnen."
        case .missing(let value): return "Nicht gefunden: \(value)"
        }
    }
}
