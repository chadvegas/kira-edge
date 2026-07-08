import Foundation

enum WeatherService {
    private static let cache = WeatherCache()

    static func snapshot() async -> WeatherSnapshot {
        let now = Date()
        if let cached = await cache.snapshotIfFresh(at: now) {
            return cached
        }

        let location: ApproximateLocation
        switch await approximateLocation() {
        case .success(let resolved):
            location = resolved
        case .rateLimited:
            let snapshot = WeatherSnapshot(
                locationName: "Weather",
                currentTemperature: nil,
                apparentTemperature: nil,
                conditionCode: nil,
                precipitationProbability: nil,
                windSpeed: nil,
                highTemperature: nil,
                lowTemperature: nil,
                hourly: [],
                lastUpdated: now,
                status: "Rate limited"
            )
            await cache.update(snapshot, at: now)
            return snapshot
        case .unavailable:
            let snapshot = WeatherSnapshot(
                locationName: "Weather",
                currentTemperature: nil,
                apparentTemperature: nil,
                conditionCode: nil,
                precipitationProbability: nil,
                windSpeed: nil,
                highTemperature: nil,
                lowTemperature: nil,
                hourly: [],
                lastUpdated: now,
                status: "Location unavailable"
            )
            await cache.update(snapshot, at: now)
            return snapshot
        }

        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            return .empty
        }

        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(location.latitude)"),
            URLQueryItem(name: "longitude", value: "\(location.longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { return .empty }

        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            guard
                let http = urlResponse as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else {
                throw WeatherServiceError.badStatus
            }
            let response = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
            let snapshot = response.snapshot(locationName: location.displayName, updatedAt: now)
            await cache.update(snapshot, at: now)
            return snapshot
        } catch {
            let snapshot = WeatherSnapshot(
                locationName: location.displayName,
                currentTemperature: nil,
                apparentTemperature: nil,
                conditionCode: nil,
                precipitationProbability: nil,
                windSpeed: nil,
                highTemperature: nil,
                lowTemperature: nil,
                hourly: [],
                lastUpdated: now,
                status: "Weather unavailable"
            )
            await cache.update(snapshot, at: now)
            return snapshot
        }
    }

    private static func approximateLocation() async -> LocationOutcome {
        if let cached = await cache.locationIfFresh(at: Date()) {
            return .success(cached)
        }

        guard let url = URL(string: "https://ipapi.co/json/") else { return .unavailable }

        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            if let http = urlResponse as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                // ipapi.co returns HTTP 429 with an error body when the free tier
                // is throttled; surface that distinctly instead of mis-decoding it.
                return http.statusCode == 429 ? .rateLimited : .unavailable
            }
            let response = try JSONDecoder().decode(IPLocationResponse.self, from: data)
            guard let latitude = response.latitude, let longitude = response.longitude else {
                return .unavailable
            }

            let displayName = [response.city, response.regionCode]
                .compactMap { $0?.isEmpty == false ? $0 : nil }
                .joined(separator: ", ")
            let location = ApproximateLocation(
                latitude: latitude,
                longitude: longitude,
                displayName: displayName.isEmpty ? "Local" : displayName
            )
            await cache.update(location, at: Date())
            return .success(location)
        } catch {
            return .unavailable
        }
    }
}

private enum LocationOutcome {
    case success(ApproximateLocation)
    case rateLimited
    case unavailable
}

private enum WeatherServiceError: Error {
    case badStatus
}

private actor WeatherCache {
    private var snapshot: WeatherSnapshot?
    private var snapshotDate: Date?
    private var location: ApproximateLocation?
    private var locationDate: Date?

    func snapshotIfFresh(at date: Date) -> WeatherSnapshot? {
        guard
            let snapshot,
            let snapshotDate,
            date.timeIntervalSince(snapshotDate) < 600
        else {
            return nil
        }
        return snapshot
    }

    func update(_ snapshot: WeatherSnapshot, at date: Date) {
        self.snapshot = snapshot
        snapshotDate = date
    }

    func locationIfFresh(at date: Date) -> ApproximateLocation? {
        guard
            let location,
            let locationDate,
            date.timeIntervalSince(locationDate) < 3600
        else {
            return nil
        }
        return location
    }

    func update(_ location: ApproximateLocation, at date: Date) {
        self.location = location
        locationDate = date
    }
}

private struct ApproximateLocation: Equatable {
    var latitude: Double
    var longitude: Double
    var displayName: String
}

private struct IPLocationResponse: Decodable {
    var latitude: Double?
    var longitude: Double?
    var city: String?
    var regionCode: String?

    enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case city
        case regionCode = "region_code"
    }
}

