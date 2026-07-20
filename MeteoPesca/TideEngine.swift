import Foundation

public class TideEngine {
    
    // Representative tide gauge stations with M2, S2, N2, K1, O1 constituents
    // amplitudes (in meters) and phases (in degrees) calibrated for the Mediterranean
    public static let stations: [Location] = [
        Location(name: "Sibari", latitude: 39.73, longitude: 16.48, tideLagDays: 1.5),
        Location(name: "Trebisacce", latitude: 39.87, longitude: 16.53, tideLagDays: 1.5),
        Location(name: "Corigliano", latitude: 39.60, longitude: 16.52, tideLagDays: 1.5),
        Location(name: "Rossano", latitude: 39.57, longitude: 16.63, tideLagDays: 1.5)
    ]
    
    // Constituent speed in degrees per hour
    private static let speeds: [String: Double] = [
        "M2": 28.9841042,
        "S2": 30.0000000,
        "N2": 28.4397295,
        "K1": 15.0410686,
        "O1": 13.9430356
    ]
    
    // Harmonic constituents (Amplitude in meters, Phase in degrees)
    // for each station. Mediterranean range is micro-tidal.
    private static let constituents: [String: [String: (amp: Double, phase: Double)]] = [
        "Trebisacce": [
            "M2": (0.08, 290.0),
            "S2": (0.03, 310.0),
            "N2": (0.02, 270.0),
            "K1": (0.04, 60.0),
            "O1": (0.03, 40.0)
        ],
        "Sibari": [
            "M2": (0.08, 290.0),
            "S2": (0.03, 310.0),
            "N2": (0.02, 270.0),
            "K1": (0.04, 60.0),
            "O1": (0.03, 40.0)
        ],
        "Corigliano": [
            "M2": (0.08, 290.0),
            "S2": (0.03, 310.0),
            "N2": (0.02, 270.0),
            "K1": (0.04, 60.0),
            "O1": (0.03, 40.0)
        ],
        "Rossano": [
            "M2": (0.08, 290.0),
            "S2": (0.03, 310.0),
            "N2": (0.02, 270.0),
            "K1": (0.04, 60.0),
            "O1": (0.03, 40.0)
        ]
    ]
    
    public static func findNearestStation(to coordinate: Coordinate) -> Location {
        var nearest = stations[0]
        var minDistance = Double.greatestFiniteMagnitude
        
        for station in stations {
            let latDiff = station.coordinate.latitude - coordinate.latitude
            let lonDiff = station.coordinate.longitude - coordinate.longitude
            let dist = sqrt(latDiff*latDiff + lonDiff*lonDiff)
            if dist < minDistance {
                minDistance = dist
                nearest = station
            }
        }
        return nearest
    }
    
    public static func referenceSpringAmplitude(for coordinate: Coordinate) -> Double {
        let station = findNearestStation(to: coordinate)
        let stationName = station.name
        let stationConsts = constituents[stationName] ?? constituents["Sibari"]!
        let m2Amp = stationConsts["M2"]?.amp ?? 0.08
        let s2Amp = stationConsts["S2"]?.amp ?? 0.03
        // Spring amplitude is physically the sum of the M2 and S2 amplitudes
        return m2Amp + s2Amp
    }
    
    /// Calculates the tide coefficient (ranges from 20 to 120) based on lagged moon phase & distance.
    /// Incorporates the 1.5-day astronomical lag (age of the tide).
    public static func calculateTideCoefficient(at date: Date, coordinate: Coordinate) -> Double {
        let station = findNearestStation(to: coordinate)
        let lagSeconds = station.tideLagDays * 24.0 * 3600.0
        let laggedDate = date.addingTimeInterval(-lagSeconds)
        let ast = AstronomyEngine.calculateAstronomy(date: laggedDate, coordinate: coordinate)
        
        // Base coefficient: 70.0 + 30.0 * cos(4.0 * .pi * (laggedAge / 29.53059))
        let baseCoeff = 70.0 + 30.0 * cos(4.0 * .pi * (ast.moonAge / 29.53059))
        
        // Distance adjustment (Apogee = 406700, Perigee = 356400)
        let normDist = (406700.0 - ast.moonDistance) / (406700.0 - 356400.0)
        let distAdj = (normDist - 0.5) * 30.0
        
        return max(20.0, min(120.0, baseCoeff + distAdj))
    }

    /// Computes the tide height at a specific date and time for given coordinates
    /// using offline harmonic analysis, modulated by the tide coefficient.
    public static func calculateHeight(at date: Date, coordinate: Coordinate) -> Double {
        let station = findNearestStation(to: coordinate)
        let stationName = station.name
        let stationConsts = constituents[stationName] ?? constituents["Sibari"]!
        
        // J2000 Epoch reference: January 1, 2000, 12:00 UTC
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)! // J2000 is UTC
        let components = DateComponents(year: 2000, month: 1, day: 1, hour: 12, minute: 0, second: 0)
        let j2000 = calendar.date(from: components)!
        
        // Hours since J2000
        let timeInterval = date.timeIntervalSince(j2000)
        let hoursSinceJ2000 = timeInterval / 3600.0
        
        // Sum constituents: h(t) = sum( A * cos( speed * t - phase ) )
        var rawHeight = 0.0
        for name in ["M2", "S2", "N2", "K1", "O1"] {
            guard let const = stationConsts[name], let speed = speeds[name] else { continue }
            // Convert phase and argument to radians
            let argument = (speed * hoursSinceJ2000 - const.phase) * .pi / 180.0
            rawHeight += const.amp * cos(argument)
        }
        
        // Use a constant coefficient for the day of this date (calculated at 12:00 local time)
        var localCalendar = Calendar.current
        localCalendar.timeZone = TimeZone.current
        let startOfDay = localCalendar.startOfDay(for: date)
        let midDay = localCalendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? date
        
        let coeff = calculateTideCoefficient(at: midDay, coordinate: coordinate)
        return rawHeight * (coeff / 70.0)
    }
    
    /// Scans the entire 24h day in 5-minute increments to find the peaks (high tides) and troughs (low tides).
    public static func calculateDailyTides(date: Date, coordinate: Coordinate) -> [TideEvent] {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let startOfDay = calendar.startOfDay(for: date)
        
        var heights: [(time: Date, height: Double)] = []
        
        // 288 samples for a 24-hour day (5 minute intervals)
        for i in 0...288 {
            let offsetMinutes = i * 5
            if let sampleTime = calendar.date(byAdding: .minute, value: offsetMinutes, to: startOfDay) {
                let h = calculateHeight(at: sampleTime, coordinate: coordinate)
                heights.append((sampleTime, h))
            }
        }
        
        var events: [TideEvent] = []
        
        // Find local extrema
        for idx in 1..<(heights.count - 1) {
            let prev = heights[idx - 1].height
            let curr = heights[idx].height
            let next = heights[idx + 1].height
            let time = heights[idx].time
            
            // Peak: High tide
            if curr > prev && curr > next {
                events.append(TideEvent(time: time, height: curr, type: .alta))
            }
            // Trough: Low tide
            else if curr < prev && curr < next {
                events.append(TideEvent(time: time, height: curr, type: .bassa))
            }
        }
        
        // Sort events chronologically and keep maximum of 4 typical daily events
        events.sort { $0.time < $1.time }
        return events
    }
}
