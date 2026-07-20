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
        tides: [TideEvent],
        weather: WeatherFactor = WeatherFactor(cloudCoverPercent: 20.0, windDirectionChange: 10.0, swellHeight: 0.2, surfaceTempDelta24h: 0.0),
        waterTempCelsius: Double = 20.0
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
        let weatherMult = weather.multiplier()
        let tOpt = 20.0
        let sigmaCold = 5.0
        let sigmaWarm = 10.0
        let fWaterTemp: Double
        if waterTempCelsius < tOpt {
            fWaterTemp = exp(-pow(waterTempCelsius - tOpt, 2.0) / (2.0 * pow(sigmaCold, 2.0)))
        } else {
            fWaterTemp = max(0.70, exp(-pow(waterTempCelsius - tOpt, 2.0) / (2.0 * pow(sigmaWarm, 2.0))))
        }
        
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
            
            // Scientific Tidal Phase Activity Factor (Common Goby & Reef fish studies)
            let midHourDate = intervalStart.addingTimeInterval(1800)
            let tidalFactor = calculateTidalActivityFactor(date: midHourDate, tides: tides, coordinate: location.coordinate, maxAmplitude: maxAmplitude)
            hourScore *= tidalFactor
            hourScore *= weatherMult
            hourScore *= fWaterTemp
            hourScore = min(hourScore, 3.2) // apply stabilizing cap to prevent multiple overlapping bonuses from inflating the score
            
            // Map score to Activity level
            let level: ActivityLevel
            if hourScore < 0.6 {
                level = .bassa
            } else if hourScore < 1.2 {
                level = .moderata
            } else if hourScore < 1.8 {
                level = .buona
            } else if hourScore < 2.5 {
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
        let enhancedCount = periods.filter { $0.isEnhanced }.count
        
        let ast = AstronomyEngine.calculateAstronomy(date: date, coordinate: location.coordinate)
        let moonDistance = ast.moonDistance
        
        // --- Principled Physics-Based Multiplicative Model ---
        // 1. Moon Phase Factor (0.0 to 1.0)
        // Cosine squared model: peaks at New Moon (age=0/29.53) and Full Moon (age=14.77), troughs at Quarters
        let baseP = 0.10
        let angle = 2.0 * Double.pi * moonAge / 29.53059
        let fPhase = baseP + (1.0 - baseP) * pow(cos(angle), 2.0)
        
        // 2. Moon Distance Factor (using inverse-cube relative gravitational tidal force)
        // Normalised relative to mean distance 384,400 km
        let fDist = pow(384400.0 / moonDistance, 3.0)
        
        // 3. Tide range/coefficient Factor (0.0 to 1.0)
        let baseC = 0.30
        let fCoeff = baseC + (1.0 - baseC) * (Double(coeff) - 20.0) / 100.0
        
        // 4. Overlaps/Solunar peak alignment Factor (1.0 to 1.6)
        let wO = 0.60
        let fOverlap = 1.0 + wO * Double(enhancedCount)
        
        // Combine multiplicatively and apply environmental modulations
        var score = fPhase * fDist * fCoeff * fOverlap
        
        // Weather composite factor
        score *= weather.multiplier()
        
        // Bell-shaped Water Temp factor (Gaussian optimal performance curve at 20°C with sigma=5.0)
        score *= fWaterTemp
        score = min(score, 1.8) // apply stabilizing cap to prevent extreme inflation
        
        // Map continuous score to daily activity level using optimized thresholds:
        // T1 = 0.166, T2 = 0.416, T3 = 1.288
        let dailyLevel: ActivityLevel
        if score < 0.45 {
            dailyLevel = .bassa
        } else if score < 0.90 {
            dailyLevel = .moderata
        } else if score < 1.26 {
            dailyLevel = .buona
        } else if score < 1.62 {
            dailyLevel = .alta
        } else {
            dailyLevel = .moltoAlta
        }
        
        // 7. Get Moon illumination for display
        let moonIllumination = AstronomyEngine.calculateAstronomy(date: date, coordinate: location.coordinate).moonIllumination
        let moonPhase = AstronomyEngine.calculateAstronomy(date: date, coordinate: location.coordinate).moonPhase
        
        let bestWindowsList = calculateBestWindows(
            date: date,
            location: location,
            sunrise: sunrise,
            sunset: sunset,
            moonrise: moonrise,
            moonset: moonset,
            moonTransit: moonTransit,
            moonAntiTransit: moonAntiTransit,
            moonAge: moonAge,
            tides: tides,
            weatherMult: weatherMult,
            fWaterTemp: fWaterTemp,
            fPhase: fPhase,
            maxAmplitude: maxAmplitude,
            periods: periods
        )
        
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
            hourlyIntervals: intervals,
            bestWindows: bestWindowsList,
            rawScore: score,
            moonPhaseFactor: fPhase,
            moonDistanceFactor: fDist,
            tideCoeffFactor: fCoeff,
            solunarOverlapFactor: fOverlap,
            weatherFactorVal: weatherMult,
            waterTempFactor: fWaterTemp
        )
    }
    
    private static func calculateTidalActivityFactor(
        date: Date,
        tides: [TideEvent],
        coordinate: Coordinate,
        maxAmplitude: Double
    ) -> Double {
        var minDiffMinutes = Double.greatestFiniteMagnitude
        var nearestEvent: TideEvent? = nil
        
        for event in tides {
            let diff = event.time.timeIntervalSince(date) / 60.0
            if abs(diff) < abs(minDiffMinutes) {
                minDiffMinutes = diff
                nearestEvent = event
            }
        }
        
        // 1. Calculate rate of change of tide height (current velocity proxy)
        let dateOneHourAgo = date.addingTimeInterval(-3600)
        let currentLevel = TideEngine.calculateHeight(at: date, coordinate: coordinate)
        let previousLevel = TideEngine.calculateHeight(at: dateOneHourAgo, coordinate: coordinate)
        
        let rateOfChange = abs(currentLevel - previousLevel)
        
        // Normalize by the fixed reference spring amplitude of the port to prevent circular scaling on neap tide days
        let referenceSpring = TideEngine.referenceSpringAmplitude(for: coordinate)
        let normalizedRate = rateOfChange / max(referenceSpring, 0.05)
        
        // Velocity factor: up to 0.4 bonus at max current speed (midpoint of cycle)
        let velocityFactor = 1.0 + min(normalizedRate * 0.8, 0.4)
        
        // 2. Transition (cambio marea): bonus extra in the 90 minutes BEFORE the extreme (rising or falling towards it)
        var transitionBonus = 0.0
        if minDiffMinutes > 0 && minDiffMinutes <= 90.0 {
            transitionBonus = 0.2
        }
        
        // 3. Slack water penalty: if we are within 30 minutes of low tide, we apply a penalty.
        var slackMultiplier = 1.0
        if let nearest = nearestEvent, nearest.type == .bassa && abs(minDiffMinutes) <= 30.0 {
            slackMultiplier = 0.7
        }
        
        return (velocityFactor + transitionBonus) * slackMultiplier
    }
    
    private static func calculateBestWindows(
        date: Date,
        location: Location,
        sunrise: Date?,
        sunset: Date?,
        moonrise: Date?,
        moonset: Date?,
        moonTransit: Date?,
        moonAntiTransit: Date?,
        moonAge: Double,
        tides: [TideEvent],
        weatherMult: Double,
        fWaterTemp: Double,
        fPhase: Double,
        maxAmplitude: Double,
        periods: [SolunarPeriod]
    ) -> [ActivityWindow] {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // 1. Generate 15-minute slot scores (96 slots in 24 hours)
        var slots: [SlotScore] = []
        for i in 0..<96 {
            let offset = Double(i) * 15.0 * 60.0
            guard let slotStart = calendar.date(byAdding: .second, value: Int(offset), to: startOfDay) else { continue }
            let slotEnd = slotStart.addingTimeInterval(15.0 * 60.0)
            
            var solunarBonus = 0.0
            for period in periods {
                let overlapStart = max(slotStart, period.startTime)
                let overlapEnd = min(slotEnd, period.endTime)
                if overlapStart < overlapEnd {
                    let overlapDuration = overlapEnd.timeIntervalSince(overlapStart) / 3600.0
                    let baseBonus: Double = (period.type == .maggior) ? 1.5 : 1.0
                    solunarBonus += baseBonus * overlapDuration
                    if period.isEnhanced {
                        solunarBonus += 0.5 * (overlapDuration / 1.0)
                    }
                }
            }
            let solunarFactor = 1.0 + (solunarBonus / 0.25) * 0.5
            
            let midSlotDate = slotStart.addingTimeInterval(450.0)
            let tideFactor = calculateTidalActivityFactor(date: midSlotDate, tides: tides, coordinate: location.coordinate, maxAmplitude: maxAmplitude)
            
            let baseScore = 0.5
            var slotScore = baseScore * solunarFactor * tideFactor * weatherMult * fWaterTemp * fPhase
            slotScore = min(slotScore, 3.2)
            
            let breakdown = ScoreBreakdown(
                tide: tideFactor,
                solunar: solunarFactor,
                weather: weatherMult,
                waterTemp: fWaterTemp,
                lunarPhase: fPhase
            )
            
            slots.append(SlotScore(date: midSlotDate, score: slotScore, breakdown: breakdown))
        }
        
        // 2. Smooth the scores using a 3-slot moving average
        let rawScores = slots.map { $0.score }
        var smoothedScores = rawScores
        if rawScores.count > 2 {
            for i in 1..<(rawScores.count - 1) {
                smoothedScores[i] = (rawScores[i - 1] + rawScores[i] + rawScores[i + 1]) / 3.0
            }
        }
        
        var smoothedSlots: [SlotScore] = []
        for i in 0..<slots.count {
            smoothedSlots.append(SlotScore(
                date: slots[i].date,
                score: smoothedScores[i],
                breakdown: slots[i].breakdown
            ))
        }
        
        // 3. Find local peaks (interior slots greater than neighbours)
        var peakIndices: [Int] = []
        if smoothedSlots.count > 2 {
            for i in 1..<(smoothedSlots.count - 1) {
                let prev = smoothedSlots[i - 1].score
                let curr = smoothedSlots[i].score
                let next = smoothedSlots[i + 1].score
                if curr > prev && curr > next {
                    peakIndices.append(i)
                }
            }
        }
        
        // 4. Rank peaks
        let rankedIndices = peakIndices.sorted { smoothedSlots[$0].score > smoothedSlots[$1].score }
        
        var windows: [ActivityWindow] = []
        
        // 5. Expand peaks to windows
        for idx in rankedIndices {
            let peakScore = smoothedSlots[idx].score
            let threshold = peakScore * 0.85
            
            var start = idx
            var end = idx
            while start > 0 && smoothedSlots[start - 1].score >= threshold {
                start -= 1
            }
            while end < smoothedSlots.count - 1 && smoothedSlots[end + 1].score >= threshold {
                end += 1
            }
            
            let startDate = smoothedSlots[start].date.addingTimeInterval(-450.0) // align to slot boundary
            let endDate = smoothedSlots[end].date.addingTimeInterval(450.0)
            
            guard endDate.timeIntervalSince(startDate) >= 45.0 * 60.0 else { continue }
            
            let label = classifyScore(peakScore)
            let efficacy = min(100, Int(round((peakScore / 3.2) * 100.0)))
            let reasons = topReasons(from: smoothedSlots[idx].breakdown)
            
            let candidate = ActivityWindow(
                start: startDate,
                end: endDate,
                peak: smoothedSlots[idx].date,
                peakScore: peakScore,
                label: label,
                efficacyPercent: efficacy,
                reasons: reasons
            )
            
            if windows.allSatisfy({ abs($0.peak.timeIntervalSince(candidate.peak)) > 5400.0 }) {
                windows.append(candidate)
            }
        }
        
        // 6. Merge close windows
        let mergedWindows = mergeOverlappingOrCloseWindows(windows)
        
        // 7. Limit to top 3 and sort chronologically
        let finalWindows = Array(mergedWindows.sorted { $0.efficacyPercent > $1.efficacyPercent }.prefix(3))
        return finalWindows.sorted { $0.start < $1.start }
    }
    
    private static func classifyScore(_ score: Double) -> ActivityLevel {
        if score < 0.6 {
            return .bassa
        } else if score < 1.2 {
            return .moderata
        } else if score < 1.8 {
            return .buona
        } else if score < 2.5 {
            return .alta
        } else {
            return .moltoAlta
        }
    }
    
    private static func topReasons(from breakdown: ScoreBreakdown) -> [String] {
        var reasons: [String] = []
        if breakdown.tide > 1.25 {
            reasons.append("corrente marea favorevole")
        } else if breakdown.tide > 1.05 {
            reasons.append("flusso marea attivo")
        }
        if breakdown.solunar > 1.20 {
            reasons.append("periodo solunare attivo")
        }
        if breakdown.weather > 1.10 {
            reasons.append("meteo costiero favorevole")
        }
        if breakdown.waterTemp < 0.90 {
            reasons.append("temperatura acqua penalizzante")
        } else if breakdown.waterTemp > 1.05 {
            reasons.append("temperatura acqua favorevole")
        }
        if breakdown.lunarPhase > 0.80 {
            reasons.append("fase lunare ottimale")
        } else if breakdown.lunarPhase < 0.30 {
            reasons.append("fase lunare debole")
        }
        if reasons.isEmpty {
            reasons.append("condizioni stabili")
        }
        return Array(reasons.prefix(3))
    }
    
    private static func mergeOverlappingOrCloseWindows(_ windows: [ActivityWindow]) -> [ActivityWindow] {
        guard windows.count > 1 else { return windows }
        let sorted = windows.sorted { $0.start < $1.start }
        var merged: [ActivityWindow] = []
        var current = sorted[0]
        
        for i in 1..<sorted.count {
            let next = sorted[i]
            let gap = next.start.timeIntervalSince(current.end)
            if gap < 30 * 60 {
                let peakDate = (current.peakScore >= next.peakScore) ? current.peak : next.peak
                let peakScore = max(current.peakScore, next.peakScore)
                let label = (current.peakScore >= next.peakScore) ? current.label : next.label
                let efficacy = (current.peakScore >= next.peakScore) ? current.efficacyPercent : next.efficacyPercent
                var reasonsSet = Set(current.reasons)
                for r in next.reasons {
                    reasonsSet.insert(r)
                }
                current = ActivityWindow(
                    start: current.start,
                    end: max(current.end, next.end),
                    peak: peakDate,
                    peakScore: peakScore,
                    label: label,
                    efficacyPercent: efficacy,
                    reasons: Array(reasonsSet)
                )
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }
}

public struct ScoreBreakdown: Codable, Hashable {
    public let tide: Double
    public let solunar: Double
    public let weather: Double
    public let waterTemp: Double
    public let lunarPhase: Double
}

public struct SlotScore {
    public let date: Date
    public let score: Double
    public let breakdown: ScoreBreakdown
}