private struct OpenMeteoForecast: Decodable {
    var current: Current
    var hourly: Hourly
    var daily: Daily
    var timezone: String?
    var utcOffsetSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case current
        case hourly
        case daily
        case timezone
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    // The request sets timezone=auto, so Open-Meteo returns hourly/daily
    // timestamps as wall-clock strings in the IP-resolved location's zone. Pin
    // the parsers to that returned zone (preferring the exact UTC offset, then
    // the named identifier) so timestamps are interpreted consistently even when
    // the device timezone differs from the location's.
    private var locationTimeZone: TimeZone? {
        if let utcOffsetSeconds {
            return TimeZone(secondsFromGMT: utcOffsetSeconds)
        }
        if let timezone {
            return TimeZone(identifier: timezone)
        }
        return nil
    }

    func snapshot(locationName: String, updatedAt: Date) -> WeatherSnapshot {
        let hourParser = OpenMeteoDateParsers.makeHour(timeZone: locationTimeZone)
        let dayParser = OpenMeteoDateParsers.makeDay(timeZone: locationTimeZone)

        // Open-Meteo returns the hourly arrays anchored to 00:00 local of the
        // current day, so anchor the rolling window to the current hour instead
        // of always starting at midnight. A sample counts as "current or later"
        // when its timestamp is no more than one hour in the past.
        let parsedDates = hourly.times.map { hourParser.date(from: $0) }
        // Only build a window when an actual current-or-later sample exists.
        // If every sample is more than an hour in the past (or unparseable),
        // leave the window empty so the UI shows its status/empty state rather
        // than rendering stale, already-past midnight-anchored hours.
        let startIndex = parsedDates.firstIndex { date in
            guard let date else { return false }
            return date.timeIntervalSince(updatedAt) >= -3600
        }

        let window: Range<Int>
        if let startIndex {
            let endIndex = min(startIndex + 12, hourly.times.count)
            window = startIndex < endIndex ? startIndex..<endIndex : startIndex..<startIndex
        } else {
            window = 0..<0
        }
        let hourlyForecast = window.compactMap { index -> HourlyWeather? in
            guard
                let date = parsedDates[safe: index] ?? nil,
                let temperature = hourly.temperatures[safe: index] ?? nil
            else {
                return nil
            }

            return HourlyWeather(
                date: date,
                temperature: temperature,
                precipitationProbability: (hourly.precipitationProbabilities[safe: index] ?? nil).map { Double($0) / 100 },
                conditionCode: hourly.weatherCodes[safe: index] ?? nil
            )
        }

        let dailyForecast: [DailyForecast] = daily.times.indices.compactMap { index in
            guard
                let date = dayParser.date(from: daily.times[index]),
                let high = daily.highs[safe: index] ?? nil,
                let low = daily.lows[safe: index] ?? nil
            else {
                return nil
            }
            return DailyForecast(
                date: date,
                high: high,
                low: low,
                conditionCode: daily.weatherCodes[safe: index] ?? nil
            )
        }

        return WeatherSnapshot(
            locationName: locationName,
            currentTemperature: current.temperature,
            apparentTemperature: current.apparentTemperature,
            conditionCode: current.weatherCode,
            precipitationProbability: hourlyForecast.first?.precipitationProbability,
            windSpeed: current.windSpeed,
            highTemperature: dailyForecast.first?.high,
            lowTemperature: dailyForecast.first?.low,
            hourly: Array(hourlyForecast),
            daily: dailyForecast,
            lastUpdated: updatedAt,
            status: "Updated"
        )
    }

    struct Current: Decodable {
        var temperature: Double?
        var apparentTemperature: Double?
        var weatherCode: Int?
        var windSpeed: Double?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case windSpeed = "wind_speed_10m"
        }
    }

    struct Hourly: Decodable {
        var times: [String]
        var temperatures: [Double?]
        var precipitationProbabilities: [Int?]
        var weatherCodes: [Int?]

        enum CodingKeys: String, CodingKey {
            case times = "time"
            case temperatures = "temperature_2m"
            case precipitationProbabilities = "precipitation_probability"
            case weatherCodes = "weather_code"
        }
    }

    struct Daily: Decodable {
        var times: [String]
        var highs: [Double?]
        var lows: [Double?]
        var weatherCodes: [Int?]

        enum CodingKeys: String, CodingKey {
            case times = "time"
            case highs = "temperature_2m_max"
            case lows = "temperature_2m_min"
            case weatherCodes = "weather_code"
        }
    }
}

private enum OpenMeteoDateParsers {
    // Build a fresh parser per decode pinned to the location's timezone. A new
    // DateFormatter avoids mutating shared state across concurrent decodes; when
    // no zone is supplied it falls back to the device timezone (prior behavior).
    static func makeHour(timeZone: TimeZone?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let timeZone {
            formatter.timeZone = timeZone
        }
        return formatter
    }

    static func makeDay(timeZone: TimeZone?) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        if let timeZone {
            formatter.timeZone = timeZone
        }
        return formatter
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
