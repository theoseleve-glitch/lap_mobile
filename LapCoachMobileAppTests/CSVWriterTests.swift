import Foundation
import XCTest
@testable import LapCoachMobileApp

final class CSVWriterTests: XCTestCase {
    func testWriterAppendsHeaderAndSample() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("session.tmp.csv")
        let writer = try CSVWriter(fileURL: fileURL)

        let sample = SensorSample(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            timestampMs: 1_711_812_345_678,
            source: .phone,
            latDeg: 51.2,
            lonDeg: 4.4,
            speedMps: 20.5,
            headingDeg: 180.0,
            ax: 1.0,
            ay: 2.0,
            az: 3.0,
            gx: 0.1,
            gy: 0.2,
            gz: 0.3,
            horizontalAccuracy: 0.9
        )

        try await writer.append(sample)
        try await writer.close()

        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(contents.contains(SensorSample.csvHeader))
        XCTAssertTrue(contents.contains("00000000-0000-0000-0000-000000000001"))
        XCTAssertTrue(contents.contains("1711812345678"))
        XCTAssertTrue(contents.contains("20.5"))
    }
}
