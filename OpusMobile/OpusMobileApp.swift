import SwiftUI

@main
struct OpusMobileApp: App {
    // Single source of truth for auth state — shared via .environmentObject to all views
    @StateObject private var authService = AuthService()
    @StateObject private var sessionManager = SessionManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showPrivacyOverlay = false

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

                // Privacy overlay hides sensitive data from the iOS task switcher snapshot
                if showPrivacyOverlay {
                    Color("NavyBlue")
                        .ignoresSafeArea()
                        .overlay {
                            Image("OpusLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120)
                        }
                        .transition(.opacity)
                        .zIndex(2)
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
                switch newPhase {
                case .active:
                    showPrivacyOverlay = false
                    guard authService.isAuthenticated else { return }
                    sessionManager.appWillEnterForeground()
                    Task { await authService.checkTokenOnForeground() }
                case .background:
                    showPrivacyOverlay = true
                    guard authService.isAuthenticated else { return }
                    sessionManager.appDidEnterBackground()
                case .inactive:
                    // Show overlay on inactive too — iOS takes the snapshot during this phase
                    showPrivacyOverlay = true
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
