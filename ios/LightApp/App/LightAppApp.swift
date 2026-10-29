//
//  LightAppApp.swift
//  LightApp
//
//  App entry point: creates the data layer once, injects it into the
//  environment, and mirrors the Android Activity lifecycle hooks
//  (onStart -> onAppForeground, onStop -> onAppBackground).
//

import SwiftUI

// MARK: - SecureStorage environment plumbing

/// SecureStorage is a plain (non-@Observable) data-layer store, so it rides in
/// the environment through a classic EnvironmentKey rather than
/// `.environment(_:)`'s Observable overload.
private struct SecureStorageKey: EnvironmentKey {
    static let defaultValue = SecureStorage()
}

extension EnvironmentValues {
    var secureStorage: SecureStorage {
        get { self[SecureStorageKey.self] }
        set { self[SecureStorageKey.self] = newValue }
    }
}

// MARK: - App

@main
struct LightAppApp: App {
    private let storage: SecureStorage
    @State private var repository: WalletRepository
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let storage = SecureStorage()
        self.storage = storage
        _repository = State(initialValue: WalletRepository(storage: storage))
    }

    var body: some Scene {
        WindowGroup {
            AppRoot(repository: repository)
                .environment(repository)
                .environment(\.secureStorage, storage)
                // iOS analogue of FLAG_SECURE Recents blanking: blank the app
                // switcher snapshot whenever the scene is not active.
                .privacyCover()
                // Dark-only design.
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                repository.onAppForeground()
            case .background:
                repository.onAppBackground()
            default:
                break
            }
        }
    }
}
