import LocalAuthentication
import SwiftUI

/// Displayed when the session is locked due to inactivity.
/// Requires biometric re-authentication to dismiss, or offers sign-out as a fallback.
struct LockScreenView: View {
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var isUnlocking = false
    @State private var errorMessage: String?
    @State private var ringRotation: Double = 0

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")

    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 52

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [navy, Color(red: 0.04, green: 0.10, blue: 0.20)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            backgroundRings
                .accessibilityHidden(true)

            VStack(spacing: 32) {
                Spacer()

                // Lock icon
                Image(systemName: "lock.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(gold)
                    .padding(.bottom, 8)

                VStack(spacing: 8) {
                    Text("Session Locked")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("Verify your identity to continue")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                        Text(errorMessage)
                            .font(.caption)
                    }
                    .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                    .transition(.opacity)
                }

                // Unlock button — uses biometric if available, falls back to device passcode
                Button {
                    unlock()
                } label: {
                    ZStack {
                        if isUnlocking {
                            ProgressView()
                                .tint(navy)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: unlockIconName)
                                Text(unlockLabel)
                            }
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
                .disabled(isUnlocking)
                .padding(.horizontal, 40)

                Spacer()

                // Sign out fallback
                Button {
                    authService.logout()
                    sessionManager.unlock()
                } label: {
                    Text("Sign Out")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
            // Auto-trigger unlock prompt on appear
            unlock()
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

    // MARK: - Helpers

    private var unlockIconName: String {
        BiometricService.isAvailable ? BiometricService.systemImageName : "lock.open.fill"
    }

    private var unlockLabel: String {
        BiometricService.isAvailable ? "Unlock with \(BiometricService.displayName)" : "Unlock"
    }

    // MARK: - Actions

    /// Uses .deviceOwnerAuthentication which accepts Face ID, Touch ID, OR device passcode.
    /// No keychain read needed — we just prove the user is physically present.
    private func unlock() {
        guard !isUnlocking else { return }
        isUnlocking = true
        errorMessage = nil

        let context = LAContext()
        context.localizedReason = "Unlock Opus"

        Task {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Unlock Opus"
                )
                if success {
                    await MainActor.run { sessionManager.unlock() }
                }
            } catch let error as LAError where error.code == .userCancel || error.code == .appCancel {
                // User cancelled — no error message
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.3)) {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            await MainActor.run { isUnlocking = false }
        }
    }
}
