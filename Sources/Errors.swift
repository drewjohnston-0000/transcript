import Foundation

enum TranscriptError: LocalizedError {
    case invalidURL(String)
    case networkError(underlying: any Error)
    case apiKeyNotFound
    case videoNotFound(String)
    case noCaptionsAvailable
    case languageNotFound(requested: String, available: [String])
    case captionDownloadFailed
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let input):
            "Invalid YouTube URL or video ID: \(input)"
        case .networkError(let underlying):
            "Network error: \(underlying.localizedDescription)"
        case .apiKeyNotFound:
            "Could not extract YouTube API key from page"
        case .videoNotFound(let id):
            "Video not found: \(id)"
        case .noCaptionsAvailable:
            "No captions available for this video"
        case .languageNotFound(let requested, let available):
            "Language '\(requested)' not available. Available: \(available.joined(separator: ", "))"
        case .captionDownloadFailed:
            "Failed to download caption data"
        case .parseError(let detail):
            "Parse error: \(detail)"
        }
    }
}
