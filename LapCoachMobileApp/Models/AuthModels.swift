import Foundation

struct APIConfiguration: Sendable {
    let baseURL: URL
    var signInPath: String = "/mobile/auth/login"
    var sessionsPath: String = "/mobile/sessions"

    func endpoint(_ path: String) -> URL {
        baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

struct AuthenticatedUser: Codable, Hashable, Sendable {
    let id: String
    let email: String
    let displayName: String?
}

struct AuthSession: Codable, Hashable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthenticatedUser
}

struct SignInRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct SignInResponse: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthenticatedUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}
