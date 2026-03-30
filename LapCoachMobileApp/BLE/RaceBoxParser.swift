import Foundation

struct UBXMessage: Sendable {
    let classID: UInt8
    let messageID: UInt8
    let payload: Data
}

final class RaceBoxParser {
    private var buffer = Data()

    func append(_ data: Data) -> [RaceBoxTelemetrySample] {
        buffer.append(data)
        var decodedSamples: [RaceBoxTelemetrySample] = []

        while let message = nextMessage() {
            if let sample = decode(message) {
                decodedSamples.append(sample)
            }
        }

        return decodedSamples
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

    private func decode(_ message: UBXMessage) -> RaceBoxTelemetrySample? {
        switch (message.classID, message.messageID) {
        case (0x01, 0x07):
            return decodeNavPVT(message.payload)
        default:
            return nil
        }
    }

    private func decodeNavPVT(_ payload: Data) -> RaceBoxTelemetrySample? {
        guard payload.count >= 68 else { return nil }

        let lon = Double(payload.int32LE(at: 24)) / 10_000_000.0
        let lat = Double(payload.int32LE(at: 28)) / 10_000_000.0
        let speedMps = Double(payload.int32LE(at: 60)) / 1_000.0
        let headingDeg = Double(payload.int32LE(at: 64)) / 100_000.0

        return RaceBoxTelemetrySample(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1_000.0),
            latitude: lat,
            longitude: lon,
            speedMps: speedMps,
            headingDeg: headingDeg
        )
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
    fileprivate func int32LE(at offset: Int) -> Int32 {
        let b0 = Int32(self[offset])
        let b1 = Int32(self[offset + 1]) << 8
        let b2 = Int32(self[offset + 2]) << 16
        let b3 = Int32(bitPattern: UInt32(self[offset + 3]) << 24)
        return b0 | b1 | b2 | b3
    }
}
