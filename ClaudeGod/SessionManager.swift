import Foundation

class SessionManager {
    static let shared = SessionManager()
    private let sessionKey = "session"
    private let defaults = UserDefaults.standard

    var session: String? {
        get { return defaults.string(forKey: sessionKey) }
        set { defaults.set(newValue, forKey: sessionKey) }
    }

    func startSession() {
        // Implement session start logic here
        // ... 
        // Update session on successful start
        session = "newSession"
    }

    func endSession() {
        session = nil
    }
}