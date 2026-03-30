import XCTest
@testable import LapCoachMobileApp

final class RaceBoxParserTests: XCTestCase {
    func testParserReassemblesFragmentedNavPVTFrame() {
        let payload = makeNavPVTPayload(
            latitude: 50.1234567,
            longitude: 4.9876543,
            speedMps: 32.5,
            headingDeg: 182.25
        )
        let frame = makeUBXFrame(classID: 0x01, messageID: 0x07, payload: payload)
        let parser = RaceBoxParser()

        XCTAssertTrue(parser.append(Data(frame.prefix(10))).isEmpty)
        XCTAssertTrue(parser.append(Data(frame[10 ..< 40])).isEmpty)
        let decoded = parser.append(Data(frame.dropFirst(40)))

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].latitude, 50.1234567, accuracy: 0.0000001)
        XCTAssertEqual(decoded[0].longitude, 4.9876543, accuracy: 0.0000001)
        XCTAssertEqual(decoded[0].speedMps, 32.5, accuracy: 0.001)
        XCTAssertEqual(decoded[0].headingDeg, 182.25, accuracy: 0.0001)
    }

    private func makeNavPVTPayload(
        latitude: Double,
        longitude: Double,
        speedMps: Double,
        headingDeg: Double
    ) -> Data {
        var payload = Data(repeating: 0, count: 92)
        payload.replaceSubrange(24 ..< 28, with: int32Bytes(Int32(longitude * 10_000_000.0)))
        payload.replaceSubrange(28 ..< 32, with: int32Bytes(Int32(latitude * 10_000_000.0)))
        payload.replaceSubrange(60 ..< 64, with: int32Bytes(Int32(speedMps * 1_000.0)))
        payload.replaceSubrange(64 ..< 68, with: int32Bytes(Int32(headingDeg * 100_000.0)))
        return payload
    }

    private func int32Bytes(_ value: Int32) -> Data {
        let littleEndian = value.littleEndian
        return withUnsafeBytes(of: littleEndian) { Data($0) }
    }

    private func makeUBXFrame(classID: UInt8, messageID: UInt8, payload: Data) -> Data {
        var frame = Data([0xB5, 0x62, classID, messageID])
        let length = UInt16(payload.count).littleEndian
        frame.append(contentsOf: withUnsafeBytes(of: length) { Array($0) })
        frame.append(payload)

        var ckA: UInt8 = 0
        var ckB: UInt8 = 0
        for byte in frame.dropFirst(2) {
            ckA = ckA &+ byte
            ckB = ckB &+ ckA
        }
        frame.append(ckA)
        frame.append(ckB)
        return frame
    }
}
