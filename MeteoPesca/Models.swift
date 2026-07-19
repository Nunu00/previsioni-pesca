import Foundation

public struct Coordinate: Hashable, Codable {
    public var latitude: Double
    public var longitude: Double
    public var name: String?
    
    public init(latitude: Double, longitude: Double, name: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
    }
}

public struct Location: Hashable, Identifiable, Codable {
    public var id: UUID = UUID()
    public var name: String
    public var coordinate: Coordinate
    public var tideLagDays: Double
    
    public init(name: String, latitude: Double, longitude: Double, tideLagDays: Double = 1.5) {
        self.name = name
        self.coordinate = Coordinate(latitude: latitude, longitude: longitude, name: name)
        self.tideLagDays = tideLagDays
    }
}

public enum TideType: String, Codable {
    case alta = "Alta"
    case bassa = "Bassa"
}

public struct TideEvent: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var time: Date
    public var height: Double // in meters
    public var type: TideType
}

public enum SolunarType: String, Codable {
    case maggior = "Maggiore"
    case minor = "Minore"
}

public struct SolunarPeriod: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var startTime: Date
    public var endTime: Date
    public var type: SolunarType
    public var description: String // e.g. "Transito lunare", "Alba lunare"
    public var isEnhanced: Bool = false // overlaps with sunrise/sunset
}

public enum ActivityLevel: String, Codable, CaseIterable {
    case bassa = "Bassa"
    case moderata = "Moderata"
    case buona = "Buona"
    case alta = "Alta"
    case moltoAlta = "Molto Alta"
    
    public var score: Int {
        switch self {
        case .bassa: return 0
        case .moderata: return 1
        case .buona: return 2
        case .alta: return 3
        case .moltoAlta: return 4
        }
    }
    
    public var description: String {
        switch self {
        case .bassa: return "Attività Bassa"
        case .moderata: return "Attività Moderata"
        case .buona: return "Attività Buona 🎣"
        case .alta: return "Attività Alta! 🎣"
        case .moltoAlta: return "Attività Eccezionale! 🔥"
        }
    }
}

public struct HourlyInterval: Identifiable, Codable, Hashable {
    public var id: UUID = UUID()
    public var hour: Int // 0-23
    public var startTime: Date
    public var endTime: Date
    public var activity: ActivityLevel
    public var score: Double
    public var isMajorPeriod: Bool = false
    public var isMinorPeriod: Bool = false
    public var isEnhanced: Bool = false
}

public struct DailyForecast: Identifiable, Codable {
    public var id: UUID = UUID()
    public var date: Date
    public var location: Location
    
    // Astro
    public var sunrise: Date?
    public var sunset: Date?
    public var moonrise: Date?
    public var moonset: Date?
    public var moonTransit: Date?
    public var moonAntiTransit: Date?
    public var moonPhase: String
    public var moonAge: Double
    public var moonIllumination: Double // 0-100%
    
    // Tides
    public var tides: [TideEvent]
    public var maxTideAmplitude: Double
    
    // Solunar
    public var solunarPeriods: [SolunarPeriod]
    
    // Ratings
    public var dailyActivity: ActivityLevel
    public var hourlyIntervals: [HourlyInterval]
    
    // Detailed factor breakdown
    public var rawScore: Double
    public var moonPhaseFactor: Double
    public var moonDistanceFactor: Double
    public var tideCoeffFactor: Double
    public var solunarOverlapFactor: Double
    public var weatherFactorVal: Double
    public var waterTempFactor: Double
}

public struct WeatherFactor: Codable, Hashable {
    public var cloudCoverPercent: Double      // 0-100
    public var windDirectionChange: Double    // gradi di variazione ultime 3h
    public var swellHeight: Double            // metri, se disponibile per zona costiera
    public var surfaceTempDelta24h: Double    // variazione °C ultime 24h

    public init(cloudCoverPercent: Double, windDirectionChange: Double, swellHeight: Double, surfaceTempDelta24h: Double) {
        self.cloudCoverPercent = cloudCoverPercent
        self.windDirectionChange = windDirectionChange
        self.swellHeight = swellHeight
        self.surfaceTempDelta24h = surfaceTempDelta24h
    }

    public func multiplier() -> Double {
        var m = 1.0
        // Nuvolosità estende la finestra di alba/tramonto: bonus se >60%
        if cloudCoverPercent > 60.0 { m += 0.15 }
        // Cambio vento recente riposiziona i pesci: bonus nella prima ora dopo il cambio
        if windDirectionChange > 30.0 { m += 0.10 }
        // Swell in aumento smuove il cibo dal fondale
        if swellHeight > 0.5 { m += 0.10 }
        // Rottura della stratificazione termica in estate: bonus se calo repentino
        if surfaceTempDelta24h < -1.5 { m += 0.10 }
        return m
    }
}
