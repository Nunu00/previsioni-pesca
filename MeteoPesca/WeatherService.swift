import Foundation

public struct FetchedWeatherData {
    public let waterTemp: Double
    public let cloudCover: Double
    public let windDirectionChange: Double
    public let swellHeight: Double
    public let surfaceTempDelta24h: Double
    public let windSpeedMps: Double
}

public class WeatherService {
    
    private static func parseDoubleArray(_ raw: Any?) -> [Double?] {
        guard let array = raw as? [Any] else { return [] }
        return array.map { item in
            if let num = item as? NSNumber {
                return num.doubleValue
            }
            return nil
        }
    }
    
    public static func fetch7DayWeather(latitude: Double, longitude: Double) async throws -> [String: FetchedWeatherData] {
        // 1. Fetch Forecast Data (Atmospheric Conditions for 7 days)
        let forecastUrlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&hourly=cloud_cover,wind_direction_10m,temperature_2m,wind_speed_10m&wind_speed_unit=ms&forecast_days=7&timezone=auto"
        guard let forecastUrl = URL(string: forecastUrlString) else {
            throw URLError(.badURL)
        }
        
        let (forecastData, _) = try await URLSession.shared.data(from: forecastUrl)
        let forecastJSON = try JSONSerialization.jsonObject(with: forecastData) as? [String: Any]
        
        let hourly = forecastJSON?["hourly"] as? [String: Any]
        let hourlyTime = hourly?["time"] as? [String] ?? []
        let hourlyCloud = parseDoubleArray(hourly?["cloud_cover"])
        let hourlyWind = parseDoubleArray(hourly?["wind_direction_10m"])
        let hourlyAir = parseDoubleArray(hourly?["temperature_2m"])
        let hourlyWindSpeed = parseDoubleArray(hourly?["wind_speed_10m"])
        
        // 2. Fetch Marine Data (Native Sea Surface Temperature & Swell Height for 7 days)
        let marineUrlString = "https://marine-api.open-meteo.com/v1/marine?latitude=\(latitude)&longitude=\(longitude)&hourly=sea_surface_temperature,wave_height&forecast_days=7&timezone=auto"
        var hourlySst: [Double?] = []
        var hourlyWave: [Double?] = []
        
        if let marineUrl = URL(string: marineUrlString) {
            do {
                let (marineData, _) = try await URLSession.shared.data(from: marineUrl)
                if let marineJSON = try JSONSerialization.jsonObject(with: marineData) as? [String: Any],
                   let hourlyMarine = marineJSON["hourly"] as? [String: Any] {
                    hourlySst = parseDoubleArray(hourlyMarine["sea_surface_temperature"])
                    hourlyWave = parseDoubleArray(hourlyMarine["wave_height"])
                }
            } catch {
                print("Marine API fetch failed or coordinates inland: \(error)")
            }
        }
        
        var result: [String: FetchedWeatherData] = [:]
        
        // Group by day (0 to 6)
        for day in 0..<7 {
            let startIndex = day * 24
            let endIndex = (day + 1) * 24
            
            guard hourlyTime.count > startIndex else { continue }
            
            // Get date string (first 10 chars of ISO string: "yyyy-MM-dd")
            let dateStr = String(hourlyTime[startIndex].prefix(10))
            
            // Slice hourly values and filter non-nil
            let cloudSlice = (hourlyCloud.count >= endIndex ? Array(hourlyCloud[startIndex..<endIndex]) : Array(hourlyCloud.dropFirst(startIndex))).compactMap { $0 }
            let windSlice = (hourlyWind.count >= endIndex ? Array(hourlyWind[startIndex..<endIndex]) : Array(hourlyWind.dropFirst(startIndex))).compactMap { $0 }
            let airSlice = (hourlyAir.count >= endIndex ? Array(hourlyAir[startIndex..<endIndex]) : Array(hourlyAir.dropFirst(startIndex))).compactMap { $0 }
            let sstSlice = (hourlySst.count >= endIndex ? Array(hourlySst[startIndex..<endIndex]) : Array(hourlySst.dropFirst(startIndex))).compactMap { $0 }
            let waveSlice = (hourlyWave.count >= endIndex ? Array(hourlyWave[startIndex..<endIndex]) : Array(hourlyWave.dropFirst(startIndex))).compactMap { $0 }
            let windSpeedSlice = (hourlyWindSpeed.count >= endIndex ? Array(hourlyWindSpeed[startIndex..<endIndex]) : Array(hourlyWindSpeed.dropFirst(startIndex))).compactMap { $0 }
            
            // Calculate averages / representatives
            let avgCloud = cloudSlice.isEmpty ? 20.0 : cloudSlice.reduce(0.0, +) / Double(cloudSlice.count)
            let avgWind = windSpeedSlice.isEmpty ? 4.0 : windSpeedSlice.reduce(0.0, +) / Double(windSpeedSlice.count)
            
            // Max wind direction change over any 3-hour window during the day
            var windChange = 10.0
            if windSlice.count >= 4 {
                var maxDiff = 0.0
                for i in 3..<windSlice.count {
                    let diff = abs(windSlice[i] - windSlice[i - 3])
                    let shortestDiff = diff > 180.0 ? 360.0 - diff : diff
                    if shortestDiff > maxDiff {
                        maxDiff = shortestDiff
                    }
                }
                windChange = maxDiff
            }
            
            let tempDelta = airSlice.count >= 2 ? airSlice[airSlice.count - 1] - airSlice[0] : 0.0
            let avgSst = sstSlice.isEmpty ? 20.0 : sstSlice.reduce(0.0, +) / Double(sstSlice.count)
            
            // Max wave height: use marine API data if present, or dynamic estimation based on wind speed
            let maxWave: Double
            if !waveSlice.isEmpty {
                maxWave = waveSlice.reduce(0.0, max)
            } else {
                maxWave = max(0.1, avgWind * 0.08)
            }
            
            result[dateStr] = FetchedWeatherData(
                waterTemp: avgSst,
                cloudCover: avgCloud,
                windDirectionChange: windChange,
                swellHeight: maxWave,
                surfaceTempDelta24h: tempDelta,
                windSpeedMps: avgWind
            )
        }
        
        return result
    }
}
