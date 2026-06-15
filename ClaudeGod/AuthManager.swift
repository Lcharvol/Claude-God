import Foundation

class AuthManager {
    static let shared = AuthManager()
    private let tokenKey = "authToken"
    private let defaults = UserDefaults.standard

    var authToken: String? {
        get { return defaults.string(forKey: tokenKey) }
        set { defaults.set(newValue, forKey: tokenKey) }
    }

    func login(username: String, password: String, completion: @escaping (Bool, Error?) -> Void) {
        // Implement login logic here
        // ... 
        // Update auth token on successful login
        authToken = "newAuthToken"
        completion(true, nil)
    }

    func logout() {
        authToken = nil
    }
}