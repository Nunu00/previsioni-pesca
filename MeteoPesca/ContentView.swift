import SwiftUI

struct ContentView: View {
    @State private var selectedDate: Date = Date()
    @State private var selectedLocation: Location = TideEngine.stations[0]
    @State private var customLatitude: String = "39.73"
    @State private var customLongitude: String = "16.48"
    @State private var isShowingCustomCoordinates: Bool = false
    @State private var savedLocations: [Location] = TideEngine.stations
    @State private var forecast: DailyForecast?
    
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
                            DatePicker("Seleziona Data", selection: $selectedDate, displayedComponents: [.date])
                                .datePickerStyle(.compact)
                                .environment(\.locale, Locale(identifier: "it"))
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(12)
                            
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
                                    calculateForecast()
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
                                    ForEach(0..<3) { idx in
                                        Image(systemName: "fish.fill")
                                            .font(.title2)
                                            .foregroundColor(idx < forecast.dailyActivity.score ? colorForActivity(forecast.dailyActivity) : Color.white.opacity(0.2))
                                    }
                                }
                                .padding(.top, 4)
                                
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
                            
                            // 6. Hourly intervals timeline
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Timeline Attività Oraria")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                ForEach(forecast.hourlyIntervals) { interval in
                                    HStack {
                                        Text(String(format: "%02d:00", interval.hour))
                                            .font(.subheadline)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white.opacity(0.8))
                                            .frame(width: 50, alignment: .leading)
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(interval.activity.rawValue)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundColor(colorForActivity(interval.activity))
                                            
                                            if interval.isEnhanced {
                                                Text("Picco Potenziato")
                                                    .font(.system(size: 9))
                                                    .fontWeight(.black)
                                                    .foregroundColor(.red)
                                            } else if interval.isMajorPeriod {
                                                Text("Periodo Maggiore")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.amberText)
                                            } else if interval.isMinorPeriod {
                                                Text("Periodo Minore")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.cyan)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        
                                        // Visual rating dots
                                        HStack(spacing: 4) {
                                            ForEach(0..<3) { idx in
                                                Circle()
                                                    .fill(idx < interval.activity.score ? colorForActivity(interval.activity) : Color.white.opacity(0.1))
                                                    .frame(width: 8, height: 8)
                                            }
                                        }
                                        .padding(.leading, 8)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 10)
                                    .background(intervalBackgroundColor(interval))
                                    .cornerRadius(8)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(16)
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
            .onAppear(perform: calculateForecast)
            .onChange(of: selectedDate) { _ in calculateForecast() }
        }
        .preferredColorScheme(.dark)
    }
    
    private func applyCustomCoordinates() {
        if let lat = Double(customLatitude), let lon = Double(customLongitude) {
            let customLoc = Location(name: "Coordinate Manuali", latitude: lat, longitude: lon)
            selectedLocation = customLoc
            calculateForecast()
        }
    }
    
    private func calculateForecast() {
        // 1. Calculate Sun/Moon ephemerides via SwiftAA
        let coord = selectedLocation.coordinate
        let astro = AstronomyEngine.calculateAstronomy(date: selectedDate, coordinate: coord)
        
        // 2. Generate tides offline via local harmonic constituent database
        let tides = TideEngine.calculateDailyTides(date: selectedDate, coordinate: coord)
        
        // 3. Evaluate solunar rules and fish activity scoring
        let forecastResult = RulesEngine.evaluateForecast(
            date: selectedDate,
            location: selectedLocation,
            sunrise: astro.sunrise,
            sunset: astro.sunset,
            moonrise: astro.moonrise,
            moonset: astro.moonset,
            moonTransit: astro.moonTransit,
            moonAntiTransit: astro.moonAntiTransit,
            moonAge: astro.moonAge,
            tides: tides
        )
        
        self.forecast = forecastResult
    }
    
    private func timeString(_ date: Date?) -> String {
        guard let date = date else { return "--:--" }
        return hourFormatter.string(from: date)
    }
    
    private func colorForActivity(_ level: ActivityLevel) -> Color {
        switch level {
        case .bassa: return .gray
        case .media: return .yellow
        case .alta: return .orange
        case .moltoAlta: return .green
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
                }
            }
            
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
