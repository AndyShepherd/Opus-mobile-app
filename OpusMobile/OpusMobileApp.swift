import SwiftUI

@main
struct OpusMobileApp: App {
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            ZStack {
                if authService.isAuthenticated {
                    ClientListView()
                        .transition(.opacity)
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: authService.isAuthenticated)
            .environmentObject(authService)
            .task {
                await authService.checkAuth()
            }
        }
    }
}
