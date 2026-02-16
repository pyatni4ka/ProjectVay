import Foundation
import Vision
#if canImport(UIKit)
import UIKit
#endif

struct ScannedReceiptItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let price: Decimal?
    let quantity: Int?
    let category: String?
    
    var isValid: Bool {
        !name.isEmpty && name.count >= 2
    }
}

enum ReceiptScannerError: Error {
    case imageProcessingFailed
    case textRecognitionFailed
    case noTextFound
}

final class ReceiptScannerService: @unchecked Sendable {
    static let shared = ReceiptScannerService()
    
    private init() {}
    
    #if canImport(UIKit)
    func scanReceipt(from image: UIImage) async throws -> [ScannedReceiptItem] {
        guard let cgImage = image.cgImage else {
            throw ReceiptScannerError.imageProcessingFailed
        }
        
        let recognizedText = try await performTextRecognition(on: cgImage)
        
        guard !recognizedText.isEmpty else {
            throw ReceiptScannerError.noTextFound
        }
        
        let items = parseReceiptText(recognizedText)
        return items
    }
    #endif
    
    private func performTextRecognition(on image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let textLines = observations.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }
                
                continuation.resume(returning: textLines)
            }
            
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ru-RU", "en-US"]
            request.usesLanguageCorrection = true
            
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func parseReceiptText(_ lines: [String]) -> [ScannedReceiptItem] {
        var items: [ScannedReceiptItem] = []
        
        let pricePattern = #"(\d+[.,]\d{2})\s*(?:руб|р|\$|€)?"#
        let priceRegex = try? NSRegularExpression(pattern: pricePattern, options: .caseInsensitive)
        
        let quantityPattern = #"(\d+)\s*(?:шт|кг|г|мл|л)?"#
        let quantityRegex = try? NSRegularExpression(pattern: quantityPattern, options: .caseInsensitive)
        
        let stopWords = ["итого", "сумма", "нал", "безнал", "карта", "скидка", "бонусы", "сдача", "спасибо", "через", "терминал"]
        
        for line in lines {
            let lowercasedLine = line.lowercased()
            
            if stopWords.contains(where: { lowercasedLine.contains($0) }) {
                continue
            }
            
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.count >= 3 else { continue }
            
            var price: Decimal?
            var quantity: Int?
            
            if let priceRegex = priceRegex {
                let range = NSRange(lowercasedLine.startIndex..., in: lowercasedLine)
                if let match = priceRegex.firstMatch(in: lowercasedLine, options: [], range: range) {
                    if let priceRange = Range(match.range(at: 1), in: lowercasedLine) {
                        let priceString = String(lowercasedLine[priceRange]).replacingOccurrences(of: ",", with: ".")
                        price = Decimal(string: priceString)
                    }
                }
            }
            
            if let quantityRegex = quantityRegex {
                let range = NSRange(lowercasedLine.startIndex..., in: lowercasedLine)
                if let match = quantityRegex.firstMatch(in: lowercasedLine, options: [], range: range) {
                    if let quantityRange = Range(match.range(at: 1), in: lowercasedLine) {
                        quantity = Int(lowercasedLine[quantityRange])
                    }
                }
            }
            
            let category = detectCategory(for: trimmedLine)
            
            let itemName = cleanItemName(trimmedLine)
            
            guard itemName.count >= 2 else { continue }
            
            let item = ScannedReceiptItem(
                name: itemName,
                price: price,
                quantity: quantity,
                category: category
            )
            
            if item.isValid {
                items.append(item)
            }
        }
        
        return items
    }
    
    private func cleanItemName(_ name: String) -> String {
        var cleaned = name
        
        let removePatterns = [
            #"\d+[.,]\d{2}\s*(?:руб|р)? "#,
            #"^\d+\s+"#,
            #"\s+\d+$"#
        ]
        
        for pattern in removePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func detectCategory(for itemName: String) -> String? {
        let lowercased = itemName.lowercased()
        
        let categoryKeywords: [(String, [String])] = [
            ("Молочные", ["молоко", "кефир", "йогурт", "сыр", "творог", "сметана", "сливки"]),
            ("Мясо", ["мясо", "курица", "свинина", "говядина", "колбаса", "сосиски"]),
            ("Хлеб", ["хлеб", "батон", "булка", "пирожок"]),
            ("Овощи", ["помидор", "огурец", "картофель", "морковь", "лук", "чеснок"]),
            ("Фрукты", ["яблоко", "банан", "апельсин", "мандарин", "виноград"]),
            ("Напитки", ["вода", "сок", "чай", "кофе", "газировка"]),
            ("Консервы", ["консерв", "тушенка", "рыба", "горох", "кукуруза"])
        ]
        
        for (category, keywords) in categoryKeywords {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    return category
                }
            }
        }
        
        return nil
    }
}
