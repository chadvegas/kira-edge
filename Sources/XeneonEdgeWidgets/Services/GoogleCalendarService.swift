import Foundation

/// Read-only Google Calendar API client. Callers supply a valid OAuth access
/// token (obtained via `GoogleAuthService`); this type performs no auth itself.
enum GoogleCalendarService {
    /// Maximum number of merged events returned by `events(...)`. Sized so a
    /// ~5-week fetch window can populate the month grid, not just a short list.
    private static let eventCap = 400

    /// Maximum number of events fetched per calendar across pagination. Bounds
    /// the number of follow-up `pageToken` requests for very busy calendars.
    private static let perCalendarEventCap = 300

    // MARK: Calendar list

    /// Fetches the user's calendar list and maps it to `GoogleCalendarInfo`,
    /// sorted primary-first then alphabetically by title.
    static func listCalendars(accessToken: String) async throws -> [GoogleCalendarInfo] {
        guard let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") else {
            throw GoogleCalendarServiceError.invalidURL
        }

        let data = try await get(url, accessToken: accessToken)
        let response = try JSONDecoder().decode(CalendarListResponse.self, from: data)

        let calendars = response.items.map { item -> GoogleCalendarInfo in
            let title = item.summary ?? item.id
            return GoogleCalendarInfo(
                id: item.id,
                title: title,
                colorHex: item.backgroundColor,
                isPrimary: item.primary ?? false,
                accountSummary: item.summary ?? item.id
            )
        }

        return calendars.sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    // MARK: Events

    /// Fetches events for each calendar concurrently, merges them, drops events
    /// that ended before the start of today (keeping today's finished events so
    /// the month grid still dots today), sorts ascending by start, and caps the
    /// count. A failure fetching any single calendar is tolerated and that
    /// calendar is skipped rather than failing the whole request.
    static func events(
        accessToken: String,
        calendarIDs: [String],
        from: Date,
        to: Date
    ) async throws -> [CalendarEventItem] {
        guard !calendarIDs.isEmpty else { return [] }

        let timeMin = isoFormatter.string(from: from)
        let timeMax = isoFormatter.string(from: to)

        let merged = await withTaskGroup(of: [CalendarEventItem].self) { group in
            for calendarID in calendarIDs {
                group.addTask {
                    do {
                        return try await fetchEvents(
                            accessToken: accessToken,
                            calendarID: calendarID,
                            timeMin: timeMin,
                            timeMax: timeMax
                        )
                    } catch {
                        // Tolerate per-calendar failures: skip this calendar.
                        return []
                    }
                }
            }

            var collected: [CalendarEventItem] = []
            for await events in group {
                collected.append(contentsOf: events)
            }
            return collected
        }

        let startOfToday = Calendar.current.startOfDay(for: Date())
        return merged
            .filter { $0.end > startOfToday }
            .sorted { $0.start < $1.start }
            .prefix(eventCap)
            .map { $0 }
    }

    private static func fetchEvents(
        accessToken: String,
        calendarID: String,
        timeMin: String,
        timeMax: String
    ) async throws -> [CalendarEventItem] {
        // The calendar ID is a path segment and may contain characters such as
        // "@" or "#" that must be percent-encoded.
        let encodedID = calendarID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarID

        // A page may be short (or empty) even when more events match, so follow
        // nextPageToken until the API reports no further pages, bounded by
        // perCalendarEventCap (plus a page-count safety valve, since an empty
        // page can still carry a token).
        var events: [CalendarEventItem] = []
        var pageToken: String?
        var pageCount = 0

        repeat {
            guard var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedID)/events") else {
                throw GoogleCalendarServiceError.invalidURL
            }

