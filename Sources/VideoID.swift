import Foundation

struct VideoID: Sendable {
    let value: String

    init(from input: String) throws {
        if let id = Self.extractFromURL(input) {
            self.value = id
        } else if Self.isRawID(input) {
            self.value = input
        } else {
            throw TranscriptError.invalidURL(input)
        }
    }

    private static func extractFromURL(_ input: String) -> String? {
        guard let components = URLComponents(string: input),
              let host = components.host?.lowercased().replacingOccurrences(of: "www.", with: "").replacingOccurrences(of: "m.", with: "")
        else { return nil }

        switch host {
        case "youtube.com":
            // /watch?v=ID, /embed/ID, /shorts/ID, /live/ID
            if let v = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return v
            }
            let pathParts = components.path.split(separator: "/")
            if pathParts.count >= 2,
               ["embed", "shorts", "live", "v"].contains(String(pathParts[0])) {
                return String(pathParts[1])
            }
            return nil
        case "youtu.be":
            let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return id.isEmpty ? nil : id
        default:
            return nil
        }
    }

    private static func isRawID(_ input: String) -> Bool {
        let pattern = /^[A-Za-z0-9_-]{11}$/
        return input.wholeMatch(of: pattern) != nil
    }
}
