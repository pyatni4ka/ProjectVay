import XCTest
@testable import InventoryCore

final class HealthWeightChartTests: XCTestCase {
    
    // Test helper to simulate HomeView.sanitizedHealthWeightHistory logic
    func sanitizePoints(_ points: [HealthKitService.SamplePoint]) -> [HealthKitService.SamplePoint] {
        let cal = Calendar.current
        let validRange: ClosedRange<Double> = 30...300
        let filtered = points
            .filter { validRange.contains($0.value) }
            .sorted { $0.date < $1.date }

        var byDay: [Date: HealthKitService.SamplePoint] = [:]
        for point in filtered {
            let day = cal.startOfDay(for: point.date)
            // Logic: keep the latest sample for the day
            if let existing = byDay[day] {
                if point.date > existing.date {
                    byDay[day] = point
                }
            } else {
                byDay[day] = point
            }
        }
        return byDay.values.sorted { $0.date < $1.date }
    }
    
    func testSanitizationDeduplicatesByDay() {
        let day1 = Date()
        let day1Later = day1.addingTimeInterval(3600)
        let day2 = day1.addingTimeInterval(86400)
        
        let p1 = HealthKitService.SamplePoint(date: day1, value: 70.0)
        let p2 = HealthKitService.SamplePoint(date: day1Later, value: 71.0) // Should win
        let p3 = HealthKitService.SamplePoint(date: day2, value: 70.5)
        
        let result = sanitizePoints([p1, p3, p2]) // Mixed order
        
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].value, 71.0) // Last on day 1
        XCTAssertEqual(result[1].value, 70.5) // Day 2
    }
    
    func testSanitizationFiltersOutliers() {
        let valid = HealthKitService.SamplePoint(date: Date(), value: 70.0)
        let tooLow = HealthKitService.SamplePoint(date: Date().addingTimeInterval(1), value: 29.0)
        let tooHigh = HealthKitService.SamplePoint(date: Date().addingTimeInterval(2), value: 301.0)
        
        let result = sanitizePoints([valid, tooLow, tooHigh])
        
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 70.0)
    }
}
