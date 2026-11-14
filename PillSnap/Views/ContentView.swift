import SwiftUI
import UIKit

enum Route: Hashable {
    case new
    case edit(UUID)
}

struct ContentView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.openURL) private var openURL
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                permissionSection

                if store.state.alarms.isEmpty {
                    Section {
                        EmptyStateView { path.append(.new) }
                    }
                } else {
                    Section("Alarms") {
                        ForEach(store.sortedAlarms) { alarm in
                            AlarmRow(alarm: alarm, isPending: store.isPending(alarm.id)) {
                                path.append(.edit(alarm.id))
                            }
                        }
                    }
                }

                Section {
                    Picker("Ring again every", selection: Binding(
                        get: { store.state.repeatMinutes },
                        set: { store.setRepeatMinutes($0) }
                    )) {
                        ForEach([1, 2, 3, 5], id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                } footer: {
                    Text("If you stop the alarm without scanning, it rings again after this many minutes – over and over until the photo matches.")
                }

                if !store.state.logs.isEmpty {
                    Section("Recent doses") {
                        ForEach(store.state.logs.prefix(10)) { log in
                            DoseLogRow(log: log)
                        }
                    }
                }
            }
            .navigationTitle("PillSnap")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        path.append(.new)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add alarm")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .new:
                    AlarmEditView(existingID: nil)
                case .edit(let id):
                    AlarmEditView(existingID: id)
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.lastError ?? "")
            }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        switch store.authorization {
        case .denied:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Alarms are turned off for PillSnap", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Your alarms can't ring until you allow them in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 4)
            }
        case .notDetermined where !store.state.alarms.isEmpty:
            Section {
                Button("Allow PillSnap to ring alarms") {
                    Task { await store.requestAuthorization() }
                }
            }
        default:
            EmptyView()
        }
    }
}

struct AlarmRow: View {
    @EnvironmentObject private var store: AlarmStore
    let alarm: MedAlarm
    let isPending: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    ThumbnailView(fileName: alarm.referencePhotos.first)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alarm.timeText)
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
                        Text(alarm.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(alarm.daysText) · scan \(alarm.objectName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isPending {
                            Label("Waiting for your photo", systemImage: "bell.badge.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)

            Toggle("Enabled", isOn: Binding(
                get: { alarm.isEnabled },
                set: { newValue in Task { await store.setEnabled(alarm.id, newValue) } }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct ThumbnailView: View {
    let fileName: String?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemFill))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "pills.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: fileName) {
            image = fileName.flatMap { ImageStore.load($0) }
        }
    }
}

struct DoseLogRow: View {
    let log: DoseLog

    var body: some View {
        HStack {
            Image(systemName: log.outcome == .taken ? "checkmark.circle.fill" : "forward.fill")
                .foregroundStyle(log.outcome == .taken ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(log.alarmName)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        let day = log.resolvedAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
        let resolved = log.resolvedAt.formatted(date: .omitted, time: .shortened)
        let rang = log.rangAt.formatted(date: .omitted, time: .shortened)
        let verb = log.outcome == .taken ? "Verified" : "Skipped"
        return "\(verb) at \(resolved) (rang \(rang)) · \(day)"
    }
}

struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Never forget your medicine")
                .font(.title3.weight(.semibold))
            step("1.circle.fill", "Set an alarm time, e.g. 8:00 am.")
            step("2.circle.fill", "Take 1–3 photos of the thing to scan, e.g. your medicine box.")
            step("3.circle.fill", "When the alarm rings, it only stops for good after you photograph that same thing.")
            Button(action: onAdd) {
                Label("Add your first alarm", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 8)
    }

    private func step(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.teal)
        }
    }
}
