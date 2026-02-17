import Foundation

enum ScanPayload {
    case ean13(String)
    case dataMatrix(raw: String, gtin: String?, expiryDate: Date?)
    case internalCode(code: String, parsedWeightGrams: Double?)
}

final class ScannerService {
    func parse(code: String) -> ScanPayload {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.count == 13, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: normalized)) {
            return .ean13(normalized)
        }

        if let parsedDataMatrix = parseDataMatrix(raw: normalized) {
            return .dataMatrix(raw: normalized, gtin: parsedDataMatrix.gtin, expiryDate: parsedDataMatrix.expiryDate)
        }

        return .internalCode(code: normalized, parsedWeightGrams: parseInternalWeight(normalized))
    }

    private func parseDataMatrix(raw: String) -> (gtin: String?, expiryDate: Date?)? {
        let cleaned = normalizeDataMatrixPayload(raw)
        guard !cleaned.isEmpty else { return nil }

        let gtin = extractAI(code: cleaned, ai: "01", length: 14)
        let expiryRaw = extractAI(code: cleaned, ai: "17", length: 6)
        let expiryDate = expiryRaw.flatMap(parseYYMMDD)

        guard gtin != nil || expiryDate != nil else {
            return nil
        }

        return (gtin: gtin, expiryDate: expiryDate)
    }

    private func extractAI(code: String, ai: String, length: Int) -> String? {
        guard !ai.isEmpty, length > 0, code.count >= ai.count + length else {
            return nil
        }

        let characters = Array(code)
        let aiCharacters = Array(ai)
        let maxStart = characters.count - aiCharacters.count - length
        guard maxStart >= 0 else { return nil }

        for start in 0...maxStart {
            let aiSlice = characters[start..<(start + aiCharacters.count)]
            if !zip(aiSlice, aiCharacters).allSatisfy({ $0 == $1 }) {
                continue
            }

            let dataStart = start + aiCharacters.count
            let dataEnd = dataStart + length
            let valueSlice = characters[dataStart..<dataEnd]
            if valueSlice.allSatisfy({ $0.isNumber }) {
                return String(valueSlice)
            }
        }

        return nil
    }

    private func normalizeDataMatrixPayload(_ raw: String) -> String {
        var value = raw
        if value.hasPrefix("]d2") || value.hasPrefix("]Q3") {
            value.removeFirst(3)
        }

        return value.filter { character in
            character.isNumber || character == "\u{001D}"
        }
    }

    private func parseYYMMDD(_ digits: String) -> Date? {
        guard digits.count == 6 else { return nil }
        let yearPart = digits.prefix(2)
        let monthPart = digits.dropFirst(2).prefix(2)
        let dayPart = digits.suffix(2)

        guard
            let year = Int(yearPart),
            let month = Int(monthPart),
            let day = Int(dayPart),
            (1...12).contains(month),
            (1...31).contains(day)
        else {
            return nil
        }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = 2000 + year
        components.month = month
        components.day = day
        components.hour = 12

        return components.date
    }

    private func parseInternalWeight(_ code: String) -> Double? {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 5 else { return nil }
        return Double(digits.suffix(3))
    }
}
