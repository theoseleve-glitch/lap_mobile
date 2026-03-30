import Foundation
import Security

final class AuthService {
    private let apiConfiguration: APIConfiguration
    private let session: URLSession
    private let keychain: KeychainStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        apiConfiguration: APIConfiguration,
        session: URLSession = .shared,
        keychain: KeychainStore = KeychainStore(service: "com.lapcoach.mobile.auth")
    ) {
        self.apiConfiguration = apiConfiguration
        self.session = session
        self.keychain = keychain

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func restoreSession() -> AuthSession? {
        keychain.read()
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let requestBody = SignInRequest(email: email, password: password)
        var request = URLRequest(url: apiConfiguration.endpoint(apiConfiguration.signInPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AuthServiceError.invalidResponse
        }

        guard (200 ... 299).contains(response.statusCode) else {
            throw AuthServiceError.statusCode(response.statusCode)
        }

        let decoded = try decoder.decode(SignInResponse.self, from: data)
        let authSession = AuthSession(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            user: decoded.user
        )
        keychain.save(authSession)
        return authSession
    }

    func signOut() {
        keychain.clear()
    }
}

enum AuthServiceError: LocalizedError {
    case invalidResponse
    case statusCode(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The authentication server returned an invalid response."
        case let .statusCode(code):
            return "Authentication failed with status code \(code)."
        }
    }
}

final class KeychainStore {
    private let service: String
    private let account = "lapcoach-auth-session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String) {
        self.service = service
    }

    func save(_ session: AuthSession) {
        clear()
        guard let payload = try? encoder.encode(session) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    func read() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? decoder.decode(AuthSession.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
