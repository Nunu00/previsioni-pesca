import SwiftUI

struct ContentView: View {
    @State private var selectedDate: Date = Date()
    @State private var selectedLocation: Location = TideEngine.stations[0]
    @State private var customLatitude: String = "39.73"
    @State private var customLongitude: String = "16.48"
    @State private var isShowingCustomCoordinates: Bool = false
    @State private var savedLocations: [Location] = TideEngine.stations
    @State private var forecast: DailyForecast?
    
    // Environmental conditions state variables
    @State private var cloudCover: Double = 20.0
    @State private var windDirectionChange: Double = 10.0
    @State private var swellHeight: Double = 0.2
    @State private var surfaceTempDelta24h: Double = 0.0
    @State private var waterTempCelsius: Double = 20.0
    @State private var isFetchingWeather: Bool = false
    @State private var weatherErrorMessage: String? = nil
    @State private var weatherCache: [String: FetchedWeatherData] = [:]
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateStyle = .full
        return formatter
    }
    
    private var hourFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "HH:mm"
        return formatter
    }
    
    private var calendarDays: [Date] {
        let calendar = Calendar.current
        guard let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) else { return [] }
        let range = calendar.range(of: .day, in: .month, for: startOfMonth)!
        
        var days: [Date] = []
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(date)
            }
        }
        return days
    }
    
    private func activityForDate(_ date: Date) -> ActivityLevel {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let coord = selectedLocation.coordinate
        
        let astro = AstronomyEngine.calculateAstronomy(date: startOfDay, coordinate: coord)
        let tides = TideEngine.calculateDailyTides(date: startOfDay, coordinate: coord)
        
        let dateKey = cacheKeyFormatter.string(from: startOfDay)
        var sst = 20.0
        var cloud = 20.0
        var wind = 0.0
        var swell = 0.2
        var delta = 0.0
        
        if let cached = weatherCache[dateKey] {
            cloud = cached.cloudCover
            wind = cached.windDirectionChange
            swell = cached.swellHeight
            delta = cached.surfaceTempDelta24h
            sst = cached.waterTemp
        } else {
            let today = Date()
            let daysDifference = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: startOfDay).day ?? 0
            let seasonalWaterTemp = climatologicalMean(for: startOfDay)
            
            if daysDifference < -1 {
                sst = seasonalWaterTemp
            } else {
                // SST Anomaly Persistence Forecast (exponential decay with decorrelationTime = 15 days)
                let todayKey = cacheKeyFormatter.string(from: today)
                let currentSst = weatherCache[todayKey]?.waterTemp ?? 20.0
                
                // Anomaly evaluated at Day 7 (end of forecast window) to guarantee continuity
                let day7Date = calendar.date(byAdding: .day, value: 7, to: today) ?? today
                let day7Key = cacheKeyFormatter.string(from: day7Date)
                let day7SST = weatherCache[day7Key]?.waterTemp ?? currentSst
                let day7Climatology = climatologicalMean(for: day7Date)
                let anomalyAtDay7 = day7SST - day7Climatology
                
                let daysAhead = Double(daysDifference - 7)
                let tau = decorrelationTime(for: startOfDay)
                let decayFactor = exp(-daysAhead / tau)
                sst = seasonalWaterTemp + anomalyAtDay7 * decayFactor
            }
        }
        
        let weatherFactor = WeatherFactor(
            cloudCoverPercent: cloud,
            windDirectionChange: wind,
            swellHeight: swell,
            surfaceTempDelta24h: delta
        )
        
        let forecastResult = RulesEngine.evaluateForecast(
            date: startOfDay,
            location: selectedLocation,
            sunrise: astro.sunrise,
            sunset: astro.sunset,
            moonrise: astro.moonrise,
            moonset: astro.moonset,
            moonTransit: astro.moonTransit,
            moonAntiTransit: astro.moonAntiTransit,
            moonAge: astro.moonAge,
            tides: tides,
            weather: weatherFactor,
            waterTempCelsius: sst
        )
        
        return forecastResult.dailyActivity
    }
    
    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date).capitalized
    }
    
    private func changeMonth(by value: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: value, to: selectedDate) {
            selectedDate = newDate
            calculateForecast()
            updateWeatherAutomatically()
        }
    }
    
    private var cacheKeyFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
    
    private func climatologicalMean(for date: Date) -> Double {
        let calendar = Calendar.current
        let dayOfYear = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 180)
        let angle = (dayOfYear - 230.0) / 365.0 * 2.0 * Double.pi
        let meanSst = 19.5 + 6.5 * cos(angle)
        return meanSst
    }
    
    private func decorrelationTime(for date: Date) -> Double {
        let month = Calendar.current.component(.month, from: date)
        switch month {
        case 6...9: return 20.0   // estate: forte stratificazione, persistenza lunga
        case 10...11, 3...5: return 12.0  // transizione: mixing moderato
        default: return 8.0       // inverno: mixing intenso, decorrelazione rapida
        }
    }
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    
    var body: some View {
        NavigationView {
            ZStack {
                // Deep sea premium dark gradient background
                LinearGradient(
                    gradient: Gradient(colors: [Color(red: 7/255, green: 15/255, blue: 30/255), Color(red: 20/255, green: 38/255, blue: 67/255)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        
                        // 1. Selector Section
                        VStack(spacing: 12) {
                            HStack {
                                Text("Località")
                                    .foregroundColor(.white.opacity(0.8))
                                Spacer()
                                Picker("Località", selection: $selectedLocation) {
                                    ForEach(savedLocations) { loc in
                                        Text(loc.name).tag(loc)
                                    }
                                }
                                .pickerStyle(.menu)
                                .onChange(of: selectedLocation) { newLoc in
                                    customLatitude = String(format: "%.4f", newLoc.coordinate.latitude)
                                    customLongitude = String(format: "%.4f", newLoc.coordinate.longitude)
                                    self.weatherCache = [:]
                                    calculateForecast()
                                    updateWeatherAutomatically()
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(12)
                            
                            Toggle(isOn: $isShowingCustomCoordinates) {
                                Text("Coordinate Personalizzate")
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            
                            if isShowingCustomCoordinates {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Latitudine").font(.caption).foregroundColor(.white.opacity(0.6))
                                        TextField("es. 39.73", text: $customLatitude)
                                            .keyboardType(.decimalPad)
                                            .padding(10)
                                            .background(Color.white.opacity(0.1))
                                            .cornerRadius(8)
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Longitudine").font(.caption).foregroundColor(.white.opacity(0.6))
                                        TextField("es. 16.48", text: $customLongitude)
                                            .keyboardType(.decimalPad)
                                            .padding(10)
                                            .background(Color.white.opacity(0.1))
                                            .cornerRadius(8)
                                            .foregroundColor(.white)
                                    }
                                    
                                    Button(action: applyCustomCoordinates) {
                                        Text("Applica")
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                            .background(Color.teal)
                                            .foregroundColor(.black)
                                            .cornerRadius(8)
                                    }
                                    .padding(.top, 20)
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .padding(.horizontal)
                        
                        // 1a. Monthly Efficacy Calendar Card
                        efficacyCalendarCard
                        
                        if let forecast = forecast {
                            
                            // 2. Main Fishing Score Badge
                            VStack(spacing: 8) {
                                Text("ATTIVITÀ DEL GIORNO")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.6))
                                    .tracking(2)
                                
                                Text(forecast.dailyActivity.description)
                                    .font(.title2)
                                    .fontWeight(.black)
                                    .foregroundColor(colorForActivity(forecast.dailyActivity))
                                    .shadow(color: colorForActivity(forecast.dailyActivity).opacity(0.5), radius: 8)
                                
                                HStack(spacing: 8) {
                                    ForEach(0..<4) { idx in
                                        Image(systemName: "fish.fill")
                                            .font(.title2)
                                            .foregroundColor(idx < forecast.dailyActivity.score ? colorForActivity(forecast.dailyActivity) : Color.white.opacity(0.2))
                                    }
                                }
                                .padding(.top, 4)
                                
                                Text("Indice di Efficacia: \(Int(round((forecast.rawScore / 1.8) * 100.0)))%")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(colorForActivity(forecast.dailyActivity))
                                    .padding(.top, 2)
                                
                                Text("Escursione max marea: \(String(format: "%.2f", forecast.maxTideAmplitude)) m")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(colorForActivity(forecast.dailyActivity).opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            
                            // 3. Tide curve SVG/Canvas
                            TideChartView(forecast: forecast)
                                .frame(height: 160)
                                .padding()
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            
                            // 4. Astro Times Details
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Astronomia e Fase Lunare")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 16) {
                                    VStack(alignment: .center, spacing: 12) {
                                        Text(forecast.moonPhase)
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.yellow)
                                        
                                        // Simple SVG representing Moon Phase based on age
                                        MoonPhaseView(age: forecast.moonAge)
                                            .frame(width: 50, height: 50)
                                            
                                        Text("\(Int(forecast.moonIllumination))% Illuminata")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(width: 120)
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "sunrise.fill").foregroundColor(.orange)
                                            Text("Alba Sole: \(timeString(forecast.sunrise))").font(.caption)
                                        }
                                        HStack {
                                            Image(systemName: "sunset.fill").foregroundColor(.orange)
                                            Text("Tramonto Sole: \(timeString(forecast.sunset))").font(.caption)
                                        }
                                        HStack {
                                            Image(systemName: "moonphase.waxing.crescent").foregroundColor(.yellow)
                                            Text("Alba Luna: \(timeString(forecast.moonrise))").font(.caption)
                                        }
                                        HStack {
                                            Image(systemName: "moonphase.waning.crescent").foregroundColor(.yellow)
                                            Text("Tramonto Luna: \(timeString(forecast.moonset))").font(.caption)
                                        }
                                        HStack {
                                            Image(systemName: "scope").foregroundColor(.cyan)
                                            Text("Transito Luna: \(timeString(forecast.moonTransit))").font(.caption)
                                        }
                                    }
                                    .foregroundColor(.white)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(16)
                            .padding(.horizontal)
                            
                            // 5. Solunar Periods Section
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Periodi Solunari del Giorno")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                ForEach(forecast.solunarPeriods) { period in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(period.type.rawValue)
                                                    .font(.caption)
                                                    .fontWeight(.bold)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(period.type == .maggior ? Color.amberBadge : Color.cyanBadge)
                                                    .foregroundColor(.black)
                                                    .cornerRadius(4)
                                                
                                                if period.isEnhanced {
                                                    Text("PICCO POTENZIATO 🔥")
                                                        .font(.caption)
                                                        .fontWeight(.bold)
                                                        .padding(.horizontal, 8)
                                                        .padding(.vertical, 4)
                                                        .background(Color.red)
                                                        .foregroundColor(.white)
                                                        .cornerRadius(4)
                                                }
                                            }
                                            
                                            Text(period.description)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                            
                                            Text("Orario: \(hourFormatter.string(from: period.startTime)) - \(hourFormatter.string(from: period.endTime))")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        Spacer()
                                        
                                        Image(systemName: period.type == .maggior ? "bolt.fill" : "bolt")
                                            .foregroundColor(period.isEnhanced ? .red : (period.type == .maggior ? .orange : .cyan))
                                            .font(.title2)
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(16)
                            .padding(.horizontal)
                            
                            // 6. Environmental Conditions Card (Meteo & Parametri Costieri)
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Meteo & Parametri Costieri")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    if isFetchingWeather {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .teal))
                                    } else {
                                        Button(action: updateWeatherAutomatically) {
                                            Image(systemName: "arrow.clockwise")
                                                .foregroundColor(.teal)
                                                .font(.subheadline)
                                        }
                                    }
                                }
                                
                                if let errorMsg = weatherErrorMessage {
                                    Text(errorMsg)
                                        .font(.caption2)
                                        .foregroundColor(errorMsg.contains("offline") ? .red : .orange)
                                }
                                
                                VStack(spacing: 12) {
                                    // Water Temp
                                    HStack {
                                        Image(systemName: "thermometer.medium")
                                            .foregroundColor(.teal)
                                            .frame(width: 20)
                                        Text("Temp. Acqua")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(Int(waterTempCelsius))°C")
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(.teal)
                                            Text(waterTempCelsius < 15 ? "Metabolismo ridotto (freddo)" : (waterTempCelsius > 25 ? "Letargici (caldo)" : "Condizione ottimale (Q10)"))
                                                .font(.system(size: 9))
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.1))
                                    
                                    // Cloud Cover
                                    HStack {
                                        Image(systemName: "cloud.fill")
                                            .foregroundColor(.cyan)
                                            .frame(width: 20)
                                        Text("Nuvolosità")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("\(Int(cloudCover))%")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.cyan)
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.1))
                                    
                                    // Wind Change
                                    HStack {
                                        Image(systemName: "wind")
                                            .foregroundColor(.orange)
                                            .frame(width: 20)
                                        Text("Variazione Direzione Vento")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text("\(Int(windDirectionChange))°")
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.1))
                                    
                                    // Swell Height
                                    HStack {
                                        Image(systemName: "water.waves")
                                            .foregroundColor(.blue)
                                            .frame(width: 20)
                                        Text("Altezza Onda (Swell)")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text(String(format: "%.1f m", swellHeight))
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.1))
                                    
                                    // Surface Temp Delta
                                    HStack {
                                        Image(systemName: "thermometer.snowflake")
                                            .foregroundColor(surfaceTempDelta24h < -1.5 ? .green : .white)
                                            .frame(width: 20)
                                        Text("Variazione Temp. Superficiale (24h)")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                        Spacer()
                                        Text(String(format: "%+.1f°C", surfaceTempDelta24h))
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(surfaceTempDelta24h < -1.5 ? .green : .white)
                                    }
                                    
                                    Divider().background(Color.white.opacity(0.1))
                                    
                                    Text("* Rilevamenti costieri e satellitari aggiornati via Open-Meteo.")
                                        .font(.caption2)
                                        .italic()
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding()
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(12)
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.horizontal)
                            
                            // 7. Detailed Factor Breakdown Section
                            let sumFactors = forecast.moonPhaseFactor + forecast.moonDistanceFactor + forecast.tideCoeffFactor + forecast.solunarOverlapFactor + forecast.weatherFactorVal + forecast.waterTempFactor
                            let normMoonPhase = (forecast.moonPhaseFactor / sumFactors) * 100.0
                            let normMoonDist = (forecast.moonDistanceFactor / sumFactors) * 100.0
                            let normTide = (forecast.tideCoeffFactor / sumFactors) * 100.0
                            let normOverlap = (forecast.solunarOverlapFactor / sumFactors) * 100.0
                            let normWeather = (forecast.weatherFactorVal / sumFactors) * 100.0
                            let normWaterTemp = (forecast.waterTempFactor / sumFactors) * 100.0
                            
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Analisi dei Fattori Costieri & Lunari")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white.opacity(0.9))
                                    .tracking(0.5)
                                
                                VStack(spacing: 8) {
                                    FactorRow(name: "Fase Lunare (Novilunio/Plenilunio)", value: String(format: "%.1f%%", normMoonPhase), icon: "moon.stars.fill", color: .yellow)
                                    FactorRow(name: "Gravità Luna (Apogeo/Perigeo)", value: String(format: "%.1f%%", normMoonDist), icon: "scalemass.fill", color: .purple)
                                    FactorRow(name: "Coefficiente di Marea (Ampiezza)", value: String(format: "%.1f%%", normTide), icon: "water.waves", color: .blue)
                                    FactorRow(name: "Allineamenti Solunari (Coincidenze)", value: String(format: "%.1f%%", normOverlap), icon: "sparkles", color: .orange)
                                    FactorRow(name: "Fattori Meteo Compositi", value: String(format: "%.1f%%", normWeather), icon: "cloud.sun.fill", color: .cyan)
                                    FactorRow(name: "Temperatura Acqua (Metabolismo Q10)", value: String(format: "%.1f%%", normWaterTemp), icon: "thermometer.medium", color: .teal)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .padding(.horizontal)
                        }
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("MeteoPesca Forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack {
                        Text("Previsioni Pesca")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(dateFormatter.string(from: selectedDate))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .onAppear {
                calculateForecast()
                updateWeatherAutomatically()
            }
            .onChange(of: selectedDate) { _ in
                calculateForecast()
                updateWeatherAutomatically()
            }
            .onChange(of: cloudCover) { _ in calculateForecast() }
            .onChange(of: windDirectionChange) { _ in calculateForecast() }
            .onChange(of: swellHeight) { _ in calculateForecast() }
            .onChange(of: surfaceTempDelta24h) { _ in calculateForecast() }
            .onChange(of: waterTempCelsius) { _ in calculateForecast() }
        }
        .preferredColorScheme(.dark)
    }
    
    private func applyCustomCoordinates() {
        if let lat = Double(customLatitude), let lon = Double(customLongitude) {
            let customLoc = Location(name: "Coordinate Manuali", latitude: lat, longitude: lon)
            selectedLocation = customLoc
            self.weatherCache = [:]
            calculateForecast()
            updateWeatherAutomatically()
        }
    }
    
    private func calculateForecast() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: selectedDate)
        let coord = selectedLocation.coordinate
        
        // 1. Calculate Sun/Moon ephemerides via SwiftAA
        let astro = AstronomyEngine.calculateAstronomy(date: startOfDay, coordinate: coord)
        
        // 2. Generate tides offline via local harmonic constituent database
        let tides = TideEngine.calculateDailyTides(date: startOfDay, coordinate: coord)
        
        // 3. Evaluate solunar rules and fish activity scoring
        let weatherFactor = WeatherFactor(
            cloudCoverPercent: cloudCover,
            windDirectionChange: windDirectionChange,
            swellHeight: swellHeight,
            surfaceTempDelta24h: surfaceTempDelta24h
        )
        
        let forecastResult = RulesEngine.evaluateForecast(
            date: startOfDay,
            location: selectedLocation,
            sunrise: astro.sunrise,
            sunset: astro.sunset,
            moonrise: astro.moonrise,
            moonset: astro.moonset,
            moonTransit: astro.moonTransit,
            moonAntiTransit: astro.moonAntiTransit,
            moonAge: astro.moonAge,
            tides: tides,
            weather: weatherFactor,
            waterTempCelsius: waterTempCelsius
        )
        
        self.forecast = forecastResult
    }
    
    private func updateWeatherAutomatically() {
        let dateKey = cacheKeyFormatter.string(from: selectedDate)
        if weatherCache[dateKey] != nil || weatherCache.count > 0 {
            // Apply parameters for selected date from cache or blend climatology
            applyWeatherForSelectedDate()
        } else {
            // Fetch 7-day forecast cache
            fetch7DayWeatherCache()
        }
    }
    
    private func fetch7DayWeatherCache() {
        let coord = selectedLocation.coordinate
        isFetchingWeather = true
        weatherErrorMessage = nil
        
        Task {
            do {
                let cache = try await WeatherService.fetch7DayWeather(latitude: coord.latitude, longitude: coord.longitude)
                await MainActor.run {
                    self.weatherCache = cache
                    self.isFetchingWeather = false
                    self.applyWeatherForSelectedDate()
                }
            } catch {
                await MainActor.run {
                    self.weatherErrorMessage = "Meteo offline: impossibile caricare le previsioni."
                    self.isFetchingWeather = false
                    self.applyWeatherForSelectedDate()
                }
            }
        }
    }
    
    private func applyWeatherForSelectedDate() {
        let dateKey = cacheKeyFormatter.string(from: selectedDate)
        
        let calendar = Calendar.current
        let today = Date()
        let startOfToday = calendar.startOfDay(for: today)
        let startOfSelected = calendar.startOfDay(for: selectedDate)
        let daysDifference = calendar.dateComponents([.day], from: startOfToday, to: startOfSelected).day ?? 0
        
        let seasonalWaterTemp = climatologicalMean(for: startOfSelected)
        let todayKey = cacheKeyFormatter.string(from: today)
        let currentSst = weatherCache[todayKey]?.waterTemp ?? 20.0
        
        if let cached = weatherCache[dateKey] {
            // Selected date is within the 7-day forecast!
            self.cloudCover = cached.cloudCover
            self.windDirectionChange = cached.windDirectionChange
            self.swellHeight = cached.swellHeight
            self.surfaceTempDelta24h = cached.surfaceTempDelta24h
            self.waterTempCelsius = cached.waterTemp
            self.weatherErrorMessage = nil
        } else {
            // Distant date (past or future)!
            self.cloudCover = 20.0
            self.windDirectionChange = 0.0
            self.swellHeight = 0.2
            self.surfaceTempDelta24h = 0.0
            
            if daysDifference < -1 {
                // Past date: just use climatological water temp
                self.waterTempCelsius = seasonalWaterTemp
                self.weatherErrorMessage = "* Mostrati parametri medi climatologici storici (data passata)."
            } else {
                // Future date beyond 7 days: Anomaly Persistence Forecast with exponential decay (15 days time scale)
                // Anomaly evaluated at Day 7 to guarantee continuity
                let day7Date = calendar.date(byAdding: .day, value: 7, to: today) ?? today
                let day7Key = cacheKeyFormatter.string(from: day7Date)
                let day7SST = weatherCache[day7Key]?.waterTemp ?? currentSst
                let day7Climatology = climatologicalMean(for: day7Date)
                let anomalyAtDay7 = day7SST - day7Climatology
                
                let daysAhead = Double(daysDifference - 7)
                let tau = decorrelationTime(for: startOfSelected)
                let decayFactor = exp(-daysAhead / tau)
                let projectedSst = seasonalWaterTemp + anomalyAtDay7 * decayFactor
                
                self.waterTempCelsius = projectedSst
                
                let anomalyPercent = Int(round(decayFactor * 100.0))
                if anomalyPercent > 10 {
                    self.weatherErrorMessage = String(format: "* Anomalia termica persistente al %d%% (temperatura prevista: %.1f°C).", anomalyPercent, projectedSst)
                } else {
                    self.weatherErrorMessage = "* Temperatura allineata alla media climatologica storica (data lontana)."
                }
            }
        }
        
        self.calculateForecast()
    }
    
    private func timeString(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        return hourFormatter.string(from: date)
    }
    
    private func colorForActivity(_ level: ActivityLevel) -> Color {
        switch level {
        case .bassa: return .gray
        case .moderata: return .cyan
        case .buona: return .yellow
        case .alta: return .orange
        case .moltoAlta: return .green
        }
    }
    private var efficacyCalendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.teal)
                    .font(.headline)
                Text("Calendario Efficacia")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { changeMonth(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.teal)
                            .fontWeight(.bold)
                            .padding(6)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                    }
                    
                    Text(monthYearString(for: selectedDate))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(minWidth: 95, alignment: .center)
                    
                    Button(action: { changeMonth(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.teal)
                            .fontWeight(.bold)
                            .padding(6)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(6)
                    }
                }
            }
            
            // Days of week header
            HStack(spacing: 0) {
                ForEach(["Lu", "Ma", "Me", "Gi", "Ve", "Sa", "Do"], id: \.self) { day in
                    Text(day)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            
            let days = calendarDays
            let firstDayOfWeek = Calendar.current.component(.weekday, from: days.first ?? Date())
            let leadingEmptySlots = (firstDayOfWeek + 5) % 7
            
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<leadingEmptySlots, id: \.self) { _ in
                    Color.clear
                        .frame(height: 32)
                }
                
                ForEach(days, id: \.self) { date in
                    let activity = activityForDate(date)
                    let isToday = Calendar.current.isDate(date, inSameDayAs: Date())
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    
                    let daysDiff = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
                    let isForecastAvailable = (daysDiff >= -1 && daysDiff <= 7)
                    
                    // Extremely explicit type-checking values
                    var textColor: Color = .white
                    if isSelected {
                        textColor = .black
                    } else if isToday {
                        textColor = .teal
                    } else if !isForecastAvailable {
                        textColor = Color.white.opacity(0.65)
                    }
                    
                    var cellBg: Color = Color.white.opacity(0.02)
                    if isSelected {
                        cellBg = .white
                    } else if isForecastAvailable {
                        cellBg = colorForActivity(activity).opacity(0.3)
                    }
                    
                    var strokeColor: Color = Color.teal
                    if !isToday || isSelected {
                        let baseColor = colorForActivity(activity)
                        let borderOpacity = isForecastAvailable ? 1.0 : 0.45
                        strokeColor = baseColor.opacity(borderOpacity)
                    }
                    
                    let dashPattern: [CGFloat] = isForecastAvailable ? [] : [4.0, 3.0]
                    
                    VStack(spacing: 2) {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.footnote)
                            .fontWeight(isSelected ? .bold : (isToday ? .bold : .medium))
                            .foregroundColor(textColor)
                        
                        if isToday {
                            Circle()
                                .fill(isSelected ? Color.black : Color.teal)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(height: 32)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(cellBg)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                strokeColor,
                                style: StrokeStyle(
                                    lineWidth: isSelected ? 2.5 : (isToday ? 2.0 : 1.0),
                                    lineCap: .round,
                                    lineJoin: .round,
                                    dash: dashPattern
                                )
                            )
                    )
                    .onTapGesture {
                        selectedDate = date
                        calculateForecast()
                        updateWeatherAutomatically()
                    }
                }
            }
            
            // Legenda del calendario
            calendarLegend
        }
        .padding()
        .background(Color.white.opacity(0.04))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal)
    }
    
    private var calendarLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.vertical, 4)
            
            Text("LEGENDA CALENDARIO")
                .font(.system(size: 9))
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
            
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                            )
                            .frame(width: 12, height: 12)
                        Text("Previsioni Reali").font(.system(size: 9)).foregroundColor(.white.opacity(0.7))
                    }
                    
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            )
                            .frame(width: 12, height: 12)
                        Text("Stima Climatologica").font(.system(size: 9)).foregroundColor(.white.opacity(0.7))
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.teal)
                            .frame(width: 6, height: 6)
                        Text("Oggi (Giorno corrente)").font(.system(size: 9)).foregroundColor(.white.opacity(0.7))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Efficacia Pesca:").font(.system(size: 9)).foregroundColor(.white.opacity(0.5))
                    
                    HStack(spacing: 6) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(colorForActivity(level))
                                    .frame(width: 6, height: 6)
                                Text(level.rawValue).font(.system(size: 8)).foregroundColor(.white.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func intervalBackgroundColor(_ interval: HourlyInterval) -> Color {
        if interval.isEnhanced {
            return Color.red.opacity(0.12)
        } else if interval.isMajorPeriod {
            return Color(red: 255/255, green: 175/255, blue: 64/255).opacity(0.08)
        } else if interval.isMinorPeriod {
            return Color.cyan.opacity(0.06)
        } else {
            return Color.white.opacity(0.02)
        }
    }
}

