import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var selectedEnvironment = Config.selectedEnvironment
    @State private var customURL = Config.customURL
    @State private var skipSSL = Config.skipSSLValidation
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
            Text("Server changed to \(Config.apiBaseURL). Please sign in again.")
        }
    }

    private func save() {
        Config.selectedEnvironment = selectedEnvironment
        Config.skipSSLValidation = skipSSL
        if selectedEnvironment == .custom {
            Config.customURL = customURL
        }
        if authService.isAuthenticated {
            authService.logout()
        }
        showSaved = true
    }
}
