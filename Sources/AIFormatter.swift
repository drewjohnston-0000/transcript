import Foundation

struct AIFormatter: Sendable {
    private static let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    static func format(_ rawText: String, metadata: VideoMetadata) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            throw TranscriptError.parseError(
                "OPENAI_API_KEY not set. Export it in your shell profile to use --clean."
            )
        }

        let systemPrompt = """
            You are a transcript formatter. You receive raw auto-generated YouTube caption text \
            and reformat it into clean, readable markdown.

            Rules:
            - Fix punctuation, capitalization, and sentence boundaries
            - Merge fragments into proper flowing sentences
            - Aim for 3-4 sentences per paragraph — long enough to develop a thought, short enough to stay readable
            - Break paragraphs at natural shifts in thought, not after every sentence
            - Use ">" blockquote for direct quotes or when speakers change
            - Remove filler artifacts like "[music]", "[applause]", "[laughter]" unless contextually meaningful
            - Remove obvious speech-to-text errors where possible
            - Insert ## headings at major topic shifts to break the transcript into sections
            - Choose short, descriptive headings that capture the topic being discussed
            - Use 4-6 headings for a typical 20-minute video — don't over-segment
            - Do NOT summarize, add, or remove substantive content — preserve the speaker's words
            - Output only the formatted transcript text, nothing else
            """

        let payload: [String: Any] = [
            "model": "gpt-4.1-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": rawText],
            ],
            "temperature": 0.3,
        ]

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TranscriptError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptError.parseError("Invalid response from OpenAI")
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw TranscriptError.parseError("OpenAI API error (\(http.statusCode)): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranscriptError.parseError("Could not parse OpenAI response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
