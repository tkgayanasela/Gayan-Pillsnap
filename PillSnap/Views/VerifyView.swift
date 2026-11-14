import SwiftUI
import UIKit

/// Full-screen "scan to stop" screen. It rings until a matching photo is taken.
struct VerifyView: View {
    let alarmID: UUID

    @EnvironmentObject private var store: AlarmStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage = .ready
    @State private var showCamera = false
    @State private var referenceImage: UIImage?
    @State private var holdingSkip = false

    enum Stage: Equatable {
        case ready
        case checking
        case failed(MatchResult)
        case success(Date)
    }

    private var alarm: MedAlarm? { store.alarm(withID: alarmID) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.30, blue: 0.33), Color(red: 0.03, green: 0.07, blue: 0.16)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if let alarm {
                content(for: alarm)
                    .padding(24)
            } else {
                VStack(spacing: 16) {
                    Text("This alarm was deleted.")
                        .font(.title3)
                    Button("Close") { store.finishVerification() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                source: .camera,
                onImage: { image in
                    showCamera = false
                    check(image)
                },
                onCancel: {
                    showCamera = false
                    startRingingIfNeeded()
                }
            )
            .ignoresSafeArea()
        }
        .onAppear {
            referenceImage = alarm?.referencePhotos.first.flatMap { ImageStore.load($0) }
            startRingingIfNeeded()
        }
        .onDisappear {
            RingPlayer.shared.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startRingingIfNeeded()
            } else if phase == .background {
                RingPlayer.shared.stop()
            }
        }
    }

    @ViewBuilder
    private func content(for alarm: MedAlarm) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            switch stage {
            case .success(let date):
                successView(alarm: alarm, at: date)
            default:
                header(alarm: alarm)
                referenceCard(alarm: alarm)

                if case .failed(let result) = stage {
                    failureCard(result)
                }

                Button {
                    RingPlayer.shared.stop()
                    showCamera = true
                } label: {
                    Label(stage == .checking ? "Checking…" : "Open camera", systemImage: "camera.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Capsule().fill(Color.white))
                        .foregroundStyle(Color(red: 0.02, green: 0.30, blue: 0.33))
                }
                .disabled(stage == .checking)
                .overlay {
                    if stage == .checking {
                        ProgressView().tint(.teal)
                    }
                }
            }

            Spacer(minLength: 0)

            if !isSuccess {
                skipControl(alarm: alarm)
            }
        }
    }

    private var isSuccess: Bool {
        if case .success = stage { return true }
        return false
    }

    private func header(alarm: MedAlarm) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "alarm.waves.left.and.right.fill")
                .font(.system(size: 44))
                .symbolEffect(.pulse, options: .repeating)
            Text(alarm.name)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Take a photo of your \(alarm.objectName) to turn the alarm off.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    private func referenceCard(alarm: MedAlarm) -> some View {
        VStack(spacing: 8) {
            if let referenceImage {
                Image(uiImage: referenceImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 170, height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.4), lineWidth: 1))
            }
            Text("Fill the frame with it, like this one, in good light.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func failureCard(_ result: MatchResult) -> some View {
        VStack(spacing: 6) {
            Label("That doesn't look like your item yet", systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.5))
            Text("Move closer, center it, and try again.")
                .font(.subheadline)
            if !result.details.isEmpty {
                Text(result.details)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.1)))
    }

    private func successView(alarm: MedAlarm, at date: Date) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 96))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: date)
            Text("Alarm off")
                .font(.largeTitle.weight(.bold))
            Text("Take your medicine now 💊")
                .font(.title3)
            Text("Logged at \(date.formatted(date: .omitted, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Button {
                store.finishVerification()
            } label: {
                Text("Done")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(Color.white))
                    .foregroundStyle(Color(red: 0.02, green: 0.30, blue: 0.33))
            }
            .padding(.top, 12)
        }
    }

    private func skipControl(alarm: MedAlarm) -> some View {
        Text(holdingSkip ? "Keep holding to skip this dose…" : "Away from your \(alarm.objectName)? Hold here for 3 seconds to skip this dose.")
            .font(.footnote)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(holdingSkip ? 1 : 0.6))
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Capsule().fill(.white.opacity(holdingSkip ? 0.25 : 0.08)))
            .scaleEffect(holdingSkip ? 1.05 : 1)
            .animation(.easeInOut(duration: 0.3), value: holdingSkip)
            .onLongPressGesture(minimumDuration: 3) {
                RingPlayer.shared.stop()
                store.resolve(alarmID, outcome: .skipped)
                store.finishVerification()
            } onPressingChanged: { pressing in
                holdingSkip = pressing
            }
    }

    // MARK: - Actions

    private func startRingingIfNeeded() {
        guard scenePhase == .active, !showCamera, !isSuccess, stage != .checking else { return }
        RingPlayer.shared.start()
    }

    private func check(_ image: UIImage) {
        stage = .checking
        Task {
            let result = await store.verify(image, for: alarmID)
            if result.isMatch {
                RingPlayer.shared.stop()
                store.resolve(alarmID, outcome: .taken)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                stage = .success(Date())
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                stage = .failed(result)
                startRingingIfNeeded()
            }
        }
    }
}
