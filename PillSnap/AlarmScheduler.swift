import AlarmKit
import SwiftUI

/// AlarmKit needs a metadata type even if we don't use it.
struct PillSnapAlarmMetadata: AlarmMetadata {}

extension MedAlarm {
    var recurrence: Alarm.Schedule.Relative.Recurrence {
        if days.isEmpty { return .never }
        let weekdays = Weekday.allCases.filter { days.contains($0) }.map(\.localeWeekday)
        return .weekly(weekdays)
    }
}

/// Thin wrapper around AlarmKit's AlarmManager.
enum AlarmScheduler {
    typealias Configuration = AlarmManager.AlarmConfiguration<PillSnapAlarmMetadata>

    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    static func requestAuthorization() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    static func currentAlarms() -> [Alarm] {
        (try? AlarmManager.shared.alarms) ?? []
    }

    static func isAlerting(_ id: UUID) -> Bool {
        currentAlarms().contains { $0.id == id && $0.state == .alerting }
    }

    /// Silences an alarm only if it is ringing right now
    /// (so we never touch the next occurrence of a repeating alarm).
    static func stopIfAlerting(_ id: UUID) {
        if isAlerting(id) {
            try? AlarmManager.shared.stop(id: id)
        }
    }

    static func cancel(_ id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
    }

    /// The main alarm, e.g. every day at 8:00.
    static func scheduleRepeating(_ alarm: MedAlarm) async throws {
        let schedule = Alarm.Schedule.relative(.init(
            time: .init(hour: alarm.hour, minute: alarm.minute),
            repeats: alarm.recurrence
        ))
        try await submit(id: alarm.id, schedule: schedule, alarm: alarm, title: "💊 \(alarm.name) – scan your \(alarm.objectName)")
    }

    /// A one-time alarm a few minutes from now (used for "ring again" and for testing).
    static func scheduleOneShot(for alarm: MedAlarm, after seconds: TimeInterval, title: String) async throws -> UUID {
        let id = UUID()
        try await submit(id: id, schedule: .fixed(Date().addingTimeInterval(seconds)), alarm: alarm, title: title)
        return id
    }

    private static func submit(id: UUID, schedule: Alarm.Schedule, alarm: MedAlarm, title: String) async throws {
        let scanButton = AlarmButton(text: "Scan", textColor: .white, systemImageName: "camera.fill")
        let stopButton = AlarmButton(text: "Stop", textColor: .white, systemImageName: "xmark")

        // The stopButton initializer is deprecated from iOS 26.1 (the system now draws its own
        // stop control) but it still works everywhere, so we keep it for iOS 26.0 support.
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            stopButton: stopButton,
            secondaryButton: scanButton,
            secondaryButtonBehavior: .custom
        )

        let attributes = AlarmAttributes<PillSnapAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: PillSnapAlarmMetadata(),
            tintColor: Color.teal
        )

        let configuration = Configuration(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopMedicineAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: ScanMedicineIntent(alarmID: id.uuidString)
        )

        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }
}
