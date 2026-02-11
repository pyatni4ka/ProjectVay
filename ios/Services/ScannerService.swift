import Foundation

enum ScanPayload {
    case ean13(String)
    case dataMatrix(raw: String, gtin: String?, expiryDate: Date?)
    case internalCode(code: String, parsedWeightGrams: Double?)
}

final class ScannerService {
    func parse(code: String) -> ScanPayload {
        if code.count == 13, CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: code)) {
            return .ean13(code)
        }

        if code.contains("01") || code.contains("17") {
            let gtin = extractAI01(code)
            let expiry = extractAI17(code)
            return .dataMatrix(raw: code, gtin: gtin, expiryDate: expiry)
        }

        return .internalCode(code: code, parsedWeightGrams: parseInternalWeight(code))
    }

    private func extractAI01(_ value: String) -> String? {
        guard let range = value.range(of: "01") else { return nil }
        let suffix = value[range.upperBound...]
        return String(suffix.prefix(14))
    }

    private func extractAI17(_ value: String) -> Date? {
        guard let range = value.range(of: "17") else { return nil }
        let suffix = value[range.upperBound...]
        let digits = String(suffix.prefix(6))
        guard digits.count == 6 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd"
        formatter.timeZone = .current
        return formatter.date(from: digits)
    }

    private func parseInternalWeight(_ code: String) -> Double? {
        let digits = code.filter(\.isNumber)
        guard digits.count >= 5 else { return nil }
        return Double(digits.suffix(3))
    }
}
