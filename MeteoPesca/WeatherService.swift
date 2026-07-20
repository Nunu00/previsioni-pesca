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
    
    public static func fetch7DayWeather(latitude: Double, longitude: Double) async throws -> [String: FetchedWeatherData] {
        // 1. Fetch Forecast Data (Atmospheric Conditions for 7 days)
        let forecastUrlString = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)&hourly=cloud_cover,wind_direction_10m,temperature_2m,wind_speed_10m&wind_speed_unit=ms&forecast_days=7"
        guard let forecastUrl = URL(string: forecastUrlString) else {
            throw URLError(.badURL)
        }
        
        let (forecastData, _) = try await URLSession.shared.data(from: forecastUrl)
        let forecastJSON = try JSONSerialization.jsonObject(with: forecastData) as? [String: Any]
        
        let hourly = forecastJSON?["hourly"] as? [String: Any]
        let hourlyTime = hourly?["time"] as? [String] ?? []
        let hourlyCloud = hourly?["cloud_cover"] as? [Double] ?? []
        let hourlyWind = hourly?["wind_direction_10m"] as? [Double] ?? []
        let hourlyAir = hourly?["temperature_2m"] as? [Double] ?? []
        let hourlyWindSpeed = hourly?["wind_speed_10m"] as? [Double] ?? []
        
        // 2. Fetch Marine Data (Native Sea Surface Temperature & Swell Height for 7 days)
        let marineUrlString = "https://marine-api.open-meteo.com/v1/marine?latitude=\(latitude)&longitude=\(longitude)&hourly=sea_surface_temperature,wave_height&forecast_days=7"
        var hourlySst: [Double] = []
        var hourlyWave: [Double] = []
        
        if let marineUrl = URL(string: marineUrlString) {
            do {
                let (marineData, _) = try await URLSession.shared.data(from: marineUrl)
                if let marineJSON = try JSONSerialization.jsonObject(with: marineData) as? [String: Any],
                   let hourlyMarine = marineJSON["hourly"] as? [String: Any] {
                    hourlySst = hourlyMarine["sea_surface_temperature"] as? [Double] ?? []
                    hourlyWave = hourlyMarine["wave_height"] as? [Double] ?? []
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
            
            // Slice hourly values
            let cloudSlice = hourlyCloud.count > endIndex ? Array(hourlyCloud[startIndex..<endIndex]) : []
            let windSlice = hourlyWind.count > endIndex ? Array(hourlyWind[startIndex..<endIndex]) : []
            let airSlice = hourlyAir.count > endIndex ? Array(hourlyAir[startIndex..<endIndex]) : []
            let sstSlice = hourlySst.count > endIndex ? Array(hourlySst[startIndex..<endIndex]) : []
            let waveSlice = hourlyWave.count > endIndex ? Array(hourlyWave[startIndex..<endIndex]) : []
            let windSpeedSlice = hourlyWindSpeed.count > endIndex ? Array(hourlyWindSpeed[startIndex..<endIndex]) : []
            
            // Calculate averages / representatives
            let avgCloud = cloudSlice.isEmpty ? 20.0 : cloudSlice.reduce(0.0, +) / Double(cloudSlice.count)
            
            // Wind direction change over last 3 hours of mid-day
            var windChange = 10.0
            if windSlice.count > 12 {
                let change = abs(windSlice[12] - windSlice[9])
                windChange = change > 180.0 ? 360.0 - change : change
            }
            
            let tempDelta = airSlice.count >= 24 ? airSlice[23] - airSlice[0] : 0.0
            let avgSst = sstSlice.isEmpty ? 20.0 : sstSlice.reduce(0.0, +) / Double(sstSlice.count)
            let maxWave = waveSlice.isEmpty ? 0.2 : waveSlice.reduce(0.0, max)
            let avgWind = windSpeedSlice.isEmpty ? 4.0 : windSpeedSlice.reduce(0.0, +) / Double(windSpeedSlice.count)
            
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
