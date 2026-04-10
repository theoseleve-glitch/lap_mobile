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

    func testParserUsesValidUTCDateTimeWhenPresent() {
        let payload = makeNavPVTPayload(
            latitude: 50.1234567,
            longitude: 4.9876543,
            speedMps: 32.5,
            headingDeg: 182.25,
            iTOW: 1_000,
            utc: UTCStamp(year: 2026, month: 3, day: 30, hour: 10, minute: 11, second: 12, nano: 250_000_000),
            validFlags: 0x03
        )
        let frame = makeUBXFrame(classID: 0x01, messageID: 0x07, payload: payload)
        let parser = RaceBoxParser()

        let decoded = parser.append(frame, receivedAt: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(decoded.count, 1)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC") ?? .current
        let date = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 3,
            day: 30,
            hour: 10,
            minute: 11,
            second: 12
        ))!
        let expectedTimestampMs = Int64(date.timeIntervalSince1970 * 1_000.0) + 250

        XCTAssertEqual(decoded[0].timestampMs, expectedTimestampMs)
    }

    func testParserFallsBackToAnchoredITOWWhenUTCIsInvalid() {
        let parser = RaceBoxParser()
        let firstPayload = makeNavPVTPayload(
            latitude: 50.0,
            longitude: 4.0,
            speedMps: 20.0,
            headingDeg: 180.0,
            iTOW: 1_000,
            utc: nil,
            validFlags: 0
        )
        let secondPayload = makeNavPVTPayload(
            latitude: 50.0,
            longitude: 4.0,
            speedMps: 20.0,
            headingDeg: 180.0,
            iTOW: 1_250,
            utc: nil,
            validFlags: 0
        )

        let first = parser.append(makeUBXFrame(classID: 0x01, messageID: 0x07, payload: firstPayload), receivedAt: Date(timeIntervalSince1970: 100))
        let second = parser.append(makeUBXFrame(classID: 0x01, messageID: 0x07, payload: secondPayload), receivedAt: Date(timeIntervalSince1970: 150))

        XCTAssertEqual(first.first?.timestampMs, 100_000)
        XCTAssertEqual(second.first?.timestampMs, 100_250)
    }

    private func makeNavPVTPayload(
        latitude: Double,
        longitude: Double,
        speedMps: Double,
        headingDeg: Double,
        iTOW: UInt32 = 0,
        utc: UTCStamp? = nil,
        validFlags: UInt8 = 0
    ) -> Data {
        var payload = Data(repeating: 0, count: 92)
        payload.replaceSubrange(0 ..< 4, with: uint32Bytes(iTOW))
        if let utc {
            payload.replaceSubrange(4 ..< 6, with: uint16Bytes(UInt16(utc.year)))
            payload[6] = utc.month
            payload[7] = utc.day
            payload[8] = utc.hour
            payload[9] = utc.minute
            payload[10] = utc.second
            payload.replaceSubrange(16 ..< 20, with: int32Bytes(utc.nano))
        }
        payload[11] = validFlags
        payload.replaceSubrange(24 ..< 28, with: int32Bytes(Int32(longitude * 10_000_000.0)))
        payload.replaceSubrange(28 ..< 32, with: int32Bytes(Int32(latitude * 10_000_000.0)))
        payload.replaceSubrange(60 ..< 64, with: int32Bytes(Int32(speedMps * 1_000.0)))
        payload.replaceSubrange(64 ..< 68, with: int32Bytes(Int32(headingDeg * 100_000.0)))
        return payload
    }

    private func uint16Bytes(_ value: UInt16) -> Data {
        let littleEndian = value.littleEndian
        return withUnsafeBytes(of: littleEndian) { Data($0) }
    }

    private func uint32Bytes(_ value: UInt32) -> Data {
        let littleEndian = value.littleEndian
        return withUnsafeBytes(of: littleEndian) { Data($0) }
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

private struct UTCStamp {
    let year: Int
    let month: UInt8
    let day: UInt8
    let hour: UInt8
    let minute: UInt8
    let second: UInt8
    let nano: Int32
}
