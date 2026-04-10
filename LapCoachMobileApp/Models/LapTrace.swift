import Foundation

struct LapTracePoint: Sendable {
    let cumulativeDistanceMeters: Double
    let coordinate: GeoPoint
    let elapsedTimeSeconds: Double
}

struct LapTrace: Sendable {
    let lapIndex: Int
    let durationSeconds: Double
    let points: [LapTracePoint]

    /// Binary search for the index whose cumulative distance is closest to `distance`.
    /// Returns nil if points is empty.
    func nearestIndex(byCumulativeDistance distance: Double) -> Int? {
        guard points.isEmpty == false else { return nil }

        var lo = 0
        var hi = points.count - 1

        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].cumulativeDistanceMeters < distance {
                lo = mid + 1
            } else {
                hi = mid
            }
        }

        // lo is the first index >= distance. Check if lo-1 is closer.
        if lo > 0 {
            let distLo = abs(points[lo].cumulativeDistanceMeters - distance)
            let distPrev = abs(points[lo - 1].cumulativeDistanceMeters - distance)
            if distPrev < distLo {
                return lo - 1
            }
        }

        return lo
    }

    /// Within a window around `centerIndex`, find the point closest to `coordinate` by haversine distance.
    func nearestIndex(byGPS coordinate: GeoPoint, around centerIndex: Int, windowSize: Int = 5) -> Int {
        let lo = max(0, centerIndex - windowSize)
        let hi = min(points.count - 1, centerIndex + windowSize)
        guard lo <= hi else { return centerIndex }

        var bestIndex = centerIndex
        var bestDistance = Double.greatestFiniteMagnitude

        for i in lo...hi {
            let d = points[i].coordinate.distance(to: coordinate)
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }

        return bestIndex
    }
}
