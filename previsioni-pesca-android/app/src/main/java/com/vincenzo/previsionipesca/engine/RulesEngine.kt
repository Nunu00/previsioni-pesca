package com.vincenzo.previsionipesca.engine

import com.vincenzo.previsionipesca.models.*
import org.shredzone.commons.suncalc.MoonIllumination
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.*
import kotlin.math.*

object RulesEngine {

    fun evaluateForecast(
        date: Date,
        location: Location,
        sunrise: Date?,
        sunset: Date?,
        moonrise: Date?,
        moonset: Date?,
        moonTransit: Date?,
        moonAntiTransit: Date?,
        moonAge: Double,
        tides: List<TideEvent>,
        weather: WeatherFactor = WeatherFactor(20.0, 10.0, 0.2, 0.0, 4.0),
        waterTempCelsius: Double = 20.0
    ): DailyForecast {
        val calendar = Calendar.getInstance().apply {
            time = date
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfDay = calendar.time

        // 1. Calculate Tide Amplitude
        var maxAmplitude = 0.0
        if (tides.size >= 2) {
            for (i in 0 until tides.size - 1) {
                val diff = abs(tides[i].height - tides[i + 1].height)
                if (diff > maxAmplitude) {
                    maxAmplitude = diff
                }
            }
        }

        // 2. Generate Solunar Periods
        val periods = mutableListOf<SolunarPeriod>()

        // Major Periods: ±1 hour around lunar transit and anti-transit
        moonTransit?.let {
            periods.add(
                SolunarPeriod(
                    startTime = Date(it.time - 3600000),
                    endTime = Date(it.time + 3600000),
                    type = SolunarType.MAGGIOR,
                    description = "Transito Lunare (Luna in meridiano)"
                )
            )
        }
        moonAntiTransit?.let {
            periods.add(
                SolunarPeriod(
                    startTime = Date(it.time - 3600000),
                    endTime = Date(it.time + 3600000),
                    type = SolunarType.MAGGIOR,
                    description = "Transito Opposto (Luna in nadir)"
                )
            )
        }

        // Minor Periods: ±30 minutes around moonrise and moonset
        moonrise?.let {
            periods.add(
                SolunarPeriod(
                    startTime = Date(it.time - 1800000),
                    endTime = Date(it.time + 1800000),
                    type = SolunarType.MINOR,
                    description = "Alba Lunare (Sorgere della Luna)"
                )
            )
        }
        moonset?.let {
            periods.add(
                SolunarPeriod(
                    startTime = Date(it.time - 1800000),
                    endTime = Date(it.time + 1800000),
                    type = SolunarType.MINOR,
                    description = "Tramonto Lunare (Tramonto della Luna)"
                )
            )
        }

        // 3. Mark enhanced peaks (overlapping with sunrise/sunset ±30 minutes)
        for (period in periods) {
            var isEnhanced = false
            val sunTimesList = listOfNotNull(sunrise, sunset)
            for (sunTime in sunTimesList) {
                val startOverlap = max(period.startTime.time, sunTime.time - 1800000)
                val endOverlap = min(period.endTime.time, sunTime.time + 1800000)
                if (startOverlap <= endOverlap) {
                    isEnhanced = true
                    break
                }
            }
            period.isEnhanced = isEnhanced
        }

        // 4. Build Hourly Intervals & Calculate Scores
        val weatherMult = weather.multiplier()
        val tOpt = 20.0
        val sigmaCold = 5.0
        val sigmaWarm = 10.0
        val fWaterTemp: Double = if (waterTempCelsius < tOpt) {
            exp(-(waterTempCelsius - tOpt).pow(2.0) / (2.0 * sigmaCold.pow(2.0)))
        } else {
            max(0.70, exp(-(waterTempCelsius - tOpt).pow(2.0) / (2.0 * sigmaWarm.pow(2.0))))
        }

        // We also need fPhase and fDist for hourly mapping
        // Cosine squared model: peaks at New Moon (age=0/29.53) and Full Moon (age=14.77), troughs at Quarters
        val baseP = 0.10
        val angle = 2.0 * Math.PI * moonAge / 29.53059
        val fPhase = baseP + (1.0 - baseP) * cos(angle).pow(2.0)

        val intervals = mutableListOf<HourlyInterval>()
        for (hour in 0 until 24) {
            val intervalStart = Calendar.getInstance().apply {
                time = startOfDay
                add(Calendar.HOUR_OF_DAY, hour)
            }.time
            val intervalEnd = Calendar.getInstance().apply {
                time = startOfDay
                add(Calendar.HOUR_OF_DAY, hour + 1)
            }.time

            var hourScore = 0.5 // baseline activity
            var isMajor = false
            var isMinor = false
            var isEnhanced = false

            // Check matching periods
            for (period in periods) {
                val overlapStart = max(intervalStart.time, period.startTime.time)
                val overlapEnd = min(intervalEnd.time, period.endTime.time)

                if (overlapStart < overlapEnd) {
                    val overlapDuration = (overlapEnd - overlapStart) / 3600000.0
                    val bonus = if (period.type == SolunarType.MAGGIOR) 1.5 else 1.0
                    hourScore += bonus * overlapDuration

                    if (period.type == SolunarType.MAGGIOR) isMajor = true
                    if (period.type == SolunarType.MINOR) isMinor = true
                    if (period.isEnhanced) {
                        isEnhanced = true
                        hourScore += 0.5
                    }
                }
            }

            val midHourDate = Date(intervalStart.time + 1800000)
            val tidalFactor = calculateTidalActivityFactor(midHourDate, tides, location.coordinate, maxAmplitude)
            hourScore *= tidalFactor
            hourScore *= weatherMult
            hourScore *= fWaterTemp
            hourScore = min(hourScore, 3.2) // Cap score

            intervals.add(
                HourlyInterval(
                    hour = hour,
                    startTime = intervalStart,
                    endTime = intervalEnd,
                    activity = classifyScore(hourScore),
                    score = hourScore,
                    isMajorPeriod = isMajor,
                    isMinorPeriod = isMinor,
                    isEnhanced = isEnhanced
                )
            )
        }

        // 5. Calculate Daily Activity Rating
        val coeff = TideEngine.calculateTideCoefficient(date, location.coordinate)
        val enhancedCount = periods.count { it.isEnhanced }

        val ast = AstronomyEngine.calculateAstronomy(date, location.coordinate)
        val moonDistance = ast.moonDistance

        // Relative inverse-cube gravitational tidal force
        val fDist = (384400.0 / moonDistance).pow(3.0)

        // Tide range factor
        val baseC = 0.30
        val fCoeff = baseC + (1.0 - baseC) * (coeff - 20.0) / 100.0

        // Solunar overlap factor
        val wO = 0.60
        val fOverlap = 1.0 + wO * enhancedCount

        // Combine multiplicatively and apply modulations
        var score = fPhase * fDist * fCoeff * fOverlap
        score *= weather.multiplier()
        score *= fWaterTemp
        score = min(score, 1.8) // Cap daily score

        val dailyLevel = when {
            score < 0.45 -> ActivityLevel.BASSA
            score < 0.90 -> ActivityLevel.MODERATA
            score < 1.26 -> ActivityLevel.BUONA
            score < 1.62 -> ActivityLevel.ALTA
            else -> ActivityLevel.MOLTO_ALTA
        }

        // 6. Get Moon illumination and phase name via shredzone library
        val zoneId = ZoneId.systemDefault()
        val zdt = ZonedDateTime.ofInstant(date.toInstant(), zoneId)
        val illuminationObj = MoonIllumination.compute().on(zdt).execute()
        val moonIllumination = illuminationObj.fraction * 100.0
        val moonPhaseName = getMoonPhaseName(illuminationObj.phase)

        // 7. Calculate Best Windows list
        val bestWindowsList = calculateBestWindows(
            date = date,
            location = location,
            sunrise = sunrise,
            sunset = sunset,
            moonrise = moonrise,
            moonset = moonset,
            moonTransit = moonTransit,
            moonAntiTransit = moonAntiTransit,
            moonAge = moonAge,
            tides = tides,
            weatherMult = weatherMult,
            fWaterTemp = fWaterTemp,
            fPhase = fPhase,
            maxAmplitude = maxAmplitude,
            periods = periods
        )

        return DailyForecast(
            date = date,
            location = location,
            sunrise = sunrise,
            sunset = sunset,
            moonrise = moonrise,
            moonset = moonset,
            moonTransit = moonTransit,
            moonAntiTransit = moonAntiTransit,
            moonPhase = moonPhaseName,
            moonAge = moonAge,
            moonIllumination = moonIllumination,
            tides = tides,
            maxTideAmplitude = maxAmplitude,
            tideCoefficient = coeff,
            solunarPeriods = periods,
            dailyActivity = dailyLevel,
            hourlyIntervals = intervals,
            bestWindows = bestWindowsList,
            rawScore = score,
            moonPhaseFactor = fPhase,
            moonDistanceFactor = fDist,
            tideCoeffFactor = fCoeff,
            solunarOverlapFactor = fOverlap,
            weatherFactorVal = weatherMult,
            waterTempFactor = fWaterTemp
        )
    }

    private fun getMoonPhaseName(phaseAngle: Double): String {
        var deg = phaseAngle
        if (deg < 0.0) {
            deg += 360.0
        }
        return when {
            deg >= 0.0 && deg < 22.5 -> "Luna Nuova"
            deg >= 337.5 && deg <= 360.0 -> "Luna Nuova"
            deg >= 22.5 && deg < 67.5 -> "Luna Crescente (Falce)"
            deg >= 67.5 && deg < 112.5 -> "Primo Quarto"
            deg >= 112.5 && deg < 157.5 -> "Gibbosa Crescente"
            deg >= 157.5 && deg < 202.5 -> "Luna Piena"
            deg >= 202.5 && deg < 247.5 -> "Gibbosa Calante"
            deg >= 247.5 && deg < 292.5 -> "Ultimo Quarto"
            else -> "Luna Calante (Falce)"
        }
    }

    private fun calculateTidalActivityFactor(
        date: Date,
        tides: List<TideEvent>,
        coordinate: Coordinate,
        maxAmplitude: Double
    ): Double {
        var minDiffMinutes = Double.MAX_VALUE
        var nearestEvent: TideEvent? = null

        for (event in tides) {
            val diff = (event.time.time - date.time) / 60000.0
            if (abs(diff) < abs(minDiffMinutes)) {
                minDiffMinutes = diff
                nearestEvent = event
            }
        }

        // 1. Calculate rate of change of tide height
        val dateOneHourAgo = Date(date.time - 3600000)
        val currentLevel = TideEngine.calculateHeight(date, coordinate)
        val previousLevel = TideEngine.calculateHeight(dateOneHourAgo, coordinate)

        val rateOfChange = abs(currentLevel - previousLevel)
        val referenceSpring = TideEngine.referenceSpringAmplitude(coordinate)
        val normalizedRate = rateOfChange / max(referenceSpring, 0.05)

        val velocityFactor = 1.0 + min(normalizedRate * 0.8, 0.4)

        // 2. Transition bonus: in the 90 minutes BEFORE the high/low peak
        var transitionBonus = 0.0
        if (minDiffMinutes > 0 && minDiffMinutes <= 90.0) {
            transitionBonus = 0.2
        }

        // 3. Slack water penalty: if within 30 minutes of low tide
        var slackMultiplier = 1.0
        if (nearestEvent != null && nearestEvent.type == TideType.BASSA && abs(minDiffMinutes) <= 30.0) {
            slackMultiplier = 0.7
        }

        return (velocityFactor + transitionBonus) * slackMultiplier
    }

    private fun calculateBestWindows(
        date: Date,
        location: Location,
        sunrise: Date?,
        sunset: Date?,
        moonrise: Date?,
        moonset: Date?,
        moonTransit: Date?,
        moonAntiTransit: Date?,
        moonAge: Double,
        tides: List<TideEvent>,
        weatherMult: Double,
        fWaterTemp: Double,
        fPhase: Double,
        maxAmplitude: Double,
        periods: List<SolunarPeriod>
    ): List<ActivityWindow> {
        val calendar = Calendar.getInstance().apply {
            time = date
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val startOfDay = calendar.time

        // 1. Generate 15-minute slot scores (96 slots in 24 hours)
        val slots = mutableListOf<SlotScore>()
        for (i in 0 until 96) {
            val offset = i * 15 * 60 * 1000L
            val slotStart = Date(startOfDay.time + offset)
            val slotEnd = Date(slotStart.time + 15 * 60 * 1000)

            var solunarBonus = 0.0
            for (period in periods) {
                val overlapStart = max(slotStart.time, period.startTime.time)
                val overlapEnd = min(slotEnd.time, period.endTime.time)
                if (overlapStart < overlapEnd) {
                    val overlapDuration = (overlapEnd - overlapStart) / 3600000.0
                    val baseBonus = if (period.type == SolunarType.MAGGIOR) 1.5 else 1.0
                    solunarBonus += baseBonus * overlapDuration
                    if (period.isEnhanced) {
                        solunarBonus += 0.5 * (overlapDuration / 1.0)
                    }
                }
            }
            val solunarFactor = 1.0 + (solunarBonus / 0.25) * 0.5

            val midSlotDate = Date(slotStart.time + 450000L)
            val tideFactor = calculateTidalActivityFactor(midSlotDate, tides, location.coordinate, maxAmplitude)

            val baseScore = 0.5
            var slotScore = baseScore * solunarFactor * tideFactor * weatherMult * fWaterTemp * fPhase
            slotScore = min(slotScore, 3.2)

            val breakdown = ScoreBreakdown(
                tide = tideFactor,
                solunar = solunarFactor,
                weather = weatherMult,
                waterTemp = fWaterTemp,
                lunarPhase = fPhase
            )
            slots.add(SlotScore(midSlotDate, slotScore, breakdown))
        }

        // 2. Smooth scores using 3-slot moving average
        val rawScores = slots.map { it.score }
        val smoothedScores = rawScores.toMutableList()
        if (rawScores.size > 2) {
            for (i in 1 until rawScores.size - 1) {
                smoothedScores[i] = (rawScores[i - 1] + rawScores[i] + rawScores[i + 1]) / 3.0
            }
        }

        val smoothedSlots = mutableListOf<SlotScore>()
        for (i in slots.indices) {
            smoothedSlots.add(SlotScore(slots[i].date, smoothedScores[i], slots[i].breakdown))
        }

        // 3. Find local peaks
        val peakIndices = mutableListOf<Int>()
        if (smoothedSlots.size > 2) {
            for (i in 1 until smoothedSlots.size - 1) {
                val prev = smoothedSlots[i - 1].score
                val curr = smoothedSlots[i].score
                val next = smoothedSlots[i + 1].score
                if (curr > prev && curr > next) {
                    peakIndices.add(i)
                }
            }
        }

        // 4. Rank peaks
        val rankedIndices = peakIndices.sortedByDescending { smoothedSlots[it].score }

        val windows = mutableListOf<ActivityWindow>()

        // 5. Expand peaks to windows
        for (idx in rankedIndices) {
            val peakScore = smoothedSlots[idx].score
            val threshold = peakScore * 0.85

            var start = idx
            var end = idx
            while (start > 0 && smoothedSlots[start - 1].score >= threshold) {
                start--
            }
            while (end < smoothedSlots.size - 1 && smoothedSlots[end + 1].score >= threshold) {
                end++
            }

            val startDate = Date(smoothedSlots[start].date.time - 450000L) // Align to boundary
            val endDate = Date(smoothedSlots[end].date.time + 450000L)

            // At least 45 minutes
            if (endDate.time - startDate.time < 45 * 60 * 1000) continue

            val label = classifyScore(peakScore)
            val efficacy = min(100, ((peakScore / 3.2) * 100.0).roundToInt())
            val reasons = topReasons(smoothedSlots[idx].breakdown)

            val candidate = ActivityWindow(
                start = startDate,
                end = endDate,
                peak = smoothedSlots[idx].date,
                peakScore = peakScore,
                label = label,
                efficacyPercent = efficacy,
                reasons = reasons
            )

            // Enforce peak separation of at least 90 minutes (5400000 ms)
            if (windows.all { abs(it.peak.time - candidate.peak.time) > 5400000 }) {
                windows.add(candidate)
            }
        }

        // 6. Merge close windows
        val mergedWindows = mergeOverlappingOrCloseWindows(windows)

        // 7. Limit to top 3 and sort chronologically
        val finalWindows = mergedWindows.sortedByDescending { it.efficacyPercent }.take(3)
        return finalWindows.sortedBy { it.start }
    }

    private fun classifyScore(score: Double): ActivityLevel {
        return when {
            score < 0.6 -> ActivityLevel.BASSA
            score < 1.2 -> ActivityLevel.MODERATA
            score < 1.8 -> ActivityLevel.BUONA
            score < 2.5 -> ActivityLevel.ALTA
            else -> ActivityLevel.MOLTO_ALTA
        }
    }

    private fun cleanupReasons(reasons: List<String>): List<String> {
        val unique = reasons.toSet().toMutableList()

        if (unique.contains("corrente marea favorevole") && unique.contains("flusso marea attivo")) {
            unique.remove("flusso marea attivo")
        }

        val rank = { r: String ->
            when (r) {
                "temperatura acqua penalizzante" -> 0
                "corrente marea favorevole" -> 1
                "periodo solunare attivo" -> 2
                "fase lunare ottimale" -> 3
                "meteo costiero favorevole" -> 4
                "flusso marea attivo" -> 5
                "temperatura acqua favorevole" -> 6
                "fase lunare debole" -> 7
                else -> 10
            }
        }

        return unique.sortedBy { rank(it) }.take(3)
    }

    private fun topReasons(breakdown: ScoreBreakdown): List<String> {
        val reasons = mutableListOf<String>()
        if (breakdown.tide > 1.25) {
            reasons.add("corrente marea favorevole")
        } else if (breakdown.tide > 1.05) {
            reasons.add("flusso marea attivo")
        }
        if (breakdown.solunar > 1.20) {
            reasons.add("periodo solunare attivo")
        }
        if (breakdown.weather > 1.10) {
            reasons.add("meteo costiero favorevole")
        }
        if (breakdown.waterTemp < 0.90) {
            reasons.add("temperatura acqua penalizzante")
        } else if (breakdown.waterTemp > 1.05) {
            reasons.add("temperatura acqua favorevole")
        }
        if (breakdown.lunarPhase > 0.80) {
            reasons.add("fase lunare ottimale")
        } else if (breakdown.lunarPhase < 0.30) {
            reasons.add("fase lunare debole")
        }
        if (reasons.isEmpty()) {
            reasons.add("condizioni stabili")
        }
        return cleanupReasons(reasons)
    }

    private fun mergeOverlappingOrCloseWindows(windows: List<ActivityWindow>): List<ActivityWindow> {
        if (windows.size <= 1) return windows
        val sorted = windows.sortedBy { it.start }
        val merged = mutableListOf<ActivityWindow>()
        var current = sorted[0]

        for (i in 1 until sorted.size) {
            val next = sorted[i]
            val gap = next.start.time - current.end.time
            // Merge if gap is less than 30 minutes
            if (gap < 30 * 60 * 1000) {
                val peakDate = if (current.peakScore >= next.peakScore) current.peak else next.peak
                val peakScore = max(current.peakScore, next.peakScore)
                val label = if (current.peakScore >= next.peakScore) current.label else next.label
                val efficacy = if (current.peakScore >= next.peakScore) current.efficacyPercent else next.efficacyPercent
                val combinedReasons = current.reasons + next.reasons
                current = ActivityWindow(
                    start = current.start,
                    end = if (current.end.time >= next.end.time) current.end else next.end,
                    peak = peakDate,
                    peakScore = peakScore,
                    label = label,
                    efficacyPercent = efficacy,
                    reasons = cleanupReasons(combinedReasons)
                )
            } else {
                merged.add(current)
                current = next
            }
        }
        merged.add(current)
        return merged
    }
}

data class ScoreBreakdown(
    val tide: Double,
    val solunar: Double,
    val weather: Double,
    val waterTemp: Double,
    val lunarPhase: Double
)

data class SlotScore(
    val date: Date,
    val score: Double,
    val breakdown: ScoreBreakdown
)
