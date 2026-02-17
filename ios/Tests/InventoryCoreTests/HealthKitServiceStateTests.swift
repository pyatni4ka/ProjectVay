import XCTest
@testable import InventoryCore

final class HealthKitServiceStateTests: XCTestCase {
    func testResolveReadAccessStateMapping() {
        XCTAssertEqual(
            HealthKitService.resolveReadAccessState(
                readEnabledInSettings: false,
                isHealthDataAvailable: true,
                requestStatus: .unnecessary,
                isDenied: false,
                hasAnyData: true
            ),
            .readDisabled
        )

        XCTAssertEqual(
            HealthKitService.resolveReadAccessState(
                readEnabledInSettings: true,
                isHealthDataAvailable: false,
                requestStatus: .unavailable,
                isDenied: false,
                hasAnyData: false
            ),
            .unavailable
        )

        XCTAssertEqual(
            HealthKitService.resolveReadAccessState(
                readEnabledInSettings: true,
                isHealthDataAvailable: true,
                requestStatus: .shouldRequest,
                isDenied: false,
                hasAnyData: false
            ),
            .needsRequest
        )

        XCTAssertEqual(
            HealthKitService.resolveReadAccessState(
                readEnabledInSettings: true,
                isHealthDataAvailable: true,
                requestStatus: .unknown,
                isDenied: false,
                hasAnyData: false
            ),
            .needsRequest
        )

        XCTAssertEqual(
            HealthKitService.resolveReadAccessState(
                readEnabledInSettings: true,
                isHealthDataAvailable: true,
                requestStatus: .unnecessary,
                isDenied: true,
                hasAnyData: true
            ),
            .denied
        )

        XCTAssertEqual(
            HealthKitService.resolveReadAccessState(
                readEnabledInSettings: true,
                isHealthDataAvailable: true,
                requestStatus: .unnecessary,
                isDenied: false,
                hasAnyData: false
            ),
            .authorizedNoData
        )

        XCTAssertEqual(
            HealthKitService.resolveReadAccessState(
                readEnabledInSettings: true,
                isHealthDataAvailable: true,
                requestStatus: .unnecessary,
                isDenied: false,
                hasAnyData: true
            ),
            .authorizedWithData
        )
    }
}
