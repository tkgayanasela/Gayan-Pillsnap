import SwiftUI

@main
struct PillSnapApp: App {
    @StateObject private var store = AlarmStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.teal)
        }
    }
}

/// Hosts the main screen and the full-screen "scan to stop" screen.
struct RootView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentView()
            .fullScreenCover(item: $store.activeVerification) { request in
                VerifyView(alarmID: request.id)
                    .environmentObject(store)
            }
            .task {
                store.startObserving()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                store.isForeground = (phase == .active)
                if phase == .active {
                    Task { await store.reconcile() }
                }
            }
    }
}
