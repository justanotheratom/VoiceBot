import Foundation

/// Utility for calculating token generation statistics
enum TokenStatsCalculator {
    /// Calculate statistics for a completed streaming session
    static func calculate(
        tokenCount: Int,
        startTime: Date,
        firstTokenTime: Date?,
        endTime: Date
    ) -> TokenStats {
        let totalTime = endTime.timeIntervalSince(startTime)
        let timeToFirstToken = firstTokenTime?.timeIntervalSince(startTime)
        let tokensPerSecond = tokenCount > 0 && totalTime > 0 ? Double(tokenCount) / totalTime : nil

        return TokenStats(
            tokens: tokenCount,
            timeToFirstToken: timeToFirstToken,
            tokensPerSecond: tokensPerSecond
        )
    }
}
