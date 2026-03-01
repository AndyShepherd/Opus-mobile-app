import SwiftUI

@main
struct OpusMobileApp: App {
    // Single source of truth for auth state — shared via .environmentObject to all views
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            // ZStack allows cross-fade between login and client list
            ZStack {
                if authService.isAuthenticated {
                    ClientListView()
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            // Animates the auth state change so login/list cross-fade smoothly
            .animation(.easeInOut(duration: 0.35), value: authService.isAuthenticated)
            .environmentObject(authService)
            // .task (not .onAppear) so the async check runs once and cancels if the view disappears
            .task {
                await authService.checkAuth()
            }
        }
    }
}
