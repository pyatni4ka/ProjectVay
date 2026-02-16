import Foundation

struct ProductPrediction: Identifiable, Equatable {
    let id: UUID
    let productName: String
    let estimatedDaysUntilEmpty: Int
    let suggestedPurchaseDate: Date
    let averageConsumptionPerDay: Double
    let lastPurchaseDate: Date?
    let confidence: Double
    
    var urgencyLevel: UrgencyLevel {
        if estimatedDaysUntilEmpty <= 2 { return .critical }
        if estimatedDaysUntilEmpty <= 5 { return .high }
        if estimatedDaysUntilEmpty <= 10 { return .medium }
        return .low
    }
    
    enum UrgencyLevel {
        case critical, high, medium, low
        
        var icon: String {
            switch self {
            case .critical: return "exclamationmark.octagon.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "exclamationmark.circle.fill"
            case .low: return "checkmark.circle.fill"
            }
        }
    }
}

final class PredictionService: @unchecked Sendable {
    static let shared = PredictionService()
    
    private let userDefaults = UserDefaults.standard
    private let consumptionHistoryKey = "vay_consumption_history"
    
    private init() {}
    
    struct ConsumptionRecord: Codable {
        let productId: UUID
        let productName: String
        let quantity: Double
        let unit: String
        let date: Date
    }
    
    func recordConsumption(productId: UUID, productName: String, quantity: Double, unit: String) {
        var history = loadConsumptionHistory()
        
        let record = ConsumptionRecord(
            productId: productId,
            productName: productName,
            quantity: quantity,
            unit: unit,
            date: Date()
        )
        history.append(record)
        
        if history.count > 1000 {
            history = Array(history.suffix(500))
        }
        
        saveConsumptionHistory(history)
    }
    
    func predictNeededProducts(currentInventory: [(name: String, quantity: Double, expiryDate: Date?)]) -> [ProductPrediction] {
        let history = loadConsumptionHistory()
        
        var predictions: [ProductPrediction] = []
        
        let productGroups = Dictionary(grouping: history, by: { $0.productName.lowercased() })
        
        for (productName, records) in productGroups {
            guard records.count >= 3 else { continue }
            
            let sortedRecords = records.sorted { $0.date < $1.date }
            
            let consumptionRates = calculateConsumptionRate(records: sortedRecords)
            guard consumptionRates > 0 else { continue }
            
            let inventoryItem = currentInventory.first { $0.name.lowercased() == productName }
            let currentQuantity = inventoryItem?.quantity ?? 0
            
            let daysUntilEmpty = currentQuantity / consumptionRates
            let suggestedDate = Calendar.current.date(
                byAdding: .day,
                value: Int(daysUntilEmpty),
                to: Date()
            ) ?? Date()
            
            let lastPurchase = sortedRecords.last?.date
            let confidence = min(1.0, Double(records.count) / 10.0)
            
            let prediction = ProductPrediction(
                id: UUID(),
                productName: productName.capitalized,
                estimatedDaysUntilEmpty: Int(daysUntilEmpty),
                suggestedPurchaseDate: suggestedDate,
                averageConsumptionPerDay: consumptionRates,
                lastPurchaseDate: lastPurchase,
                confidence: confidence
            )
            
            predictions.append(prediction)
        }
        
        return predictions
            .filter { $0.estimatedDaysUntilEmpty <= 14 }
            .sorted { $0.estimatedDaysUntilEmpty < $1.estimatedDaysUntilEmpty }
    }
    
    func generateShoppingList(predictions: [ProductPrediction], budget: Decimal?) -> [String] {
        var shoppingList: [String] = []
        
        let criticalItems = predictions.filter { $0.urgencyLevel == .critical || $0.urgencyLevel == .high }
        
        for prediction in criticalItems {
            let quantityNeeded = Int(prediction.averageConsumptionPerDay * 14)
            shoppingList.append("\(prediction.productName) (\(quantityNeeded) шт)")
        }
        
        return shoppingList
    }
    
    private func calculateConsumptionRate(records: [ConsumptionRecord]) -> Double {
        guard records.count >= 2 else { return 0 }
        
        let totalQuantity = records.reduce(0.0) { $0 + $1.quantity }
        
        guard let firstDate = records.first?.date,
              let lastDate = records.last?.date else { return 0 }
        
        let daysDiff = Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 1
        guard daysDiff > 0 else { return totalQuantity }
        
        return totalQuantity / Double(daysDiff)
    }
    
    private func loadConsumptionHistory() -> [ConsumptionRecord] {
        guard let data = userDefaults.data(forKey: consumptionHistoryKey),
              let history = try? JSONDecoder().decode([ConsumptionRecord].self, from: data) else {
            return []
        }
        return history
    }
    
    private func saveConsumptionHistory(_ history: [ConsumptionRecord]) {
        if let data = try? JSONEncoder().encode(history) {
            userDefaults.set(data, forKey: consumptionHistoryKey)
        }
    }
    
    func clearHistory() {
        userDefaults.removeObject(forKey: consumptionHistoryKey)
    }
}
