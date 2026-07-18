import Foundation
import SwiftAA

public class AstronomyEngine {
    
    /// Calculates the solar and lunar ephemerides for a given date and coordinates.
    /// Uses Jean Meeus algorithms via SwiftAA.
    public static func calculateAstronomy(date: Date, coordinate: Coordinate) -> (
        sunrise: Date?,
        sunset: Date?,
        moonrise: Date?,
        moonset: Date?,
        moonTransit: Date?,
        moonAntiTransit: Date?,
        moonPhase: String,
        moonAge: Double,
        moonIllumination: Double,
        moonDistance: Double
    ) {
        // Convert to local mid-day (12:00) to get representative day coordinates
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let midDay = calendar.date(byAdding: .hour, value: 12, to: startOfDay) else {
            return (nil, nil, nil, nil, nil, nil, "N/A", 0, 0, 384400.0)
        }
        
        let jd = JulianDay(midDay)
        
        // Define coordinates in SwiftAA.
        // Longitude must be positively westward (degrees West).
        // Since Italy longitudes are positive Eastward, we must pass negative longitude.
        let observer = GeographicCoordinates(
            positivelyWestwardLongitude: Degree(-coordinate.longitude),
            latitude: Degree(coordinate.latitude)
        )
        
        // 1. Solar Events (Sunrise & Sunset)
        let sun = Sun(julianDay: jd)
        let sunTimes = sun.riseTransitSetTimes(for: observer)
        let sunrise = sunTimes.riseTime?.date
        let sunset = sunTimes.setTime?.date
        
        // 2. Lunar Events (Moonrise, Moonset & Meridian Transit)
        let moon = Moon(julianDay: jd)
        let moonTimes = moon.riseTransitSetTimes(for: observer)
        let moonrise = moonTimes.riseTime?.date
        let moonset = moonTimes.setTime?.date
        let moonTransit = moonTimes.transitTime?.date
        
        // 3. Nadiral Lunar Transit (Anti-transit)
        // Nadir transit (Moon underfoot) is equivalent to meridian transit at opposite longitude (180 degrees away)
        let oppositeObserver = GeographicCoordinates(
            positivelyWestwardLongitude: Degree(-(coordinate.longitude + 180.0)),
            latitude: Degree(coordinate.latitude)
        )
        let oppositeMoonTimes = moon.riseTransitSetTimes(for: oppositeObserver)
        let moonAntiTransit = oppositeMoonTimes.transitTime?.date
        
        // 4. Moon Phase & Illumination
        let sunLong = sun.eclipticCoordinates.lambda
        let moonLong = moon.eclipticCoordinates.lambda
        var diffLong = moonLong.value - sunLong.value
        if diffLong < 0 { diffLong += 360.0 }
        
        let age = (diffLong / 360.0) * 29.53059
        let illumination = moon.illuminatedFraction() * 100.0
        
        let phaseName: String
        switch diffLong {
        case 0..<22.5, 337.5...360.0:
            phaseName = "Luna Nuova"
        case 22.5..<67.5:
            phaseName = "Luna Crescente (Falce)"
        case 67.5..<112.5:
            phaseName = "Primo Quarto"
        case 112.5..<157.5:
            phaseName = "Gibbosa Crescente"
        case 157.5..<202.5:
            phaseName = "Luna Piena"
        case 202.5..<247.5:
            phaseName = "Gibbosa Calante"
        case 247.5..<292.5:
            phaseName = "Ultimo Quarto"
        case 292.5..<337.5:
            phaseName = "Luna Calante (Falce)"
        default:
            phaseName = "Luna Nuova"
        }
        
        let moonDistance = moon.distance.value
        return (sunrise, sunset, moonrise, moonset, moonTransit, moonAntiTransit, phaseName, age, illumination, moonDistance)
    }
}
