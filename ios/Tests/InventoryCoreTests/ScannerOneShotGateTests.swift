import XCTest
@testable import InventoryCore

final class ScannerOneShotGateTests: XCTestCase {
    func testCaptureAcceptsFirstCodeAndLocksGate() {
        var gate = ScannerOneShotGate()

        let captured = gate.capture(" 4601234567890 ")

        XCTAssertEqual(captured, "4601234567890")
        XCTAssertTrue(gate.isLocked)
        XCTAssertEqual(gate.lockedCode, "4601234567890")
    }

    func testCaptureIgnoresNextCodesWhileLocked() {
        var gate = ScannerOneShotGate()
        _ = gate.capture("4601234567890")

        let next = gate.capture("4601234567891")

        XCTAssertNil(next)
        XCTAssertEqual(gate.lockedCode, "4601234567890")
    }

    func testResetUnlocksGateAndAllowsNewCapture() {
        var gate = ScannerOneShotGate()
        _ = gate.capture("4601234567890")
        gate.reset()

        let capturedAgain = gate.capture("4601234567891")

        XCTAssertEqual(capturedAgain, "4601234567891")
        XCTAssertTrue(gate.isLocked)
        XCTAssertEqual(gate.lockedCode, "4601234567891")
    }
}
