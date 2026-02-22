import XCTest
@testable import InventoryCore

final class HighPrecisionBudgetTests: XCTestCase {
    func testBudgetRoundtripPrecision() {
        // Start with 100/month
        let startMonth = Decimal(100)
        let breakdown1 = AppSettings.budgetBreakdown(input: startMonth, period: .month)
        
        let weekHighPrec = breakdown1.week
        // Should be around 23.01369...
        
        // Convert back to month using high precision
        let breakdown2 = AppSettings.budgetBreakdown(input: weekHighPrec, period: .week)
        let monthRestored = breakdown2.month
        
        XCTAssertEqual(monthRestored.rounded(scale: 2), startMonth.rounded(scale: 2), "High precision roundtrip failed")
        
        // Simulate low precision (what was happening before)
        let weekLowPrec = weekHighPrec.rounded(scale: 2) // 23.01
        let breakdown3 = AppSettings.budgetBreakdown(input: weekLowPrec, period: .week)
        let monthDrifted = breakdown3.month
        
        // 23.01 * 365 / 84 = 99.98
        // This confirms the drift existed
        XCTAssertNotEqual(monthDrifted.rounded(scale: 2), startMonth.rounded(scale: 2), "Low precision should drift")
        XCTAssertEqual(monthDrifted.rounded(scale: 2), 99.98, "Expected drift to 99.98")
    }
    
    func testAppSettingsNormalization() {
        var settings = AppSettings.default
        settings.budgetInputPeriod = .month
        settings.budgetPrimaryValue = 100
        
        let normalized = settings.normalized()
        XCTAssertEqual(normalized.budgetPrimaryValue, 100)
        
        // Test that normalization rounds to scale 2
        let preciseVal = Decimal(string: "23.0137")!
        settings.budgetPrimaryValue = preciseVal
        let normalizedPrecise = settings.normalized()
        XCTAssertEqual(normalizedPrecise.budgetPrimaryValue, Decimal(string: "23.01")!)
    }
}