            var queryItems = [
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "timeMin", value: timeMin),
                URLQueryItem(name: "timeMax", value: timeMax),
                URLQueryItem(name: "maxResults", value: "100")
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw GoogleCalendarServiceError.invalidURL
            }

            let data = try await get(url, accessToken: accessToken)
            let response = try JSONDecoder().decode(EventsResponse.self, from: data)

            events.append(contentsOf: response.items.compactMap { item in
                item.toEventItem(calendarID: calendarID, color: response.backgroundColor)
            })
            pageToken = response.nextPageToken
            pageCount += 1
        } while pageToken != nil && events.count < perCalendarEventCap && pageCount < 10

        return events
    }

    // MARK: Networking

    private static func get(_ url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard
            let http = urlResponse as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw GoogleCalendarServiceError.badStatus
        }
        return data
    }

    // MARK: Date parsing

    /// ISO8601 parser/formatter for `dateTime` values (with fractional seconds
    /// tolerated via the fallback below).
    // Formatters are immutable after setup and used read-only for parsing, which is
    // thread-safe — nonisolated(unsafe) satisfies Swift 6 strict concurrency.
    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// All-day events use a plain `yyyy-MM-dd` date string.
    private static let allDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    fileprivate static func parseDateTime(_ string: String) -> Date? {
        if let date = isoFormatter.date(from: string) {
            return date
        }
        return isoFractionalFormatter.date(from: string)
    }

    fileprivate static func parseAllDay(_ string: String) -> Date? {
        allDayFormatter.date(from: string)
    }
}

// MARK: - Errors

private enum GoogleCalendarServiceError: Error {
    case invalidURL
    case badStatus
}

// MARK: - Wire types

private struct CalendarListResponse: Decodable {
    var items: [Item]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }

    struct Item: Decodable {
        var id: String
        var summary: String?
        var backgroundColor: String?
        var primary: Bool?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try container.decodeIfPresent(String.self, forKey: .id)) ?? ""
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
            primary = try container.decodeIfPresent(Bool.self, forKey: .primary)
        }

        enum CodingKeys: String, CodingKey {
            case id
            case summary
            case backgroundColor
            case primary
        }
    }
}

private struct EventsResponse: Decodable {
    var items: [Item]
    var backgroundColor: String?
    var nextPageToken: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        nextPageToken = try container.decodeIfPresent(String.self, forKey: .nextPageToken)
    }

    enum CodingKeys: String, CodingKey {
        case items
        case backgroundColor
        case nextPageToken
    }

    struct Item: Decodable {
        var id: String
        var summary: String?
        var start: Endpoint?
        var end: Endpoint?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
            summary = try container.decodeIfPresent(String.self, forKey: .summary)
            start = try container.decodeIfPresent(Endpoint.self, forKey: .start)
            end = try container.decodeIfPresent(Endpoint.self, forKey: .end)
        }

        enum CodingKeys: String, CodingKey {
            case id
            case summary
            case start
            case end
        }

        /// Resolves the wire representation into a `CalendarEventItem`, or nil if
        /// no usable start time is present.
        func toEventItem(calendarID: String, color: String?) -> CalendarEventItem? {
            guard let start, let resolvedStart = start.resolvedDate else {
                return nil
            }

            let isAllDay = start.dateTime == nil && start.date != nil

            // Fall back to the start time when an explicit end is missing so the
            // event still has a sensible (zero-length) span.
            let resolvedEnd = end?.resolvedDate ?? resolvedStart

            return CalendarEventItem(
                id: id,
                title: (summary?.isEmpty == false ? summary : nil) ?? "(No title)",
                start: resolvedStart,
                end: resolvedEnd,
                isAllDay: isAllDay,
                calendarID: calendarID,
                colorHex: color
            )
        }
    }

    struct Endpoint: Decodable {
        var dateTime: String?
        var date: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dateTime = try container.decodeIfPresent(String.self, forKey: .dateTime)
            date = try container.decodeIfPresent(String.self, forKey: .date)
        }

        enum CodingKeys: String, CodingKey {
            case dateTime
            case date
        }

        var resolvedDate: Date? {
            if let dateTime {
                return GoogleCalendarService.parseDateTime(dateTime)
            }
            if let date {
                return GoogleCalendarService.parseAllDay(date)
            }
            return nil
        }
    }
}
