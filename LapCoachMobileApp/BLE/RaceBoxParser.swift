import Foundation

struct UBXMessage: Sendable {
    let classID: UInt8
    let messageID: UInt8
    let payload: Data
}

private struct ITOWAnchor: Sendable {
    let iTOWMs: UInt32
    let anchoredTimestampMs: Int64
}

final class RaceBoxParser {
    private let utcCalendar: Calendar
    private var buffer = Data()
    private var iTOWAnchor: ITOWAnchor?

    init(calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()) {
        self.utcCalendar = calendar
    }

    func append(_ data: Data, receivedAt: Date = Date()) -> [RaceBoxTelemetrySample] {
        buffer.append(data)
        let receivedAtMs = Int64((receivedAt.timeIntervalSince1970 * 1_000.0).rounded())
        var decodedSamples: [RaceBoxTelemetrySample] = []

        while let message = nextMessage() {
            if let sample = decode(message, receivedAtMs: receivedAtMs) {
                decodedSamples.append(sample)
            }
        }

        return decodedSamples
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        iTOWAnchor = nil
    }

    private func nextMessage() -> UBXMessage? {
        while buffer.count >= 8 {
            guard buffer[0] == 0xB5, buffer[1] == 0x62 else {
                buffer.removeFirst()
                continue
            }

            let payloadLength = Int(buffer[4]) | (Int(buffer[5]) << 8)
            let messageLength = payloadLength + 8

            guard buffer.count >= messageLength else {
                return nil
            }

            let rawMessage = buffer.prefix(messageLength)
            let checksumRange = rawMessage.dropFirst(2).dropLast(2)
            let expectedChecksum = checksum(for: checksumRange)
            let actualCKA = rawMessage[messageLength - 2]
            let actualCKB = rawMessage[messageLength - 1]

            guard expectedChecksum.0 == actualCKA, expectedChecksum.1 == actualCKB else {
                buffer.removeFirst()
                continue
            }

            let payload = Data(rawMessage[6 ..< (6 + payloadLength)])
            let message = UBXMessage(classID: rawMessage[2], messageID: rawMessage[3], payload: payload)
            buffer.removeFirst(messageLength)
            return message
        }

        return nil
    }

    private func decode(_ message: UBXMessage, receivedAtMs: Int64) -> RaceBoxTelemetrySample? {
        switch (message.classID, message.messageID) {
        case (0x01, 0x07):
            return decodeNavPVT(message.payload, receivedAtMs: receivedAtMs)
        default:
            return nil
        }
    }

    private func decodeNavPVT(_ payload: Data, receivedAtMs: Int64) -> RaceBoxTelemetrySample? {
        guard payload.count >= 68 else { return nil }

        let iTOW = payload.uint32LE(at: 0)
        let lon = Double(payload.int32LE(at: 24)) / 10_000_000.0
        let lat = Double(payload.int32LE(at: 28)) / 10_000_000.0
        let speedMps = Double(payload.int32LE(at: 60)) / 1_000.0
        let headingDeg = Double(payload.int32LE(at: 64)) / 100_000.0

        let timestampMs = deviceTimestampMs(for: payload, iTOW: iTOW, receivedAtMs: receivedAtMs)

        return RaceBoxTelemetrySample(
            timestampMs: timestampMs,
            latitude: lat,
            longitude: lon,
            speedMps: speedMps,
            headingDeg: headingDeg
        )
    }

    private func deviceTimestampMs(for payload: Data, iTOW: UInt32, receivedAtMs: Int64) -> Int64 {
        if let absoluteTimestampMs = absoluteTimestampMs(from: payload) {
            iTOWAnchor = ITOWAnchor(iTOWMs: iTOW, anchoredTimestampMs: absoluteTimestampMs)
            return absoluteTimestampMs
        }

        return anchoredTimestampMs(for: iTOW, receivedAtMs: receivedAtMs)
    }

    private func absoluteTimestampMs(from payload: Data) -> Int64? {
        let validFlags = payload[11]
        let hasValidDate = (validFlags & 0x01) != 0
        let hasValidTime = (validFlags & 0x02) != 0
        guard hasValidDate, hasValidTime else {
            return nil
        }

        let year = Int(payload.uint16LE(at: 4))
        let month = Int(payload[6])
        let day = Int(payload[7])
        let hour = Int(payload[8])
        let minute = Int(payload[9])
        let second = Int(payload[10])
        let nano = Int64(payload.int32LE(at: 16))

        var components = DateComponents()
        components.calendar = utcCalendar
        components.timeZone = utcCalendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        guard let baseDate = utcCalendar.date(from: components) else {
            return nil
        }

        let baseTimestampMs = Int64((baseDate.timeIntervalSince1970 * 1_000.0).rounded())
        return baseTimestampMs + (nano / 1_000_000)
    }

    private func anchoredTimestampMs(for iTOW: UInt32, receivedAtMs: Int64) -> Int64 {
        let anchor = iTOWAnchor ?? ITOWAnchor(iTOWMs: iTOW, anchoredTimestampMs: receivedAtMs)
        if iTOWAnchor == nil {
            iTOWAnchor = anchor
        }

        var deltaMs = Int64(iTOW) - Int64(anchor.iTOWMs)
        let halfWeekMs: Int64 = 302_400_000
        let fullWeekMs: Int64 = 604_800_000

        if deltaMs < -halfWeekMs {
            deltaMs += fullWeekMs
        } else if deltaMs > halfWeekMs {
            deltaMs -= fullWeekMs
        }

        return anchor.anchoredTimestampMs + deltaMs
    }

    private func checksum<S: Sequence>(for bytes: S) -> (UInt8, UInt8) where S.Element == UInt8 {
        var ckA: UInt8 = 0
        var ckB: UInt8 = 0
        for byte in bytes {
            ckA = ckA &+ byte
            ckB = ckB &+ ckA
        }
        return (ckA, ckB)
    }
}

extension Data {
    fileprivate func uint16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1]) << 8
        return b0 | b1
    }

    fileprivate func uint32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }

    fileprivate func int32LE(at offset: Int) -> Int32 {
        let b0 = Int32(self[offset])
        let b1 = Int32(self[offset + 1]) << 8
        let b2 = Int32(self[offset + 2]) << 16
        let b3 = Int32(bitPattern: UInt32(self[offset + 3]) << 24)
        return b0 | b1 | b2 | b3
    }
}
