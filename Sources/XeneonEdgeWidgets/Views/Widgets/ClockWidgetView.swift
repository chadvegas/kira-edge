import SwiftUI

struct ClockWidgetView: View {
    let date: Date
    let weather: WeatherSnapshot
    let showsFullDayForecast: Bool
    let use24Hour: Bool
    let forecastRange: ForecastRange
    let accent: Color
    let events: [CalendarEventItem]
    let calendarConnected: Bool
    let toggleForecast: () -> Void
    let setForecastRange: (ForecastRange) -> Void

    /// The fetched list keeps today's already-ended events so the month grid
    /// can dot today; the agenda only shows events that haven't ended yet.
    private var upcomingEvents: [CalendarEventItem] {
        events.filter { $0.end > date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 7) {
                        Text(EdgeFormatters.timeString(from: date, use24Hour: use24Hour))
                            .font(EdgeTheme.displayFont(size: 64, weight: .heavy))
                            .foregroundStyle(EdgeTheme.primaryText)
                            .monospacedDigit()
                            .minimumScaleFactor(0.42)
                            .lineLimit(1)

                        VStack(alignment: .leading, spacing: 0) {
                            if !use24Hour {
                                Text(EdgeFormatters.amPM.string(from: date))
                                    .font(EdgeTheme.bodyFont(size: 14, weight: .black))
                                    .foregroundStyle(EdgeTheme.secondaryText)
                            }

                            Text(EdgeFormatters.seconds.string(from: date))
                                .font(EdgeTheme.displayFont(size: 22, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(accent)
                                .shadow(color: accent.opacity(0.55), radius: 8)
                        }
                    }

                    Text(EdgeFormatters.fullDate.string(from: date))
                        .font(EdgeTheme.bodyFont(size: 22, weight: .heavy))
                        .foregroundStyle(EdgeTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }

                Spacer(minLength: 8)

                Button(action: toggleForecast) {
                    CompactWeatherSummary(weather: weather, accent: accent, expanded: showsFullDayForecast)
                }
                .buttonStyle(.plain)
                .help(showsFullDayForecast ? "Hide forecast" : "Show forecast")
            }

            if showsFullDayForecast {
                ExpandedForecastView(
                    weather: weather,
                    accent: accent,
                    range: forecastRange,
                    setRange: setForecastRange
                )
            }

            if calendarConnected {
                CalendarMonthView(date: date, events: events, accent: accent)
            }

            if !upcomingEvents.isEmpty {
                CalendarAgendaView(events: upcomingEvents, now: date, accent: accent, use24Hour: use24Hour)
            }

            Spacer(minLength: 4)

            HStack(spacing: 7) {
                ForEach(0..<24, id: \.self) { hour in
                    Capsule()
                        .fill(hour <= Calendar.current.component(.hour, from: date) ? accent : EdgeTheme.mutedFill)
                        .shadow(color: hour <= Calendar.current.component(.hour, from: date) ? accent.opacity(0.48) : .clear, radius: 6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 8)
                }
            }
        }
    }
}

private struct CalendarMonthView: View {
    let date: Date
    let events: [CalendarEventItem]
    let accent: Color

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    private var calendar: Calendar { Calendar.current }

