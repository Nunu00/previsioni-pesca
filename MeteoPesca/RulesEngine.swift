import Foundation

public class RulesEngine {
    
    public static func evaluateForecast(
        date: Date,
        location: Location,
        sunrise: Date?,
        sunset: Date?,
        moonrise: Date?,
        moonset: Date?,
        moonTransit: Date?,
        moonAntiTransit: Date?,
        moonAge: Double,
        tides: [TideEvent]
    ) -> DailyForecast {
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // 1. Calculate Tide Amplitude
        var maxAmplitude = 0.0
        if tides.count >= 2 {
            for i in 0..<(tides.count - 1) {
                let diff = abs(tides[i].height - tides[i+1].height)
                if diff > maxAmplitude {
                    maxAmplitude = diff
                }
            }
        }
        
        // 2. Generate Solunar Periods
        var periods: [SolunarPeriod] = []
        
        // Major Periods: ±1 hour around lunar transit and anti-transit
        if let transit = moonTransit {
            periods.append(SolunarPeriod(
                startTime: transit.addingTimeInterval(-3600),
                endTime: transit.addingTimeInterval(3600),
                type: .maggior,
                description: "Transito Lunare (Luna in meridiano)"
            ))
        }
        if let antiTransit = moonAntiTransit {
            periods.append(SolunarPeriod(
                startTime: antiTransit.addingTimeInterval(-3600),
                endTime: antiTransit.addingTimeInterval(3600),
                type: .maggior,
                description: "Transito Opposto (Luna in nadir)"
            ))
        }
        
        // Minor Periods: ±30 minutes around moonrise and moonset
        if let rise = moonrise {
            periods.append(SolunarPeriod(
                startTime: rise.addingTimeInterval(-1800),
                endTime: rise.addingTimeInterval(1800),
                type: .minor,
                description: "Alba Lunare (Sorgere della Luna)"
            ))
        }
        if let set = moonset {
            periods.append(SolunarPeriod(
                startTime: set.addingTimeInterval(-1800),
                endTime: set.addingTimeInterval(1800),
                type: .minor,
                description: "Tramonto Lunare (Tramonto della Luna)"
            ))
        }
        
        // 3. Mark enhanced peaks (overlapping with sunrise/sunset ±30 minutes)
        for i in 0..<periods.count {
            var isEnhanced = false
            for sunTime in [sunrise, sunset].compactMap({ $0 }) {
                // Check overlap
                let startOverlap = max(periods[i].startTime, sunTime.addingTimeInterval(-1800))
                let endOverlap = min(periods[i].endTime, sunTime.addingTimeInterval(1800))
                if startOverlap <= endOverlap {
                    isEnhanced = true
                    break
                }
            }
            periods[i].isEnhanced = isEnhanced
        }
        
        // 4. Build Hourly Intervals & Calculate Scores
        var intervals: [HourlyInterval] = []
        for hour in 0..<24 {
            guard let intervalStart = calendar.date(byAdding: .hour, value: hour, to: startOfDay),
                  let intervalEnd = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay) else { continue }
            
            var hourScore = 0.5 // baseline activity
            var isMajor = false
            var isMinor = false
            var isEnhanced = false
            
            // Check matching periods
            for period in periods {
                // If the hour overlaps with the period
                let overlapStart = max(intervalStart, period.startTime)
                let overlapEnd = min(intervalEnd, period.endTime)
                
                if overlapStart < overlapEnd {
                    let overlapDuration = overlapEnd.timeIntervalSince(overlapStart) / 3600.0
                    let bonus: Double = (period.type == .maggior) ? 1.5 : 1.0
                    hourScore += bonus * overlapDuration
                    
                    if period.type == .maggior { isMajor = true }
                    if period.type == .minor { isMinor = true }
                    if period.isEnhanced {
                        isEnhanced = true
                        hourScore += 0.5 // additional bonus for sunrise/sunset overlap
                    }
                }
            }
            
            // Tide rate of change bonus
            let hStart = TideEngine.calculateHeight(at: intervalStart, coordinate: location.coordinate)
            let hEnd = TideEngine.calculateHeight(at: intervalEnd, coordinate: location.coordinate)
            let tideMovement = abs(hEnd - hStart)
            hourScore += tideMovement * 10.0 // add bonus for active tide movement (multiplied by 10 for Mediterranean ranges)
            
            // Map score to Activity level
            let level: ActivityLevel
            if hourScore < 1.0 {
                level = .bassa
            } else if hourScore < 1.8 {
                level = .media
            } else if hourScore < 2.8 {
                level = .alta
            } else {
                level = .moltoAlta
            }
            
            intervals.append(HourlyInterval(
                hour: hour,
                startTime: intervalStart,
                endTime: intervalEnd,
                activity: level,
                score: hourScore,
                isMajorPeriod: isMajor,
                isMinorPeriod: isMinor,
                isEnhanced: isEnhanced
            ))
        }
        
        // 5. Calculate Daily Activity Rating using our calibrated solunar and tide rules
        let coeff = TideEngine.calculateTideCoefficient(at: date, coordinate: location.coordinate)
        
        let dailyLevel: ActivityLevel
        let distToQuarter = min(abs(moonAge - 7.38), abs(moonAge - 22.15))
        let isQuarter = distToQuarter <= 0.5
        
        // Count enhanced periods
        let enhancedCount = periods.filter { $0.isEnhanced }.count
        
        // Query moon distance for Apogee week penalty
        let ast = AstronomyEngine.calculateAstronomy(date: date, coordinate: location.coordinate)
        let moonDistance = ast.moonDistance
        
        if isQuarter {
            dailyLevel = .bassa
        } else if coeff < 38.0 {
            dailyLevel = .bassa
        } else {
            if enhancedCount >= 2 {
                dailyLevel = .moltoAlta // 3 fish
            } else if enhancedCount == 1 {
                if moonDistance > 403000.0 && coeff < 65.0 {
                    dailyLevel = .media // 1 fish
                } else {
                    dailyLevel = .alta // 2 fish
                }
            } else { // enhancedCount == 0
                if coeff >= 68.0 {
                    dailyLevel = .alta // 2 fish
                } else if moonDistance > 403000.0 {
                    dailyLevel = .bassa // 0 fish
                } else {
                    dailyLevel = .media // 1 fish
                }
            }
        }
        
        // 7. Get Moon illumination for display
        let moonIllumination = AstronomyEngine.calculateAstronomy(date: date, coordinate: location.coordinate).moonIllumination
        let moonPhase = AstronomyEngine.calculateAstronomy(date: date, coordinate: location.coordinate).moonPhase
        
        return DailyForecast(
            date: date,
            location: location,
            sunrise: sunrise,
            sunset: sunset,
            moonrise: moonrise,
            moonset: moonset,
            moonTransit: moonTransit,
            moonAntiTransit: moonAntiTransit,
            moonPhase: moonPhase,
            moonAge: moonAge,
            moonIllumination: moonIllumination,
            tides: tides,
            maxTideAmplitude: maxAmplitude,
            solunarPeriods: periods,
            dailyActivity: dailyLevel,
            hourlyIntervals: intervals
        )
    }
}
