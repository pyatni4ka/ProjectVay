import Foundation

enum ProductNameFormatter {

    struct FormattedName {
        let displayName: String
        let brand: String?
        let volumeBadge: String?
    }

    /// Returns structured result: cleaned display name + optional brand + optional volume/weight badge.
    static func formatted(_ raw: String, brand: String? = nil) -> FormattedName {
        var text = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        var finalBrand: String? = nil
        if let b = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty {
            finalBrand = b
            if let range = text.range(of: b, options: [.caseInsensitive]) {
                text.removeSubrange(range)
            }
            // Clean up possible trailing/leading commas or hyphens left after removal
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,-"))
        }

        var badge: String?

        // 1. Strip "| value unit" or "/ value unit" suffixes first
        let separatorPattern = #"\s*[|/]\s*(\d[\d,. ]*\s*(г|гр|кг|мл|л|oz|kg|ml|g))\b.*"#
        if let match = text.range(of: separatorPattern, options: [.regularExpression, .caseInsensitive]) {
            let extracted = String(text[match])
            if let unitMatch = extracted.range(of: #"\d[\d,. ]*\s*(г|гр|кг|мл|л|oz|kg|ml|g)"#, options: [.regularExpression, .caseInsensitive]) {
                badge = normalizeBadge(String(extracted[unitMatch]))
            }
            text = String(text[..<match.lowerBound])
        }

        // 2. Extract trailing volume/weight: "950МЛ", "1.5Л", "180Г"
        if badge == nil {
            let trailingPattern = #"[\s,]+(\d[\d,. ]*)\s*(мл|л|г|гр|кг|oz|kg|ml|g)\s*$"#
            if let match = text.range(of: trailingPattern, options: [.regularExpression, .caseInsensitive]) {
                badge = normalizeBadge(String(text[match]).trimmingCharacters(in: .punctuationCharacters))
                text = String(text[..<match.lowerBound])
            }
        }

        // 3. Smart capitalize
        text = smartCapitalize(text)

        // 4. Remove consecutive duplicate words
        text = removeConsecutiveDuplicates(text)

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return FormattedName(displayName: text.isEmpty ? "Без названия" : text, brand: finalBrand, volumeBadge: badge)
    }

    /// Backward-compatible: returns only the display name string.
    static func format(_ raw: String, brand: String? = nil) -> String {
        formatted(raw, brand: brand).displayName
    }

    // MARK: - Private

    private static let lowercaseWords: Set<String> = [
        "в", "на", "из", "для", "с", "и", "по", "от", "до",
        "не", "за", "без", "при", "ко", "об", "под", "над"
    ]

    private static func smartCapitalize(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        return words.enumerated().map { index, word in
            guard !word.isEmpty else { return word }
            let lower = word.lowercased()

            // Keep prepositions lowercase (except first word)
            if index > 0 && lowercaseWords.contains(lower) {
                return lower
            }

            // Percentage or pure numbers — keep as-is
            if word.contains("%") {
                return lower
            }
            if lower.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) {
                return lower
            }

            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    private static func removeConsecutiveDuplicates(_ text: String) -> String {
        let words = text.components(separatedBy: " ")
        var result: [String] = []
        for word in words {
            if let last = result.last, last.lowercased() == word.lowercased() {
                continue
            }
            result.append(word)
        }
        return result.joined(separator: " ")
    }

    private static func normalizeBadge(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
            .replacingOccurrences(of: "гр", with: "г")
    }
}
