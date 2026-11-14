import Foundation

/// One medicine alarm, e.g. "Morning medicine at 8:00, scan the Medicine box".
struct MedAlarm: Identifiable, Codable, Hashable {
    /// Also used as the AlarmKit ID of the repeating alarm.
    var id: UUID = UUID()
    var name: String = "Medicine"
    var objectName: String = "Medicine box"
    var hour: Int = 8
    var minute: Int = 0
    var days: Set<Weekday> = Set(Weekday.allCases)
    var isEnabled: Bool = true
    /// File names of the reference photos (stored by ImageStore).
    var referencePhotos: [String] = []
    /// Words read from the label of the object in the reference photos.
    var referenceWords: [String] = []
    var strictness: Strictness = .normal

    var timeText: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    var daysText: String {
        if days.count == 7 { return "Every day" }
        if days == [.monday, .tuesday, .wednesday, .thursday, .friday] { return "Weekdays" }
        if days == [.saturday, .sunday] { return "Weekends" }
        return Weekday.ordered.filter { days.contains($0) }.map(\.short).joined(separator: ", ")
    }
}

enum Weekday: Int, Codable, CaseIterable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    var short: String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][rawValue - 1]
    }

    var twoLetter: String {
        ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"][rawValue - 1]
    }

    var localeWeekday: Locale.Weekday {
        switch self {
        case .sunday: return .sunday
        case .monday: return .monday
        case .tuesday: return .tuesday
        case .wednesday: return .wednesday
        case .thursday: return .thursday
        case .friday: return .friday
        case .saturday: return .saturday
        }
    }

    /// Days in the order the user's calendar shows them (Monday first in NZ).
    static var ordered: [Weekday] {
        let first = Calendar.current.firstWeekday
        return (0..<7).compactMap { Weekday(rawValue: ((first - 1 + $0) % 7) + 1) }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How closely the new photo has to match the reference photos.
enum Strictness: String, Codable, CaseIterable, Identifiable {
    case relaxed, normal, strict

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .normal: return "Normal"
        case .strict: return "Strict"
        }
    }

    /// Largest allowed Vision feature-print distance (0 = identical, about 1.4 = unrelated).
    var baseThreshold: Float {
        switch self {
        case .relaxed: return 0.80
        case .normal: return 0.65
        case .strict: return 0.50
        }
    }

    /// Extra visual tolerance when at least two label words also match.
    var textBonus: Float {
        switch self {
        case .relaxed: return 0.35
        case .normal: return 0.25
        case .strict: return 0.15
        }
    }
}

struct DoseLog: Identifiable, Codable, Hashable {
    enum Outcome: String, Codable {
        case taken, skipped
    }

    var id = UUID()
    var alarmID: UUID
    var alarmName: String
    var rangAt: Date
    var resolvedAt: Date
    var outcome: Outcome
}

/// Everything the app saves to disk.
struct AppState: Codable {
    var alarms: [MedAlarm] = []
    /// One-shot "ring again" alarms: AlarmKit ID (string) -> MedAlarm ID.
    var reminders: [String: UUID] = [:]
    /// Doses that rang but have not been verified yet: MedAlarm ID (string) -> first ring time.
    var pending: [String: Date] = [:]
    var logs: [DoseLog] = []
    /// Minutes until the alarm rings again if the photo has not been verified.
    var repeatMinutes: Int = 2

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alarms = try container.decodeIfPresent([MedAlarm].self, forKey: .alarms) ?? []
        reminders = try container.decodeIfPresent([String: UUID].self, forKey: .reminders) ?? [:]
        pending = try container.decodeIfPresent([String: Date].self, forKey: .pending) ?? [:]
        logs = try container.decodeIfPresent([DoseLog].self, forKey: .logs) ?? []
        repeatMinutes = try container.decodeIfPresent(Int.self, forKey: .repeatMinutes) ?? 2
    }
}

struct VerificationRequest: Identifiable, Equatable {
    let id: UUID
}
