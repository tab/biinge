import Foundation

/// Auth/user resources use snake_case JSON, so they need explicit CodingKeys

struct TokenPair: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct User: Decodable, Sendable, Identifiable, Equatable {
    let id: UUID
    let login: String
    let email: String
    let firstName: String?
    let lastName: String?
    let appearance: Appearance

    enum CodingKeys: String, CodingKey {
        case id, login, email, appearance
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

enum Appearance: String, Codable, Sendable, CaseIterable {
    case light, dark, system
}
