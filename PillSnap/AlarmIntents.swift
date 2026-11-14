import AppIntents
import AlarmKit

/// Runs when the person uses the system Stop control on the ringing alarm.
/// The alarm goes quiet, but a follow-up alarm is queued so it rings again
/// in a couple of minutes until the photo is verified.
struct StopMedicineAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop medicine alarm"
    static let isDiscoverable = false

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            await AlarmStore.shared.alarmSilenced(kitID: id, openVerification: false)
        }
        return .result()
    }
}

/// Runs when the person taps "Scan" on the ringing alarm: opens the app on the camera screen.
struct ScanMedicineIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Scan item"
    static let isDiscoverable = false
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            await AlarmStore.shared.alarmSilenced(kitID: id, openVerification: true)
        }
        return .result()
    }
}
