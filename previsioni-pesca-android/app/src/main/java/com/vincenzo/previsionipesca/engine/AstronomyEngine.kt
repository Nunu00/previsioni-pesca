package com.vincenzo.previsionipesca.engine

import com.vincenzo.previsionipesca.models.Coordinate
import org.shredzone.commons.suncalc.MoonIllumination
import org.shredzone.commons.suncalc.MoonPosition
import org.shredzone.commons.suncalc.MoonTimes
import org.shredzone.commons.suncalc.SunTimes
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Date

data class AstronomyData(
    val sunrise: Date?,
    val sunset: Date?,
    val moonrise: Date?,
    val moonset: Date?,
    val moonTransit: Date?,
    val moonAntiTransit: Date?,
    val moonAge: Double,
    val moonDistance: Double
)

object AstronomyEngine {
    fun calculateAstronomy(date: Date, coordinate: Coordinate): AstronomyData {
        val zoneId = ZoneId.systemDefault()
        // Convert to local mid-day (12:00) to get representative day coordinates
        val cal = Calendar.getInstance().apply {
            time = date
            set(Calendar.HOUR_OF_DAY, 12)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val zdt = ZonedDateTime.ofInstant(cal.time.toInstant(), zoneId)

        // Sun rise and set
        val sunTimes = SunTimes.compute()
            .on(zdt)
            .at(coordinate.latitude, coordinate.longitude)
            .execute()
        val sunrise = sunTimes.rise?.let { Date.from(it.toInstant()) }
        val sunset = sunTimes.set?.let { Date.from(it.toInstant()) }

        // Moon rise and set
        val moonTimes = MoonTimes.compute()
            .on(zdt)
            .at(coordinate.latitude, coordinate.longitude)
            .execute()
        val moonrise = moonTimes.rise?.let { Date.from(it.toInstant()) }
        val moonset = moonTimes.set?.let { Date.from(it.toInstant()) }

        // Exact Moon Transit and Anti-Transit (Nadir) using altitude search
        val moonTransit = findMoonTransit(zdt, coordinate.latitude, coordinate.longitude)
        val moonAntiTransit = findMoonAntiTransit(zdt, coordinate.latitude, coordinate.longitude)

        // Moon Age: shredzone MoonIllumination getPhase() range [-180, 180] (where 0 is new moon, 180 is full moon)
        val illumination = MoonIllumination.compute()
            .on(zdt)
            .execute()
        var phaseDeg = illumination.phase
        if (phaseDeg < 0.0) {
            phaseDeg += 360.0
        }
        val moonAge = (phaseDeg / 360.0) * 29.53059

        // Moon Distance in kilometers
        val moonPos = MoonPosition.compute()
            .on(zdt)
            .at(coordinate.latitude, coordinate.longitude)
            .execute()
        val moonDistance = moonPos.distance

        return AstronomyData(
            sunrise = sunrise,
            sunset = sunset,
            moonrise = moonrise,
            moonset = moonset,
            moonTransit = moonTransit,
            moonAntiTransit = moonAntiTransit,
            moonAge = moonAge,
            moonDistance = moonDistance
        )
    }

    private fun findMoonTransit(zdt: ZonedDateTime, latitude: Double, longitude: Double): Date {
        val baseTimeMs = zdt.toLocalDate().atStartOfDay(zdt.zone).toInstant().toEpochMilli()
        var maxAlt = -Double.MAX_VALUE
        var transitTimeMs = baseTimeMs

        // Coarse search every 30 minutes
        for (i in 0..48) {
            val t = baseTimeMs + i * 30 * 60 * 1000L
            val testZdt = ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(t), zdt.zone)
            val alt = MoonPosition.compute()
                .on(testZdt)
                .at(latitude, longitude)
                .execute()
                .altitude
            if (alt > maxAlt) {
                maxAlt = alt
                transitTimeMs = t
            }
        }

        // Fine search around the candidate ±15 minutes (in 1-minute steps)
        var fineTransitTimeMs = transitTimeMs
        maxAlt = -Double.MAX_VALUE
        for (m in -15..15) {
            val t = transitTimeMs + m * 60 * 1000L
            val testZdt = ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(t), zdt.zone)
            val alt = MoonPosition.compute()
                .on(testZdt)
                .at(latitude, longitude)
                .execute()
                .altitude
            if (alt > maxAlt) {
                maxAlt = alt
                fineTransitTimeMs = t
            }
        }

        return Date(fineTransitTimeMs)
    }

    private fun findMoonAntiTransit(zdt: ZonedDateTime, latitude: Double, longitude: Double): Date {
        val baseTimeMs = zdt.toLocalDate().atStartOfDay(zdt.zone).toInstant().toEpochMilli()
        var minAlt = Double.MAX_VALUE
        var antiTransitTimeMs = baseTimeMs

        // Coarse search every 30 minutes
        for (i in 0..48) {
            val t = baseTimeMs + i * 30 * 60 * 1000L
            val testZdt = ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(t), zdt.zone)
            val alt = MoonPosition.compute()
                .on(testZdt)
                .at(latitude, longitude)
                .execute()
                .altitude
            if (alt < minAlt) {
                minAlt = alt
                antiTransitTimeMs = t
            }
        }

        // Fine search around the candidate ±15 minutes (in 1-minute steps)
        var fineAntiTransitTimeMs = antiTransitTimeMs
        minAlt = Double.MAX_VALUE
        for (m in -15..15) {
            val t = antiTransitTimeMs + m * 60 * 1000L
            val testZdt = ZonedDateTime.ofInstant(java.time.Instant.ofEpochMilli(t), zdt.zone)
            val alt = MoonPosition.compute()
                .on(testZdt)
                .at(latitude, longitude)
                .execute()
                .altitude
            if (alt < minAlt) {
                minAlt = alt
                fineAntiTransitTimeMs = t
            }
        }

        return Date(fineAntiTransitTimeMs)
    }
}
