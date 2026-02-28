import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var selectedEnvironment = Config.selectedEnvironment
    @State private var customURL = Config.customURL
    @State private var skipSSL = Config.skipSSLValidation
    @State private var biometricEnabled = Config.biometricLoginEnabled
    @State private var showSaved = false

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")

    var body: some View {
        Form {
            Section {
                Picker("Environment", selection: $selectedEnvironment) {
                    ForEach(ServerEnvironment.allCases) { env in
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

            if BiometricService.isAvailable {
                Section {
                    Toggle(
                        "Sign in with \(BiometricService.displayName)",
                        isOn: $biometricEnabled
                    )
                } header: {
                    Text("Security")
                } footer: {
                    Text("Use \(BiometricService.displayName) to quickly sign in on future launches.")
                }
            }

            Section {
                Button("Save") {
                    save()
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(gold)
            }

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
        let serverChanged = selectedEnvironment != Config.selectedEnvironment
            || skipSSL != Config.skipSSLValidation
            || (selectedEnvironment == .custom && customURL != Config.customURL)

        Config.selectedEnvironment = selectedEnvironment
        Config.skipSSLValidation = skipSSL
        if selectedEnvironment == .custom {
            Config.customURL = customURL
        }

        // Handle biometric toggle
        let biometricChanged = biometricEnabled != Config.biometricLoginEnabled
        Config.biometricLoginEnabled = biometricEnabled
        if biometricChanged && !biometricEnabled {
            BiometricService.clearAll()
        }

        if serverChanged && authService.isAuthenticated {
            authService.logout()
            showSaved = true
        } else if biometricChanged || serverChanged {
            showSaved = true
        }
    }
}