// Supporting views
struct MoonPhaseView: View {
    var age: Double // Moon age (0 to 29.53)
    
    var symbolName: String {
        if age < 1.5 || age > 28.0 {
            return "moonphase.new.moon"
        } else if age < 6.5 {
            return "moonphase.waxing.crescent"
        } else if age < 8.3 {
            return "moonphase.first.quarter"
        } else if age < 13.3 {
            return "moonphase.waxing.gibbous"
        } else if age < 16.3 {
            return "moonphase.full.moon"
        } else if age < 21.2 {
            return "moonphase.waning.gibbous"
        } else if age < 23.0 {
            return "moonphase.last.quarter"
        } else {
            return "moonphase.waning.crescent"
        }
    }
    
    var body: some View {
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .foregroundColor(.yellow)
    }
}

struct TideChartView: View {
    var forecast: DailyForecast
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Andamento delle Maree")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.6))
            
            Canvas { context, size in
                let width = size.width
                let height = size.height
                
                // Draw zero level line
                var zeroPath = Path()
                zeroPath.move(to: CGPoint(x: 0, y: height / 2))
                zeroPath.addLine(to: CGPoint(x: width, y: height / 2))
                context.stroke(zeroPath, with: .color(Color.white.opacity(0.15)), lineWidth: 1)
                
                // Draw vertical grid lines
                for hour in [6, 12, 18] {
                    let gridX = (Double(hour) / 24.0) * Double(width)
                    var gridPath = Path()
                    gridPath.move(to: CGPoint(x: gridX, y: 0))
                    gridPath.addLine(to: CGPoint(x: gridX, y: height))
                    context.stroke(gridPath, with: .color(Color.white.opacity(0.1)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                
                // Scale vertical coordinates based on max Mediterranean amplitude (e.g. max 0.3m height)
                let maxAmplitude = max(forecast.maxTideAmplitude, 0.1)
                let scaleY = (height / 2 - 20) / maxAmplitude
                
                // Draw continuous tide height curve for 24h
                var tidePath = Path()
                let coord = forecast.location.coordinate
                
                for x in 0...Int(width) {
                    let hour = (Double(x) / Double(width)) * 24.0
                    // Calculate date offset from start of day
                    let sampleDate = forecast.date.addingTimeInterval(hour * 3600)
                    let h = TideEngine.calculateHeight(at: sampleDate, coordinate: coord)
                    
                    let drawY = height / 2 - CGFloat(h) * CGFloat(scaleY)
                    
                    if x == 0 {
                        tidePath.move(to: CGPoint(x: 0, y: drawY))
                    } else {
                        tidePath.addLine(to: CGPoint(x: CGFloat(x), y: drawY))
                    }
                }
                
                context.stroke(tidePath, with: .linearGradient(Gradient(colors: [.teal, .blue]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: width, y: 0)), lineWidth: 3)
                
                // Mark tide events (highs / lows)
                let calendar = Calendar.current
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                
                for event in forecast.tides {
                    let comps = calendar.dateComponents([.hour, .minute], from: event.time)
                    let totalHours = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
                    let drawX = (totalHours / 24.0) * Double(width)
                    let drawY = height / 2 - CGFloat(event.height) * CGFloat(scaleY)
                    
                    let dotRect = CGRect(x: drawX - 6, y: Double(drawY) - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: dotRect), with: .color(event.type == .alta ? .green : .cyan))
                    context.stroke(Path(ellipseIn: dotRect), with: .color(.white), lineWidth: 1.5)
                    
                    // Draw time text next to dot
                    let timeStr = formatter.string(from: event.time)
                    let text = Text(timeStr)
                        .font(.system(size: 9))
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    let yOffset: CGFloat = event.type == .alta ? -12 : 12
                    let anchor: UnitPoint = event.type == .alta ? .bottom : .top
                    context.draw(text, at: CGPoint(x: drawX, y: drawY + yOffset), anchor: anchor)
                }
            }
            
            // Time Axis Labels
            HStack {
                Text("00:00").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("06:00").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("12:00").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("18:00").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("24:00").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 4)
            
            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Alta Marea").font(.caption2).foregroundColor(.white.opacity(0.7))
                }
                HStack(spacing: 4) {
                    Circle().fill(Color.cyan).frame(width: 8, height: 8)
                    Text("Bassa Marea").font(.caption2).foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                Text("Escursione max: \(String(format: "%.2f", forecast.maxTideAmplitude))m")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.top, 4)
        }
    }
}

// Custom Colors and Extensions
extension Color {
    static let amberBadge = Color(red: 255/255, green: 175/255, blue: 64/255)
    static let cyanBadge = Color(red: 0/255, green: 242/255, blue: 254/255)
    static let amberText = Color(red: 255/255, green: 175/255, blue: 64/255)
}

struct FactorRow: View {
    let name: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(name)
                .foregroundColor(.white.opacity(0.7))
                .font(.footnote)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .font(.footnote)
                .fontWeight(.bold)
        }
        .padding(.vertical, 4)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