    /// Every day each event spans, clamped to the visible month: days outside
    /// this month never render, and clamping (rather than capping the walk from
    /// the event's start) keeps months-long in-progress events dotted while
    /// bounding cost. The `day < end` test naturally handles the all-day
    /// exclusive-end convention (an event ending at midnight doesn't dot that day).
    private var eventDays: Set<Date> {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        var days: Set<Date> = []
        for event in events {
            let startDay = calendar.startOfDay(for: event.start)
            guard startDay < month.end, event.end > month.start || startDay >= month.start else { continue }

            var day = max(startDay, month.start)
            // First visible day: the event's own start day, or the clamped month
            // start while a longer event is still in progress.
            if day == startDay || day < event.end {
                days.insert(day)
            }
            var iterations = 0
            while iterations < 40 {
                guard
                    let next = calendar.date(byAdding: .day, value: 1, to: day),
                    next < event.end,
                    next < month.end
                else { break }
                days.insert(next)
                day = next
                iterations += 1
            }
        }
        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    private var weeks: [[Date?]] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 0
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for offset in 0..<daysInMonth {
            cells.append(calendar.date(byAdding: .day, value: offset, to: firstOfMonth))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        AnimeWell {
            VStack(alignment: .leading, spacing: 6) {
                Text(Self.monthFormatter.string(from: date))
                    .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                    .foregroundStyle(EdgeTheme.primaryText)

                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(EdgeTheme.bodyFont(size: 9, weight: .black))
                            .foregroundStyle(EdgeTheme.tertiaryText)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            CalendarDayCell(
                                day: day,
                                isToday: day.map { calendar.isDate($0, inSameDayAs: date) } ?? false,
                                hasEvent: day.map { eventDays.contains(calendar.startOfDay(for: $0)) } ?? false,
                                accent: accent
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct CalendarDayCell: View {
    let day: Date?
    let isToday: Bool
    let hasEvent: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(accent)
                        .frame(width: 22, height: 22)
                        .shadow(color: accent.opacity(0.5), radius: 5)
                }
                if let day {
                    Text("\(Calendar.current.component(.day, from: day))")
                        .font(EdgeTheme.bodyFont(size: 11, weight: isToday ? .black : .heavy))
                        .foregroundStyle(isToday ? EdgeTheme.accentGlyph : EdgeTheme.primaryText)
                }
            }
            .frame(height: 22)

            Circle()
                .fill(hasEvent ? accent : .clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .opacity(day == nil ? 0 : 1)
    }
}

private struct CompactWeatherSummary: View {
    let weather: WeatherSnapshot
    let accent: Color
    let expanded: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: weather.symbolName)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(accent)
                .shadow(color: accent.opacity(0.4), radius: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(EdgeFormatters.temperature(weather.currentTemperature))
                    .font(EdgeTheme.displayFont(size: 27, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(EdgeTheme.primaryText)

                Text("\(EdgeFormatters.temperature(weather.highTemperature)) / \(EdgeFormatters.temperature(weather.lowTemperature))")
                    .font(EdgeTheme.bodyFont(size: 11, weight: .black))
                    .foregroundStyle(EdgeTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(EdgeTheme.tertiaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(EdgeTheme.interactiveFill, in: RoundedRectangle(cornerRadius: EdgeTheme.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EdgeTheme.chipRadius, style: .continuous)
                .stroke(EdgeTheme.stroke, lineWidth: 1)
        }
    }
}

private struct ExpandedForecastView: View {
    let weather: WeatherSnapshot
    let accent: Color
    let range: ForecastRange
    let setRange: (ForecastRange) -> Void

    var body: some View {
        AnimeWell {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(weather.locationName, systemImage: weather.symbolName)
                        .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                        .foregroundStyle(EdgeTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(ForecastRange.allCases) { option in
                            Button {
                                setRange(option)
                            } label: {
                                Text(option.title)
                                    .font(EdgeTheme.bodyFont(size: 11, weight: .black))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(option == range ? accent.opacity(0.20) : EdgeTheme.interactiveFill, in: Capsule())
                                    .overlay {
                                        Capsule()
                                            .stroke(option == range ? accent.opacity(0.72) : EdgeTheme.stroke, lineWidth: 1)
                                    }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(option == range ? accent : EdgeTheme.secondaryText)
                        }
                    }
                }

                forecastRows
            }
        }
    }

    @ViewBuilder
    private var forecastRows: some View {
        switch range {
        case .day:
            if weather.hourly.isEmpty {
                emptyState
            } else {
                VStack(spacing: 5) {
                    ForEach(weather.hourly.prefix(6)) { hour in
                        HourForecastRow(hour: hour, accent: accent)
                    }
                }
            }
        case .week:
            if weather.daily.isEmpty {
                emptyState
            } else {
                VStack(spacing: 5) {
                    ForEach(weather.daily.prefix(7)) { day in
                        DailyForecastRow(day: day, accent: accent)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Text(weather.status)
            .font(EdgeTheme.bodyFont(size: 14, weight: .bold))
            .foregroundStyle(EdgeTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
    }
}

private struct DailyForecastRow: View {
    let day: DailyForecast
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(dayLabel)
                .font(EdgeTheme.bodyFont(size: 12, weight: .black))
                .foregroundStyle(EdgeTheme.secondaryText)
                .frame(width: 44, alignment: .leading)

            Image(systemName: day.symbolName)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 20)

            Spacer()

            Text("\(EdgeFormatters.temperature(day.high)) / \(EdgeFormatters.temperature(day.low))")
                .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                .foregroundStyle(EdgeTheme.primaryText)
                .monospacedDigit()
        }
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: day.date)
    }
}

private struct CompactWeatherView: View {
    let weather: WeatherSnapshot
    let accent: Color

    var body: some View {
        AnimeWell {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    AnimeIconBadge(symbolName: weather.symbolName, accent: accent, size: 44, iconSize: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(EdgeFormatters.temperature(weather.currentTemperature))
                                .font(EdgeTheme.displayFont(size: 36, weight: .heavy))
                                .monospacedDigit()
                                .foregroundStyle(EdgeTheme.primaryText)

                            Text(weather.conditionTitle)
                                .font(EdgeTheme.bodyFont(size: 14, weight: .black))
                                .foregroundStyle(EdgeTheme.secondaryText)
                                .lineLimit(1)
                        }

                        Text(weather.locationName)
                            .font(EdgeTheme.bodyFont(size: 12, weight: .bold))
                            .foregroundStyle(EdgeTheme.tertiaryText)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 8) {
                    WeatherChip(title: "Feels", value: EdgeFormatters.temperature(weather.apparentTemperature))
                    WeatherChip(title: "High", value: EdgeFormatters.temperature(weather.highTemperature))
                    WeatherChip(title: "Low", value: EdgeFormatters.temperature(weather.lowTemperature))
                }

                HStack(spacing: 8) {
                    WeatherChip(title: "Rain", value: weather.precipitationProbability.map(EdgeFormatters.percent) ?? "--")
                    WeatherChip(title: "Wind", value: weather.windSpeed.map { "\(Int($0.rounded())) mph" } ?? "--")
                }
            }
        }
    }
}

private struct CalendarAgendaView: View {
    let events: [CalendarEventItem]
    let now: Date
    let accent: Color
    let use24Hour: Bool

    var body: some View {
        AnimeWell {
            VStack(alignment: .leading, spacing: 7) {
                Label("Upcoming", systemImage: "calendar")
                    .font(EdgeTheme.bodyFont(size: 12, weight: .black))
                    .foregroundStyle(EdgeTheme.secondaryText)
                    .lineLimit(1)

                VStack(spacing: 5) {
                    ForEach(events.prefix(4)) { event in
                        CalendarAgendaRow(event: event, now: now, accent: accent, use24Hour: use24Hour)
                    }
                }
            }
        }
    }
}

private struct CalendarAgendaRow: View {
    let event: CalendarEventItem
    let now: Date
    let accent: Color
    let use24Hour: Bool

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color(hexRGB: event.colorHex ?? "") ?? accent)
                .frame(width: 9, height: 9)

            Text(event.title)
                .font(EdgeTheme.bodyFont(size: 13, weight: .heavy))
                .foregroundStyle(EdgeTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(timeLabel)
                .font(EdgeTheme.bodyFont(size: 12, weight: .bold))
                .foregroundStyle(EdgeTheme.tertiaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    /// The 35-day fetch window means rows can be days or weeks out, so the
    /// trailing label carries day context: today shows the time (or "All day"),
    /// the next six days show a weekday abbreviation, anything further shows a
    /// month + day.
    private var timeLabel: String {
        let calendar = Calendar.current

        // In-progress events (including multi-day ones that started before
        // today) read as happening now, not as a stale past start date.
        if event.start <= now {
            return event.isAllDay ? "All day" : "Now"
        }

        let daysAway = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: event.start)
        ).day ?? 0

        if daysAway == 0 {
            if event.isAllDay { return "All day" }
            // Honor the clock's 24-hour setting; the 12-hour path keeps its
            // AM/PM designator (EdgeFormatters.time has none).
            return use24Hour
                ? EdgeFormatters.time24.string(from: event.start)
                : Self.timeFormatter.string(from: event.start)
        }

        let dayLabel: String
        if (1...6).contains(daysAway) {
            dayLabel = Self.weekdayFormatter.string(from: event.start)
        } else {
            dayLabel = Self.monthDayFormatter.string(from: event.start)
        }
        return event.isAllDay ? "\(dayLabel) all day" : dayLabel
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}

private struct FullDayForecastView: View {
    let weather: WeatherSnapshot
    let accent: Color

    var body: some View {
        AnimeWell {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(weather.locationName, systemImage: weather.symbolName)
                        .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                        .foregroundStyle(EdgeTheme.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Text("\(EdgeFormatters.temperature(weather.highTemperature)) / \(EdgeFormatters.temperature(weather.lowTemperature))")
                        .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                        .foregroundStyle(accent)
                        .monospacedDigit()
                }

                if weather.hourly.isEmpty {
                    Text(weather.status)
                        .font(EdgeTheme.bodyFont(size: 14, weight: .bold))
                        .foregroundStyle(EdgeTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .center)
                } else {
                    VStack(spacing: 5) {
                        ForEach(weather.hourly.prefix(6)) { hour in
                            HourForecastRow(hour: hour, accent: accent)
                        }
                    }
                }
            }
        }
    }
}

private struct HourForecastRow: View {
    let hour: HourlyWeather
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(hourLabel)
                .font(EdgeTheme.bodyFont(size: 12, weight: .black))
                .foregroundStyle(EdgeTheme.secondaryText)
                .frame(width: 44, alignment: .leading)

            Image(systemName: hour.symbolName)
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(accent)
                .frame(width: 20)

            Text(EdgeFormatters.temperature(hour.temperature))
                .font(EdgeTheme.bodyFont(size: 13, weight: .black))
                .foregroundStyle(EdgeTheme.primaryText)
                .monospacedDigit()
                .frame(width: 42, alignment: .leading)

            Spacer()

            Text(hour.precipitationProbability.map(EdgeFormatters.percent) ?? "--")
                .font(EdgeTheme.bodyFont(size: 12, weight: .bold))
                .foregroundStyle(EdgeTheme.tertiaryText)
                .monospacedDigit()
        }
    }

    private var hourLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: hour.date).lowercased()
    }
}

private struct WeatherChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(EdgeTheme.bodyFont(size: 9, weight: .black))
                .foregroundStyle(EdgeTheme.tertiaryText)
                .textCase(.uppercase)
                .lineLimit(1)

            Text(value)
                .font(EdgeTheme.bodyFont(size: 12, weight: .heavy))
                .foregroundStyle(EdgeTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(EdgeTheme.interactiveFill, in: RoundedRectangle(cornerRadius: EdgeTheme.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EdgeTheme.chipRadius, style: .continuous)
                .stroke(EdgeTheme.stroke, lineWidth: 1)
        }
    }
}
