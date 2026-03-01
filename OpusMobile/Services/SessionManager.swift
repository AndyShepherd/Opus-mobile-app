import SwiftUI
import UIKit

/// Manages local inactivity lock. Separate from AuthService — the JWT stays valid,
/// this just requires biometric re-authentication after a configurable idle timeout.
@MainActor
final class SessionManager: ObservableObject {
    @Published var isLocked = false

    private var lastActivityDate = Date()
    private var timer: Timer?

    /// Called on every touch via the activity tracking overlay.
    func recordActivity() {
        lastActivityDate = Date()
    }

    func startMonitoring() {
        lastActivityDate = Date()
        isLocked = false
        scheduleTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the app enters the background. Stops the timer but preserves
    /// lastActivityDate so we can check elapsed time on foreground.
    func appDidEnterBackground() {
        timer?.invalidate()
        timer = nil
    }

    /// Called when the app returns to the foreground. Locks if the timeout elapsed
    /// while backgrounded, otherwise resumes the timer.
    func appWillEnterForeground() {
        if hasTimedOut() {
            isLocked = true
        } else {
            scheduleTimer()
        }
    }

    /// Called after successful biometric unlock on the lock screen.
    func unlock() {
        isLocked = false
        lastActivityDate = Date()
        scheduleTimer()
    }

    // MARK: - Private

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkTimeout()
            }
        }
    }

    private func checkTimeout() {
        if hasTimedOut() {
            isLocked = true
            timer?.invalidate()
            timer = nil
        }
    }

    private func hasTimedOut() -> Bool {
        let elapsed = Date().timeIntervalSince(lastActivityDate)
        let timeout = TimeInterval(Config.sessionTimeoutMinutes * 60)
        return elapsed >= timeout
    }
}

// MARK: - Activity Tracking Overlay

/// Transparent overlay that detects all touches without consuming them.
/// Uses UIKit's hitTest to observe touches, then returns nil so they pass through
/// to the SwiftUI content underneath.
struct ActivityTrackingOverlay: UIViewRepresentable {
    let sessionManager: SessionManager

    func makeUIView(context: Context) -> TouchDetectorView {
        let view = TouchDetectorView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.onTouch = { [weak sessionManager] in
            sessionManager?.recordActivity()
        }
        return view
    }

    func updateUIView(_ uiView: TouchDetectorView, context: Context) {}
}

/// UIView subclass that intercepts hitTest to detect touches without consuming them.
class TouchDetectorView: UIView {
    var onTouch: (() -> Void)?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        onTouch?()
        return nil  // Pass touch through to views underneath
    }
}
