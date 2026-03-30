import Foundation

struct LocationSnapshot: Hashable, Sendable {
    let timestampMs: Int64
    let latitude: Double
    let longitude: Double
    let speedMps: Double
    let headingDeg: Double
    let horizontalAccuracy: Double
}

struct MotionSnapshot: Hashable, Sendable {
    let timestampMs: Int64
    let ax: Double
    let ay: Double
    let az: Double
    let gx: Double
    let gy: Double
    let gz: Double
}

struct RaceBoxTelemetrySample: Hashable, Sendable {
    let timestampMs: Int64
    let latitude: Double
    let longitude: Double
    let speedMps: Double
    let headingDeg: Double
}

struct SensorSample: Codable, Hashable, Sendable {
    static let csvHeader = "session_id,timestamp_ms,source,lat_deg,lon_deg,speed_mps,heading_deg,ax,ay,az,gx,gy,gz,horizontal_accuracy"

    let sessionID: UUID
    let timestampMs: Int64
    let source: SessionSourceMode
    let latDeg: Double?
    let lonDeg: Double?
    let speedMps: Double?
    let headingDeg: Double?
    let ax: Double?
    let ay: Double?
    let az: Double?
    let gx: Double?
    let gy: Double?
    let gz: Double?
    let horizontalAccuracy: Double?

    var accelerationMagnitudeG: Double {
        let x = ax ?? 0.0
        let y = ay ?? 0.0
        let z = az ?? 0.0
        return sqrt((x * x) + (y * y) + (z * z)) / 9.80665
    }

    var coordinate: GeoPoint? {
        guard let latDeg, let lonDeg else { return nil }
        return GeoPoint(latitude: latDeg, longitude: lonDeg)
    }

    var csvRow: String {
        [
            sessionID.uuidString,
            String(timestampMs),
            source.rawValue,
            Self.csvValue(latDeg),
            Self.csvValue(lonDeg),
            Self.csvValue(speedMps),
            Self.csvValue(headingDeg),
            Self.csvValue(ax),
            Self.csvValue(ay),
            Self.csvValue(az),
            Self.csvValue(gx),
            Self.csvValue(gy),
            Self.csvValue(gz),
            Self.csvValue(horizontalAccuracy)
        ].joined(separator: ",")
    }

    init(
        sessionID: UUID,
        timestampMs: Int64,
        source: SessionSourceMode,
        latDeg: Double?,
        lonDeg: Double?,
        speedMps: Double?,
        headingDeg: Double?,
        ax: Double?,
        ay: Double?,
        az: Double?,
        gx: Double?,
        gy: Double?,
        gz: Double?,
        horizontalAccuracy: Double?
    ) {
        self.sessionID = sessionID
        self.timestampMs = timestampMs
        self.source = source
        self.latDeg = latDeg
        self.lonDeg = lonDeg
        self.speedMps = speedMps
        self.headingDeg = headingDeg
        self.ax = ax
        self.ay = ay
        self.az = az
        self.gx = gx
        self.gy = gy
        self.gz = gz
        self.horizontalAccuracy = horizontalAccuracy
    }

    init(csvLine: String) throws {
        let columns = csvLine.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 14, let sessionID = UUID(uuidString: columns[0]) else {
            throw CSVParseError.invalidRow(csvLine)
        }

        self.sessionID = sessionID
        self.timestampMs = Int64(columns[1]) ?? 0
        self.source = SessionSourceMode(rawValue: columns[2]) ?? .phone
        self.latDeg = Self.optionalDouble(columns[3])
        self.lonDeg = Self.optionalDouble(columns[4])
        self.speedMps = Self.optionalDouble(columns[5])
        self.headingDeg = Self.optionalDouble(columns[6])
        self.ax = Self.optionalDouble(columns[7])
        self.ay = Self.optionalDouble(columns[8])
        self.az = Self.optionalDouble(columns[9])
        self.gx = Self.optionalDouble(columns[10])
        self.gy = Self.optionalDouble(columns[11])
        self.gz = Self.optionalDouble(columns[12])
        self.horizontalAccuracy = Self.optionalDouble(columns[13])
    }

    static func from(
        sessionID: UUID,
        mode: SessionSourceMode,
        location: LocationSnapshot?,
        motion: MotionSnapshot?,
        timestampMs: Int64
    ) -> SensorSample {
        SensorSample(
            sessionID: sessionID,
            timestampMs: timestampMs,
            source: mode,
            latDeg: location?.latitude,
            lonDeg: location?.longitude,
            speedMps: location?.speedMps,
            headingDeg: location?.headingDeg,
            ax: motion?.ax,
            ay: motion?.ay,
            az: motion?.az,
            gx: motion?.gx,
            gy: motion?.gy,
            gz: motion?.gz,
            horizontalAccuracy: location?.horizontalAccuracy
        )
    }

    private static func csvValue(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static func optionalDouble(_ value: String) -> Double? {
        guard value.isEmpty == false else { return nil }
        return Double(value)
    }
}

enum CSVParseError: Error {
    case invalidRow(String)
}
