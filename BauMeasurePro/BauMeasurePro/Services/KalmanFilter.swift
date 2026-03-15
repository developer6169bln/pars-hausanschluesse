import Foundation

/// Einfacher 1D-Kalman-Filter zur Glättung von Messwerten (z. B. AR-Distanz).
/// Reduziert Tracking-Noise und kurzfristigen Drift für stabilere Anzeige.
struct KalmanFilter {
    private var estimate: Float
    private var error: Float
    private let q: Float  // Prozessrauschen
    private let r: Float  // Messrauschen

    /// Erstellt einen Filter mit optionalem Startwert (erste Messung).
    init(initialValue: Float? = nil, processNoise q: Float = 0.01, measurementNoise r: Float = 0.1) {
        self.estimate = initialValue ?? 0
        self.error = initialValue != nil ? 0.1 : 1
        self.q = q
        self.r = r
    }

    /// Aktualisiert den Filter mit einer neuen Messung; gibt den geglätteten Schätzwert zurück.
    mutating func update(measurement: Float) -> Float {
        error += q
        let k = error / (error + r)
        estimate += k * (measurement - estimate)
        error *= (1 - k)
        return estimate
    }

    /// Setzt den Filter zurück (z. B. bei neuer Messung).
    mutating func reset(initialValue: Float? = nil) {
        estimate = initialValue ?? 0
        error = initialValue != nil ? 0.1 : 1
    }
}
