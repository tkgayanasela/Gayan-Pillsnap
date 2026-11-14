import SwiftUI
import AlarmKit
import UIKit

/// The app's brain: saved alarms, which doses are waiting for a photo, and the
/// "keep ringing until verified" logic.
@MainActor
final class AlarmStore: ObservableObject {
    static let shared = AlarmStore()

    @Published private(set) var state: AppState
    @Published var activeVerification: VerificationRequest?
    @Published private(set) var authorization: AlarmManager.AuthorizationState = .notDetermined
    @Published var lastError: String?

    /// True while the app is on screen.
    var isForeground = false

    private var observeTask: Task<Void, Never>?
    private var handling: Set<UUID> = []
    private var isReconciling = false

    private static var stateURL: URL {
        let directory = URL.applicationSupportDirectory.appending(path: "PillSnap", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "state.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.stateURL),
           let decoded = try? JSONDecoder().decode(AppState.self, from: data) {
            state = decoded
        } else {
            state = AppState()
        }
        authorization = AlarmScheduler.authorizationState
    }

    // MARK: - Lookups

    var sortedAlarms: [MedAlarm] {
        state.alarms.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func alarm(withID id: UUID) -> MedAlarm? {
        state.alarms.first { $0.id == id }
    }

    /// Maps an AlarmKit alarm (main or "ring again") back to the medicine alarm it belongs to.
    func parentID(forKitID id: UUID) -> UUID? {
        if alarm(withID: id) != nil { return id }
        return state.reminders[id.uuidString]
    }

    func isPending(_ id: UUID) -> Bool {
        state.pending[id.uuidString] != nil
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(state)
            try data.write(to: Self.stateURL, options: .atomic)
        } catch {
            print("PillSnap: failed to save state: \(error)")
        }
    }

    // MARK: - Ringing alarm handling

    /// Called when a ringing alarm was silenced (system Stop, our Scan button, or the app taking over).
    /// The dose becomes "pending" and a follow-up alarm is queued, so it keeps coming back
    /// every few minutes until a matching photo is taken.
    func alarmSilenced(kitID: UUID, openVerification: Bool) async {
        AlarmScheduler.stopIfAlerting(kitID)
        guard let parent = parentID(forKitID: kitID), let alarm = self.alarm(withID: parent) else {
            return
        }
        state.reminders.removeValue(forKey: kitID.uuidString)
        if openVerification {
            activeVerification = VerificationRequest(id: parent)
        }

        guard !handling.contains(parent) else { return }
        handling.insert(parent)
        defer { handling.remove(parent) }

        if state.pending[parent.uuidString] == nil {
            state.pending[parent.uuidString] = Date()
        }
        persist()
        await scheduleFollowUp(for: alarm)
    }

    private func scheduleFollowUp(for alarm: MedAlarm) async {
        cancelReminders(for: alarm.id)
        do {
            let id = try await AlarmScheduler.scheduleOneShot(
                for: alarm,
                after: TimeInterval(state.repeatMinutes * 60),
                title: "⏰ Still waiting – scan your \(alarm.objectName)"
            )
            state.reminders[id.uuidString] = alarm.id
            persist()
        } catch {
            lastError = "Couldn't schedule the follow-up alarm: \(error.localizedDescription)"
        }
    }

    private func cancelReminders(for parent: UUID) {
        for (key, value) in state.reminders where value == parent {
            if let id = UUID(uuidString: key) {
                AlarmScheduler.cancel(id)
            }
            state.reminders.removeValue(forKey: key)
        }
        persist()
    }

    /// Runs the photo check for a medicine alarm.
    func verify(_ image: UIImage, for alarmID: UUID) async -> MatchResult {
        guard let alarm = self.alarm(withID: alarmID) else {
            return .failure("This alarm no longer exists.")
        }
        let references = alarm.referencePhotos.compactMap { ImageStore.load($0)?.cgImage }
        let candidate = ImageStore.normalized(image).cgImage
        let words = alarm.referenceWords
        let strictness = alarm.strictness
        return await Task.detached(priority: .userInitiated) {
            ObjectMatcher.compare(candidate: candidate, references: references, referenceWords: words, strictness: strictness)
        }.value
    }

    /// The photo matched (or the dose was deliberately skipped): stop everything and log it.
    func resolve(_ alarmID: UUID, outcome: DoseLog.Outcome) {
        let rangAt = state.pending[alarmID.uuidString] ?? Date()
        cancelReminders(for: alarmID)
        AlarmScheduler.stopIfAlerting(alarmID)
        state.pending.removeValue(forKey: alarmID.uuidString)
        let name = alarm(withID: alarmID)?.name ?? "Medicine"
        state.logs.insert(
            DoseLog(alarmID: alarmID, alarmName: name, rangAt: rangAt, resolvedAt: Date(), outcome: outcome),
            at: 0
        )
        if state.logs.count > 100 {
            state.logs.removeLast(state.logs.count - 100)
        }
        persist()
    }

    /// Closes the scan screen, or moves on to the next dose that is still waiting.
    func finishVerification() {
        let next = state.pending.keys
            .compactMap(UUID.init(uuidString:))
            .first { alarm(withID: $0) != nil }
        activeVerification = next.map { VerificationRequest(id: $0) }
    }

    // MARK: - Editing alarms

    /// Saves an alarm and (re)schedules it. Returns an error message, or nil on success.
    @discardableResult
    func upsert(_ alarm: MedAlarm) async -> String? {
        let previous = self.alarm(withID: alarm.id)
        if let index = state.alarms.firstIndex(where: { $0.id == alarm.id }) {
            state.alarms[index] = alarm
        } else {
            state.alarms.append(alarm)
        }
        persist()

        if let previous {
            ImageStore.delete(previous.referencePhotos.filter { !alarm.referencePhotos.contains($0) })
        }

        AlarmScheduler.cancel(alarm.id)
        guard alarm.isEnabled else {
            clearPending(for: alarm.id)
            return nil
        }
        return await scheduleMain(alarm)
    }

    private func scheduleMain(_ alarm: MedAlarm) async -> String? {
        let allowed = await AlarmScheduler.requestAuthorization()
        authorization = AlarmScheduler.authorizationState
        guard allowed else {
            return "PillSnap isn't allowed to set alarms. Turn on alarms for PillSnap in the Settings app, then open PillSnap again."
        }
        do {
            try await AlarmScheduler.scheduleRepeating(alarm)
            return nil
        } catch {
            return "Couldn't schedule the alarm: \(error.localizedDescription)"
        }
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) async {
        guard var alarm = self.alarm(withID: id) else { return }
        alarm.isEnabled = enabled
        if let message = await upsert(alarm) {
            lastError = message
        }
    }

    func delete(_ id: UUID) {
        guard let alarm = self.alarm(withID: id) else { return }
        AlarmScheduler.cancel(id)
        clearPending(for: id)
        ImageStore.delete(alarm.referencePhotos)
        state.alarms.removeAll { $0.id == id }
        persist()
    }

    private func clearPending(for id: UUID) {
        cancelReminders(for: id)
        state.pending.removeValue(forKey: id.uuidString)
        if activeVerification?.id == id {
            finishVerification()
        }
        persist()
    }

    func setRepeatMinutes(_ minutes: Int) {
        state.repeatMinutes = minutes
        persist()
    }

    func requestAuthorization() async {
        _ = await AlarmScheduler.requestAuthorization()
        authorization = AlarmScheduler.authorizationState
        await reconcile()
    }

    /// Rings this alarm once in 60 seconds so the whole flow can be tried out.
    func ringTest(_ id: UUID) async {
        guard let alarm = self.alarm(withID: id) else { return }
        guard await AlarmScheduler.requestAuthorization() else {
            authorization = AlarmScheduler.authorizationState
            lastError = "PillSnap isn't allowed to set alarms. Turn on alarms for PillSnap in the Settings app."
            return
        }
        do {
            let kitID = try await AlarmScheduler.scheduleOneShot(for: alarm, after: 60, title: "🧪 Test – scan your \(alarm.objectName)")
            state.reminders[kitID.uuidString] = alarm.id
            persist()
        } catch {
            lastError = "Couldn't schedule the test alarm: \(error.localizedDescription)"
        }
    }

    // MARK: - Keeping AlarmKit in sync

    func startObserving() {
        guard observeTask == nil else { return }
        observeTask = Task { [weak self] in
            for await alarms in AlarmManager.shared.alarmUpdates {
                guard let self else { return }
                await self.handleUpdate(alarms)
            }
        }
    }

    /// If one of our alarms starts ringing while the app is open, the app takes over:
    /// it silences the system alert and shows the scan screen (which rings in-app).
    private func handleUpdate(_ alarms: [Alarm]) async {
        guard isForeground else { return }
        for alarm in alarms where alarm.state == .alerting && parentID(forKitID: alarm.id) != nil {
            await alarmSilenced(kitID: alarm.id, openVerification: true)
        }
    }

    /// Called whenever the app comes to the front.
    func reconcile() async {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        authorization = AlarmScheduler.authorizationState
        let kitAlarms = AlarmScheduler.currentAlarms()
        let kitIDs = Set(kitAlarms.map(\.id))

        // Forget follow-up alarms that already rang or were removed.
        for key in state.reminders.keys {
            if let id = UUID(uuidString: key), !kitIDs.contains(id) {
                state.reminders.removeValue(forKey: key)
            }
        }

        if authorization == .authorized {
            // Make AlarmKit match the saved alarms.
            for alarm in state.alarms {
                if alarm.isEnabled && !kitIDs.contains(alarm.id) {
                    try? await AlarmScheduler.scheduleRepeating(alarm)
                } else if !alarm.isEnabled && kitIDs.contains(alarm.id) {
                    AlarmScheduler.cancel(alarm.id)
                }
            }
            // Remove AlarmKit alarms we no longer know about.
            let known = Set(state.alarms.map(\.id))
                .union(state.reminders.keys.compactMap(UUID.init(uuidString:)))
            for kitAlarm in kitAlarms where !known.contains(kitAlarm.id) {
                AlarmScheduler.cancel(kitAlarm.id)
            }
        }

        // Every dose that is still waiting must have a follow-up alarm queued.
        for key in state.pending.keys {
            guard let id = UUID(uuidString: key), let alarm = self.alarm(withID: id), alarm.isEnabled else {
                if let id = UUID(uuidString: key) { cancelReminders(for: id) }
                state.pending.removeValue(forKey: key)
                continue
            }
            if !state.reminders.values.contains(id) && !handling.contains(id) {
                await scheduleFollowUp(for: alarm)
            }
        }
        persist()

        // An alarm is ringing right now and the app is open: take over.
        if isForeground {
            for kitAlarm in kitAlarms where kitAlarm.state == .alerting && parentID(forKitID: kitAlarm.id) != nil {
                await alarmSilenced(kitID: kitAlarm.id, openVerification: true)
            }
        }

        if activeVerification == nil {
            finishVerification()
        }
    }
}
