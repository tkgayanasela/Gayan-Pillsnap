import SwiftUI
import UIKit

struct AlarmEditView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.dismiss) private var dismiss

    private let existingID: UUID?
    /// ID used when saving (stays the same if the first save attempt fails).
    @State private var draftID: UUID

    @State private var name = "Morning medicine"
    @State private var objectName = "Medicine box"
    @State private var time = AlarmEditView.defaultTime
    @State private var days: Set<Weekday> = Set(Weekday.allCases)
    @State private var strictness: Strictness = .normal
    @State private var photos: [RefPhoto] = []
    @State private var loaded = false

    @State private var picker: PickerRequest?
    @State private var testResult: MatchResult?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var testScheduled = false

    private static let maxPhotos = 3

    struct RefPhoto: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    enum PickerRequest: String, Identifiable {
        case referenceCamera, referenceLibrary, testCamera
        var id: String { rawValue }
    }

    init(existingID: UUID?) {
        self.existingID = existingID
        _draftID = State(initialValue: existingID ?? UUID())
    }

    private static var defaultTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var isExisting: Bool { store.alarm(withID: draftID) != nil }

    private var canSave: Bool {
        !photos.isEmpty && !days.isEmpty && !isWorking
    }

    var body: some View {
        Form {
            Section("Alarm") {
                TextField("Name, e.g. Morning medicine", text: $name)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repeat")
                    DayPicker(days: $days)
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField("What is it? e.g. Medicine box", text: $objectName)
                photoStrip
            } header: {
                Text("What you'll photograph to stop it")
            } footer: {
                Text("Take 2–3 photos from slightly different angles. Put the object in the middle and let it fill most of the picture. Boxes with printed names work best.")
            }

            Section {
                Picker("Matching", selection: $strictness) {
                    ForEach(Strictness.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    picker = .testCamera
                } label: {
                    Label("Test recognition now", systemImage: "camera.viewfinder")
                }
                .disabled(photos.isEmpty)

                if let testResult {
                    MatchResultView(result: testResult)
                }
            } header: {
                Text("Recognition")
            } footer: {
                Text("Test with the real object and with something else. If the real one fails, use Relaxed or add another reference photo. If other things pass, use Strict.")
            }

            if isExisting {
                Section {
                    Button {
                        Task {
                            await store.ringTest(draftID)
                            testScheduled = store.lastError == nil
                        }
                    } label: {
                        Label(testScheduled ? "Test alarm set – it rings in about 1 minute" : "Ring a test alarm in 1 minute",
                              systemImage: "alarm")
                    }
                    .disabled(testScheduled)

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete alarm", systemImage: "trash")
                    }
                } footer: {
                    Text("The test uses the saved settings. Lock your phone and wait for it to ring.")
                }
            }
        }
        .navigationTitle(existingID == nil ? "New alarm" : "Edit alarm")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await save() }
                }
                .disabled(!canSave)
            }
        }
        .onAppear(perform: loadIfNeeded)
        .fullScreenCover(item: $picker) { request in
            CameraPicker(
                source: request == .referenceLibrary ? .library : .camera,
                onImage: { image in handlePicked(image, for: request) },
                onCancel: { picker = nil }
            )
            .ignoresSafeArea()
        }
        .confirmationDialog("Delete this alarm?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(draftID)
                dismiss()
            }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if isWorking {
                ProgressView("Working…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Button {
                            photos.removeAll { $0.id == photo.id }
                            testResult = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.6))
                        }
                        .buttonStyle(.borderless)
                        .padding(4)
                        .accessibilityLabel("Remove photo")
                    }
                }

                if photos.count < Self.maxPhotos {
                    Menu {
                        Button {
                            picker = .referenceCamera
                        } label: {
                            Label("Take photo", systemImage: "camera")
                        }
                        Button {
                            picker = .referenceLibrary
                        } label: {
                            Label("Choose from library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                            Text(photos.isEmpty ? "Add photo" : "Add another")
                                .font(.caption.weight(.medium))
                        }
                        .frame(width: 96, height: 96)
                        .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                        .foregroundStyle(.teal)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let id = existingID, let alarm = store.alarm(withID: id) else { return }
        name = alarm.name
        objectName = alarm.objectName
        time = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: Date()) ?? time
        days = alarm.days
        strictness = alarm.strictness
        photos = alarm.referencePhotos.compactMap { ImageStore.load($0) }.map { RefPhoto(image: $0) }
    }

    private func handlePicked(_ image: UIImage, for request: PickerRequest) {
        picker = nil
        let normalized = ImageStore.normalized(image)
        switch request {
        case .referenceCamera, .referenceLibrary:
            if photos.count < Self.maxPhotos {
                photos.append(RefPhoto(image: normalized))
                testResult = nil
            }
        case .testCamera:
            runTest(with: normalized)
        }
    }

    private func runTest(with image: UIImage) {
        isWorking = true
        let references = photos.compactMap { $0.image.cgImage }
        let candidate = image.cgImage
        let level = strictness
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                ObjectMatcher.compare(candidate: candidate, references: references, referenceWords: nil, strictness: level)
            }.value
            testResult = result
            isWorking = false
        }
    }

    private func save() async {
        guard canSave else { return }
        isWorking = true
        defer { isWorking = false }

        let references = photos.compactMap { $0.image.cgImage }
        let words = await Task.detached(priority: .userInitiated) {
            ObjectMatcher.words(inAll: references)
        }.value

        var alarm = store.alarm(withID: draftID) ?? MedAlarm(id: draftID)
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedObject = objectName.trimmingCharacters(in: .whitespacesAndNewlines)
        alarm.name = trimmedName.isEmpty ? "Medicine" : trimmedName
        alarm.objectName = trimmedObject.isEmpty ? "item" : trimmedObject
        alarm.hour = components.hour ?? 8
        alarm.minute = components.minute ?? 0
        alarm.days = days
        alarm.strictness = strictness
        alarm.referenceWords = words.sorted()

        do {
            alarm.referencePhotos = try photos.map { try ImageStore.save($0.image) }
        } catch {
            errorMessage = "Couldn't save the photos: \(error.localizedDescription)"
            return
        }

        if let message = await store.upsert(alarm) {
            errorMessage = message
            return
        }
        dismiss()
    }
}

struct DayPicker: View {
    @Binding var days: Set<Weekday>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.ordered) { day in
                let isOn = days.contains(day)
                Button {
                    if isOn {
                        if days.count > 1 { days.remove(day) }
                    } else {
                        days.insert(day)
                    }
                } label: {
                    Text(day.twoLetter)
                        .font(.footnote.weight(.semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(isOn ? Color.teal : Color(.secondarySystemFill)))
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(day.short)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MatchResultView: View {
    let result: MatchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(result.isMatch ? "Match – this photo would stop the alarm" : "No match – the alarm would keep ringing",
                  systemImage: result.isMatch ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(result.isMatch ? Color.green : Color.red)
            if !result.details.isEmpty {
                Text(result.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
