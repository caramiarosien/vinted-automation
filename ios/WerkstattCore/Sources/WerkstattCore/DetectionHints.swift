import Foundation

public struct DetectionSuggestion: Equatable {
    public let kind: ProductKind
    public let brand: String
    public let title: String
    public let color: String
    public init(kind: ProductKind, brand: String = "", title: String = "", color: String = "") {
        self.kind = kind; self.brand = brand; self.title = title; self.color = color
    }
}

public enum DetectionHints {
    /// OCR recognizes printed words. It cannot establish physical identity, condition or function.
    /// A hint must be confirmed by the seller or a chat analysis of all photos.
    public static func from(text: String) -> DetectionSuggestion? {
        let value = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
        if value.range(of: #"\bfreebuds\s+se\s*4\s+anc\b"#, options: .regularExpression) != nil {
            return DetectionSuggestion(kind: .headphones, brand: value.contains("huawei") ? "HUAWEI" : "", title: "FreeBuds SE 4 ANC")
        }
        if value.range(of: #"\bgalaxy\s+watch\s*6\s+classic\b"#, options: .regularExpression) != nil {
            return DetectionSuggestion(kind: .smartwatch, brand: value.contains("samsung") ? "Samsung" : "", title: "Galaxy Watch6 Classic")
        }
        if value.range(of: #"\bfjallberget\b"#, options: .regularExpression) != nil {
            return DetectionSuggestion(kind: .chair, brand: value.contains("ikea") ? "IKEA" : "", title: "FJÄLLBERGET")
        }
        if value.range(of: #"\b(smartwatch|galaxy\s+watch|apple\s+watch)\b"#, options: .regularExpression) != nil {
            return DetectionSuggestion(kind: .smartwatch)
        }
        if value.range(of: #"\b(headphones|earbuds|kopfhorer|freebuds|airpods)\b"#, options: .regularExpression) != nil {
            return DetectionSuggestion(kind: .headphones)
        }
        if value.range(of: #"\b(burostuhl|drehstuhl|schreibtischstuhl|conference\s+chair)\b"#, options: .regularExpression) != nil {
            return DetectionSuggestion(kind: .chair)
        }
        return nil
    }
}
