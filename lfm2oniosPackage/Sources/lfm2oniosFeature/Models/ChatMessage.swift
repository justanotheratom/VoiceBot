import Foundation

// MARK: - Chat UI Message Models

public struct TokenStats: Equatable, Sendable {
    public let tokens: Int
    public let timeToFirstToken: TimeInterval?
    public let tokensPerSecond: Double?

    public init(tokens: Int, timeToFirstToken: TimeInterval? = nil, tokensPerSecond: Double? = nil) {
        self.tokens = tokens
        self.timeToFirstToken = timeToFirstToken
        self.tokensPerSecond = tokensPerSecond
    }
}

public struct Message: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let id: UUID
    public let role: Role
    public var text: String
    public var stats: TokenStats?

    public init(id: UUID = UUID(), role: Role, text: String, stats: TokenStats? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.stats = stats
    }
}
