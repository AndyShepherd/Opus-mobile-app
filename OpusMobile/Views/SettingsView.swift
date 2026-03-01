import SwiftUI

/// Settings screen. In DEBUG builds: full server picker, SSL toggle, and biometric toggle.
/// In RELEASE builds: only the biometric toggle is shown (server is locked to production).
struct SettingsView: View {
    @EnvironmentObject private var authService: AuthService

    // Server settings are DEBUG-only — compiled out of release builds entirely
    #if DEBUG
    @State private var selectedEnvironment = Config.selectedEnvironment
    @State private var customURL = Config.customURL
    @State private var skipSSL = Config.skipSSLValidation
    #endif
    @State private var biometricEnabled = Config.biometricLoginEnabled
    @State private var timeoutMinutes = Config.sessionTimeoutMinutes
    @State private var showSaved = false

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")

    var body: some View {
        Form {
            #if DEBUG
            Section {
                Picker("Environment", selection: $selectedEnvironment) {
                    ForEach(ServerEnvironment.availableCases) { env in
                        Text(env.rawValue).tag(env)
                    }
                }

                if selectedEnvironment == .custom {
                    TextField("https://api.example.com", text: $customURL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    HStack {
                        Text("URL")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(selectedEnvironment.defaultURL)
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                Toggle("Skip SSL Validation", isOn: $skipSSL)
            } header: {
                Text("API Server")
            } footer: {
                Text("Changing the server requires signing in again. Enable Skip SSL for servers with self-signed certificates.")
            }
            #endif

            Section {
                if BiometricService.isAvailable {
                    Toggle(
                        "Sign in with \(BiometricService.displayName)",
                        isOn: $biometricEnabled
                    )
                }

                Picker("Auto-Lock Timeout", selection: $timeoutMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                }
            } header: {
                Text("Security")
            } footer: {
                if BiometricService.isAvailable {
                    Text("Use \(BiometricService.displayName) to sign in quickly. The app locks after \(timeoutMinutes) minute\(timeoutMinutes == 1 ? "" : "s") of inactivity.")
                } else {
                    Text("The app locks after \(timeoutMinutes) minute\(timeoutMinutes == 1 ? "" : "s") of inactivity.")
                }
            }

            Section {
                Button("Save") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(gold)
            }

            #if DEBUG
            Section {
                HStack {
                    Text("Current Server")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Config.apiBaseURL)
                        .font(.caption)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
            } header: {
                Text("Active Connection")
            }
            #endif
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Saved", isPresented: $showSaved) {
            Button("OK") {}
        } message: {
            Text("Settings have been saved.")
        }
    }

    private func save() {
        #if DEBUG
        // Detect server changes so we can force re-auth if the server endpoint changed
        let serverChanged = selectedEnvironment != Config.selectedEnvironment
            || skipSSL != Config.skipSSLValidation
            || (selectedEnvironment == .custom && customURL != Config.customURL)

        Config.selectedEnvironment = selectedEnvironment
        Config.skipSSLValidation = skipSSL
        if selectedEnvironment == .custom {
            Config.customURL = customURL
        }
        #endif

        let biometricChanged = biometricEnabled != Config.biometricLoginEnabled
        Config.biometricLoginEnabled = biometricEnabled
        Config.sessionTimeoutMinutes = timeoutMinutes
        // Clear stored credentials when biometric is disabled so they don't linger in the Keychain
        if biometricChanged && !biometricEnabled {
            BiometricService.clearAll()
        }

        #if DEBUG
        // Changing server while authenticated requires logout — the token is for the old server
        if serverChanged && authService.isAuthenticated {
            authService.logout()
            showSaved = true
        } else if biometricChanged || serverChanged {
            showSaved = true
        }
        #else
        if biometricChanged {
            showSaved = true
        }
        #endif
    }
}
