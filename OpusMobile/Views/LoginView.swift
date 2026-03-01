import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var isBiometricLoading = false
    @State private var errorMessage: String?

    // Animation states for the staggered entrance effect
    @State private var logoAppeared = false
    @State private var formAppeared = false
    @State private var ringRotation: Double = 0
    @FocusState private var focusedField: Field?

    // Value changes on these trigger .sensoryFeedback modifiers for haptic feedback
    @State private var loginResult: LoginResult?
    @State private var showSettings = false

    private enum Field: Hashable { case username, password }
    private enum LoginResult { case success, failure }

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")

    // @ScaledMetric makes these sizes scale with the user's Dynamic Type setting,
    // so controls remain proportional at larger accessibility text sizes
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
        // Haptic feedback on login result — .sensoryFeedback triggers when the value changes
        .sensoryFeedback(.success, trigger: loginResult) { _, new in new == .success }
        .sensoryFeedback(.error, trigger: loginResult) { _, new in new == .failure }
        // .onAppear (not .task) here because we need synchronous animation setup, not async work
        .onAppear {
            // Staggered entrance: logo fades in first, then the form slides up
            withAnimation(.easeOut(duration: 0.8)) {
                logoAppeared = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                formAppeared = true
            }
            // Slow continuous rotation for the decorative background rings
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            // Auto-trigger biometric login if the user has it enabled
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
                // Capped at 180pt so it doesn't overwhelm the screen at large Dynamic Type sizes
                .frame(width: min(logoSize, 180), height: min(logoSize, 180))
                .shadow(color: gold.opacity(0.3), radius: 20, y: 4)
                .scaleEffect(logoAppeared ? 1 : 0.6)
                .opacity(logoAppeared ? 1 : 0)
                .accessibilityLabel("Opus Accountancy logo")
                // Hidden gesture: double-tap logo opens settings (useful before login)
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
                    // 0.6 opacity (not 0.5) to meet WCAG contrast on the dark background
                    .foregroundColor(.white.opacity(0.6))
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
                .frame(height: buttonHeight)
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
            .accessibilityLabel("Sign In")
            .accessibilityHint("Double tap to sign in to your account")

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
                .font(.system(size: fieldIconSize, weight: .medium))
                // Icon highlights gold when its field is focused for visual feedback
                .foregroundColor(focusedField == field ? gold : .white.opacity(0.4))
                .frame(width: 20)
                .animation(.easeInOut(duration: 0.2), value: focusedField)
                // Decorative — the text field itself provides the accessible label
                .accessibilityHidden(true)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                        .focused($focusedField, equals: field)
                        .textContentType(.password)
                        // "Go" on the keyboard return key signals this is the final field
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                } else {
                    TextField(placeholder, text: text)
                        .focused($focusedField, equals: field)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        // "Next" advances focus to password; "Go" on password submits the form
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }
            }
            // Uses .body text style (not a fixed size) so it scales with Dynamic Type
            .font(.body)
            .foregroundColor(.white)
            .tint(gold)
        }
        .padding(.horizontal, 16)
        // minHeight (not fixed) so the field can grow when Dynamic Type is large
        .frame(minHeight: fieldHeight)
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
                loginResult = .success  // Triggers success haptic via .sensoryFeedback
            } catch {
                withAnimation(.spring(response: 0.3)) {
                    errorMessage = error.localizedDescription
                }
                loginResult = .failure  // Triggers error haptic via .sensoryFeedback
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
