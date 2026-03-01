import SwiftUI

@main
struct OpusMobileApp: App {
    // Single source of truth for auth state — shared via .environmentObject to all views
    @StateObject private var authService = AuthService()
    @StateObject private var sessionManager = SessionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // ZStack allows cross-fade between login, client list, and lock screen
            ZStack {
                if authService.isAuthenticated {
                    ClientListView()
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }

                if authService.isAuthenticated && sessionManager.isLocked {
                    LockScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            // Animates the auth state change so login/list cross-fade smoothly
            .animation(.easeInOut(duration: 0.35), value: authService.isAuthenticated)
            .animation(.easeInOut(duration: 0.35), value: sessionManager.isLocked)
            .overlay {
                if authService.isAuthenticated && !sessionManager.isLocked {
                    ActivityTrackingOverlay(sessionManager: sessionManager)
                        .allowsHitTesting(true)
                }
            }
            .environmentObject(authService)
            .environmentObject(sessionManager)
            // .task (not .onAppear) so the async check runs once and cancels if the view disappears
            .task {
                await authService.checkAuth()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard authService.isAuthenticated else { return }
                switch newPhase {
                case .active:
                    sessionManager.appWillEnterForeground()
                case .background:
                    sessionManager.appDidEnterBackground()
                case .inactive:
                    break  // Notification shade — don't lock prematurely
                @unknown default:
                    break
                }
            }
            .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated {
                    sessionManager.startMonitoring()
                } else {
                    sessionManager.stopMonitoring()
                    sessionManager.isLocked = false
                }
            }
        }
    }
}
