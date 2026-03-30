import Foundation

actor CSVWriter {
    private let handle: FileHandle

    init(fileURL: URL) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

        if FileManager.default.fileExists(atPath: fileURL.path) == false {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()

        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if size == 0 {
            try write(line: SensorSample.csvHeader)
        }
    }

    func append(_ sample: SensorSample) throws {
        try write(line: sample.csvRow)
    }

    func close() throws {
        try handle.synchronize()
        try handle.close()
    }

    private func write(line: String) throws {
        try handle.seekToEnd()
        guard let data = "\(line)\n".data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
    }
}

enum CSVSampleFileReader {
    static func loadSamples(from fileURL: URL) throws -> [SensorSample] {
        let raw = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = raw.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else { return [] }

        return try lines.dropFirst().map { line in
            try SensorSample(csvLine: String(line))
        }
    }

    static func makeChunks(from fileURL: URL, chunkSize: Int) throws -> [SessionChunkPayload] {
        let samples = try loadSamples(from: fileURL)
        guard let sessionID = samples.first?.sessionID else { return [] }

        return stride(from: 0, to: samples.count, by: chunkSize).enumerated().map { index, offset in
            let chunkSamples = Array(samples[offset ..< min(offset + chunkSize, samples.count)])
            return SessionChunkPayload(
                sessionID: sessionID.uuidString,
                chunkIndex: index,
                chunkSize: chunkSamples.count,
                samples: chunkSamples
            )
        }
    }
}
