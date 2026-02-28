import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var isBiometricLoading = false
    @State private var errorMessage: String?

    // Animation states
    @State private var logoAppeared = false
    @State private var formAppeared = false
    @State private var ringRotation: Double = 0
    @FocusState private var focusedField: Field?

    // Haptic triggers (#5)
    @State private var loginResult: LoginResult?
    @State private var showSettings = false

    private enum Field: Hashable { case username, password }
    private enum LoginResult { case success, failure }

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")

    // Scaled metrics for Dynamic Type (#6)
    @ScaledMetric(relativeTo: .body) private var fieldIconSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .title) private var logoSize: CGFloat = 140

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: max(geo.size.height * 0.08, 40))

                    logoSection
                        .padding(.bottom, 40)

                    loginCard
                        .padding(.horizontal, 28)

                    Spacer()
                        .frame(height: 40)

                    Text("Practice Manager")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [navy, Color(red: 0.04, green: 0.10, blue: 0.20)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    backgroundRings
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                                .foregroundColor(gold)
                        }
                    }
            }
            .environmentObject(authService)
        }
        // #5: haptic feedback
        .sensoryFeedback(.success, trigger: loginResult) { _, new in new == .success }
        .sensoryFeedback(.error, trigger: loginResult) { _, new in new == .failure }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                logoAppeared = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                formAppeared = true
            }
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            if Config.biometricLoginEnabled && BiometricService.hasStoredCredentials {
                biometricSignIn()
            }
        }
    }

    // MARK: - Background Rings

    private var backgroundRings: some View {
        ZStack {
            Circle()
                .stroke(gold.opacity(0.04), lineWidth: 1)
                .frame(width: 500, height: 500)
                .rotationEffect(.degrees(ringRotation))

            Circle()
                .stroke(gold.opacity(0.06), lineWidth: 0.5)
                .frame(width: 650, height: 650)
                .rotationEffect(.degrees(-ringRotation * 0.7))

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [gold.opacity(0.08), .clear, gold.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
                .frame(width: 350, height: 350)
                .rotationEffect(.degrees(ringRotation * 0.5))
        }
        .offset(y: -80)
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 16) {
            Image("OpusLogo")
                .resizable()
                .scaledToFit()
                .frame(width: min(logoSize, 180), height: min(logoSize, 180)) // #6, #18
                .shadow(color: gold.opacity(0.3), radius: 20, y: 4)
                .scaleEffect(logoAppeared ? 1 : 0.6)
                .opacity(logoAppeared ? 1 : 0)
                .accessibilityLabel("Opus Accountancy logo") // #1
                .onTapGesture(count: 2) {
                    showSettings = true
                }
        }
    }

    // MARK: - Login Card

    private var loginCard: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Welcome Back")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                Text("Sign in to manage your clients")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6)) // #12: raised from 0.5
            }
            .padding(.top, 8)

            VStack(spacing: 14) {
                customField(
                    icon: "person.fill",
                    placeholder: "Username",
                    text: $username,
                    field: .username,
                    isSecure: false
                )

                customField(
                    icon: "lock.fill",
                    placeholder: "Password",
                    text: $password,
                    field: .password,
                    isSecure: true
                )
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                focusedField = nil
                signIn()
            } label: {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .tint(navy)
                    } else {
                        Text("Sign In")
                            .font(.headline)
                            .foregroundColor(navy)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight) // #6
                .background(
                    LinearGradient(
                        colors: [gold, gold.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: gold.opacity(0.3), radius: 8, y: 4)
            }
            .disabled(username.isEmpty || password.isEmpty || isLoading)
            .opacity(username.isEmpty || password.isEmpty ? 0.6 : 1)
            .accessibilityLabel("Sign In") // #1
            .accessibilityHint("Double tap to sign in to your account") // #1

            if Config.biometricLoginEnabled && BiometricService.hasStoredCredentials {
                Button {
                    biometricSignIn()
                } label: {
                    HStack(spacing: 8) {
                        if isBiometricLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: BiometricService.systemImageName)
                            Text("Sign in with \(BiometricService.displayName)")
                        }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.3), lineWidth: 1.5)
                    )
                }
                .disabled(isBiometricLoading)
                .accessibilityLabel("Sign in with \(BiometricService.displayName)")
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .white.opacity(0.05), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .offset(y: formAppeared ? 0 : 30)
        .opacity(formAppeared ? 1 : 0)
    }

    // MARK: - Custom Text Field

    private func customField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        isSecure: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: fieldIconSize, weight: .medium)) // #6
                .foregroundColor(focusedField == field ? gold : .white.opacity(0.4))
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: focusedField)
                .accessibilityHidden(true) // #1: decorative, label comes from field

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                        .focused($focusedField, equals: field)
                        .textContentType(.password)
                        .submitLabel(.go) // #9
                        .onSubmit { signIn() } // #9
                } else {
                    TextField(placeholder, text: text)
                        .focused($focusedField, equals: field)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.next) // #9
                        .onSubmit { focusedField = .password } // #9
                }
            }
            .font(.body) // #6: uses text style
            .foregroundColor(.white)
            .tint(gold)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: fieldHeight) // #6: minHeight instead of fixed
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white.opacity(focusedField == field ? 0.12 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(focusedField == field ? gold.opacity(0.5) : .clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: focusedField)
    }

    // MARK: - Actions

    private func signIn() {
        guard !username.isEmpty, !password.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.login(username: username, password: password)
                loginResult = .success // #5
            } catch {
                withAnimation(.spring(response: 0.3)) {
                    errorMessage = error.localizedDescription
                }
                loginResult = .failure // #5
            }
            isLoading = false
        }
    }

    private func biometricSignIn() {
        guard !isBiometricLoading else { return }
        isBiometricLoading = true
        errorMessage = nil

        Task {
            do {
                try await authService.attemptBiometricLogin()
                loginResult = .success
            } catch is CancellationError {
                // User cancelled — no error message
            } catch BiometricError.cancelled {
                // User cancelled — no error message
            } catch {
                withAnimation(.spring(response: 0.3)) {
                    errorMessage = error.localizedDescription
                }
                loginResult = .failure
            }
            isBiometricLoading = false
        }
    }
}
