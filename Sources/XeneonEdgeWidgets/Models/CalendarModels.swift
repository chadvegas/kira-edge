import Foundation

/// Metadata for a single Google calendar the user can choose to display.
struct GoogleCalendarInfo: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let colorHex: String?
    let isPrimary: Bool
    let accountSummary: String
}

/// A single upcoming event rendered in the Clock widget agenda.
struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let colorHex: String?
}
