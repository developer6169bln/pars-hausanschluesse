import Foundation
import simd

/// Erzeugt aus vielen Magenta-Kabelpunkten eine glatte 3D-Mittellinie (Polyline) für Rohr-Darstellung.
enum MagentaCableAutoTrace {

    /// Berechnet eine Polyline entlang des größten zusammenhängenden Kabel-Clusters.
    /// - Parameters:
    ///   - points: Weltkoordinaten der als Kabel markierten Punkte.
    ///   - maxInputPoints: Obere Grenze für Rechenzeit (Zufallsstichprobe).
    static func computeCenterline(fromCablePoints points: [SIMD3<Float>], maxInputPoints: Int = 6500) -> [SIMD3<Float>] {
        guard points.count >= 35 else { return [] }

        var work = points
        if work.count > maxInputPoints {
            work.shuffle()
            work = Array(work.prefix(maxInputPoints))
        }

        guard let cluster = largestConnectedVoxelComponent(points: work, cellSize: 0.07) else { return [] }
        guard cluster.count >= 28 else { return [] }

        let line = centerlineFromClusterPCA(points: cluster, binLength: 0.038)
        guard line.count >= 2 else { return [] }

        // Mindestlänge entlang der Polyline (verwirft kleine Flecken)
        var span: Float = 0
        for i in 1..<line.count {
            span += simd_distance(line[i - 1], line[i])
        }
        guard span >= 0.12 else { return [] }

        return decimatePolyline(line, minSegmentLength: 0.022)
    }

    // MARK: - Voxel-Cluster (6-Nachbarschaft)

    private struct VoxelKey: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }

    private static func voxelKey(_ p: SIMD3<Float>, cellSize: Float) -> VoxelKey {
        VoxelKey(
            x: Int(floor(p.x / cellSize)),
            y: Int(floor(p.y / cellSize)),
            z: Int(floor(p.z / cellSize))
        )
    }

    private static func neighbors6(_ k: VoxelKey) -> [VoxelKey] {
        [
            VoxelKey(x: k.x + 1, y: k.y, z: k.z),
            VoxelKey(x: k.x - 1, y: k.y, z: k.z),
            VoxelKey(x: k.x, y: k.y + 1, z: k.z),
            VoxelKey(x: k.x, y: k.y - 1, z: k.z),
            VoxelKey(x: k.x, y: k.y, z: k.z + 1),
            VoxelKey(x: k.x, y: k.y, z: k.z - 1)
        ]
    }

    private static func largestConnectedVoxelComponent(points: [SIMD3<Float>], cellSize: Float) -> [SIMD3<Float>]? {
        var buckets: [VoxelKey: [SIMD3<Float>]] = [:]
        buckets.reserveCapacity(min(points.count / 4, 4096))
        for p in points {
            let k = voxelKey(p, cellSize: cellSize)
            buckets[k, default: []].append(p)
        }
        guard !buckets.isEmpty else { return nil }

        var visited = Set<VoxelKey>()
        visited.reserveCapacity(buckets.count)
        var best: [SIMD3<Float>] = []

        for start in buckets.keys {
            guard !visited.contains(start) else { continue }
            var queue: [VoxelKey] = [start]
            visited.insert(start)
            var acc: [SIMD3<Float>] = []
            acc.reserveCapacity(512)
            acc.append(contentsOf: buckets[start] ?? [])

            var index = 0
            while index < queue.count {
                let k = queue[index]
                index += 1
                for nk in neighbors6(k) {
                    guard let pts = buckets[nk], !visited.contains(nk) else { continue }
                    visited.insert(nk)
                    queue.append(nk)
                    acc.append(contentsOf: pts)
                }
            }
            if acc.count > best.count {
                best = acc
            }
        }
        return best.isEmpty ? nil : best
    }

    // MARK: - PCA + Bins entlang Hauptachse

    private static func centerlineFromClusterPCA(points: [SIMD3<Float>], binLength: Float) -> [SIMD3<Float>] {
        let n = Float(points.count)
        guard n >= 1 else { return [] }

        var mean = SIMD3<Float>(0, 0, 0)
        for p in points { mean += p }
        mean /= n

        var c00: Float = 0, c01: Float = 0, c02: Float = 0
        var c11: Float = 0, c12: Float = 0
        var c22: Float = 0
        for p in points {
            let d = p - mean
            c00 += d.x * d.x
            c01 += d.x * d.y
            c02 += d.x * d.z
            c11 += d.y * d.y
            c12 += d.y * d.z
            c22 += d.z * d.z
        }
        // Spaltenweise (symmetrische Kovarianzmatrix).
        let C = simd_float3x3(
            SIMD3(c00, c01, c02),
            SIMD3(c01, c11, c12),
            SIMD3(c02, c12, c22)
        )

        var axis = simd_normalize(SIMD3<Float>(1, 0.02, 0.01))
        for _ in 0..<36 {
            let w = C * axis
            let len = simd_length(w)
            guard len > 1e-8 else { break }
            axis = w / len
        }

        var tMin: Float = .greatestFiniteMagnitude
        var tMax: Float = -.greatestFiniteMagnitude
        var ts = [Float]()
        ts.reserveCapacity(points.count)
        for p in points {
            let t = simd_dot(p - mean, axis)
            ts.append(t)
            tMin = min(tMin, t)
            tMax = max(tMax, t)
        }
        guard tMax - tMin > 0.02 else { return [] }

        let invBin = 1.0 / binLength
        let binCount = max(1, Int(ceil((tMax - tMin) * invBin)) + 1)
        var sums = [SIMD3<Float>](repeating: .zero, count: binCount)
        var counts = [Int](repeating: 0, count: binCount)

        for i in points.indices {
            let b = Int(floor((ts[i] - tMin) * invBin))
            let bb = min(max(0, b), binCount - 1)
            sums[bb] += points[i]
            counts[bb] += 1
        }

        var out: [SIMD3<Float>] = []
        for i in 0..<binCount where counts[i] > 0 {
            out.append(sums[i] / Float(counts[i]))
        }
        return out
    }

    private static func decimatePolyline(_ pts: [SIMD3<Float>], minSegmentLength: Float) -> [SIMD3<Float>] {
        guard var last = pts.first else { return [] }
        var out = [last]
        for i in 1..<pts.count {
            let p = pts[i]
            if simd_distance(last, p) >= minSegmentLength {
                out.append(p)
                last = p
            }
        }
        if out.count == 1, pts.count > 1, let end = pts.last {
            out.append(end)
        }
        return out
    }
}
