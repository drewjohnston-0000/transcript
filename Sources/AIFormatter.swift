import Foundation

struct AIFormatter: Sendable {
    private static let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    // Long inputs push the model toward summarizing instead of reformatting,
    // so the transcript is split into pieces and each is formatted separately.
    private static let chunkTargetSize = 10_000

    // Verbatim reformatting should return roughly as many characters as it
    // received; a much shorter response means the model summarized.
    private static let minOutputRatio = 0.7

    static func format(_ rawText: String, metadata: VideoMetadata) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            Logger.failure("OPENAI_API_KEY is not set — AI formatting cannot run.")
            throw TranscriptError.parseError(
                "OPENAI_API_KEY not set. Export it in your shell profile to use --clean."
            )
        }

        let chunks = splitIntoChunks(rawText, targetSize: Self.chunkTargetSize)
        Logger.info(
            "Requesting AI formatting (model: gpt-4.1-mini, \(rawText.count) chars, \(chunks.count) chunk(s))"
        )

        var parts: [String] = []
        for (index, chunk) in chunks.enumerated() {
            let part = try await formatChunk(
                chunk, index: index, total: chunks.count, metadata: metadata,
                previousTail: parts.last.map { String($0.suffix(500)) },
                knownLabels: speakerLabels(in: parts), apiKey: apiKey
            )
            parts.append(part)
        }

        return parts.joined(separator: "\n\n")
    }

    /// Speaker labels ("**Name:**") already used in formatted parts, in order
    /// of first appearance, so later chunks can be held to the same set.
    static func speakerLabels(in parts: [String]) -> [String] {
        var labels: [String] = []
        for part in parts {
            for match in part.matches(of: /\*\*([^*\n]+):\*\*/) {
                let label = "**\(match.1):**"
                if !labels.contains(label) { labels.append(label) }
            }
        }
        return labels
    }

    private static func formatChunk(
        _ chunk: String, index: Int, total: Int, metadata: VideoMetadata,
        previousTail: String?, knownLabels: [String], apiKey: String
    ) async throws -> String {
        let systemPrompt = makeSystemPrompt(
            index: index, total: total, metadata: metadata,
            previousTail: previousTail, knownLabels: knownLabels
        )

        if total > 1 {
            Logger.info("Formatting chunk \(index + 1)/\(total) (\(chunk.count) chars)")
        }

        var content = try await sendRequest(systemPrompt: systemPrompt, text: chunk, apiKey: apiKey)
        var ratio = Double(content.count) / Double(chunk.count)

        if ratio < Self.minOutputRatio {
            Logger.warning(
                "Chunk \(index + 1)/\(total) came back \(content.count)/\(chunk.count) chars "
                    + "(ratio \(String(format: "%.2f", ratio)) < \(Self.minOutputRatio)) — "
                    + "output looks summarized, retrying once"
            )
            let sternPrompt = systemPrompt + """


                IMPORTANT: Your previous attempt was far shorter than the input. You must \
                reproduce every sentence of the input text, reformatted — a summary is a failure.
                """
            content = try await sendRequest(systemPrompt: sternPrompt, text: chunk, apiKey: apiKey)
            ratio = Double(content.count) / Double(chunk.count)
        }

        guard ratio >= Self.minOutputRatio else {
            Logger.failure(
                "AI formatting is lossy: chunk \(index + 1)/\(total) returned "
                    + "\(content.count) of \(chunk.count) chars after retry."
            )
            throw TranscriptError.parseError(
                "AI formatting summarized the transcript instead of reformatting it "
                    + "(chunk \(index + 1)/\(total): \(content.count)/\(chunk.count) chars). "
                    + "Re-run without --clean for the verbatim transcript."
            )
        }

        return content
    }

    static func makeSystemPrompt(
        index: Int, total: Int, metadata: VideoMetadata,
        previousTail: String? = nil, knownLabels: [String] = []
    ) -> String {
        var prompt = """
            You are a transcript formatter. You receive raw auto-generated YouTube caption text \
            and reformat it into clean, readable markdown.

            Video title: \(metadata.title)
            Channel: \(metadata.author)

            Rules:
            - Fix punctuation, capitalization, and sentence boundaries
            - Merge fragments into proper flowing sentences
            - Aim for 3-4 sentences per paragraph — long enough to develop a thought, short enough to stay readable
            - Break paragraphs at natural shifts in thought, not after every sentence
            - If more than one person is speaking, start each speaking turn on a new paragraph \
            with a bold speaker label, e.g. "**Smith:** ..." — name the speakers: the channel \
            name usually identifies the host/interviewer, and the video title usually names the \
            guest. Fall back to **Host:** and **Guest:** only if you truly cannot name a speaker. \
            Use the same label for the same person throughout. If only one person speaks, use no labels
            - Remove filler artifacts like "[music]", "[applause]", "[laughter]" unless contextually meaningful
            - Remove obvious speech-to-text errors where possible
            - Insert ## headings at major topic shifts to break the transcript into sections
            - Choose short, descriptive headings that capture the topic being discussed
            - Do NOT summarize, condense, or drop content — reproduce every sentence, reformatted
            - Output only the formatted transcript text, nothing else
            """

        if total > 1 {
            prompt += """


                This text is part \(index + 1) of \(total) of one continuous transcript. Format \
                only this portion: do not add an introduction, conclusion, or commentary about \
                the missing parts. Use at most 1-2 ## headings, and only at a genuine topic \
                shift — it is fine to use none.
                """
            if !knownLabels.isEmpty {
                let labelList = knownLabels.joined(separator: " and ")
                prompt += """


                    The earlier portions label the speakers \(labelList). This portion continues \
                    that same conversation: label EVERY speaking turn with one of those exact \
                    labels, even if one speaker talks for a long stretch.
                    """
            }
            if let previousTail {
                prompt += """


                    For continuity, the previously formatted portion ends like this (do not \
                    repeat it):

                    \(previousTail)

                    Continue seamlessly from there.
                    """
            }
        } else {
            prompt += """

                - Use 4-6 headings for a typical 20-minute video — don't over-segment
                """
        }

        return prompt
    }

    // Splits on whitespace so words stay intact. Once a chunk reaches
    // targetSize it is cut at the next sentence-ending word so no sentence
    // straddles a chunk seam; a hard cap covers text with no punctuation.
    static func splitIntoChunks(_ text: String, targetSize: Int) -> [String] {
        guard text.count > targetSize else { return [text] }
        let hardCap = targetSize * 3 / 2

        var chunks: [String] = []
        var current = ""
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            current += current.isEmpty ? String(word) : " " + String(word)
            if current.count >= targetSize {
                let endsSentence = word.last.map { ".!?".contains($0) } ?? false
                if endsSentence || current.count >= hardCap {
                    chunks.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func sendRequest(
        systemPrompt: String, text: String, apiKey: String
    ) async throws -> String {
        let payload: [String: Any] = [
            "model": "gpt-4.1-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
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
            Logger.failure("Network error calling OpenAI: \(error.localizedDescription)")
            throw TranscriptError.networkError(underlying: error)
        }

        guard let http = response as? HTTPURLResponse else {
            Logger.failure("OpenAI returned a non-HTTP response.")
            throw TranscriptError.parseError("Invalid response from OpenAI")
        }

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            Logger.failure("OpenAI API error (HTTP \(http.statusCode)): \(body)")
            throw TranscriptError.parseError("OpenAI API error (\(http.statusCode)): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            Logger.failure("Could not parse OpenAI response body.")
            throw TranscriptError.parseError("Could not parse OpenAI response")
        }

        Logger.info("AI formatting completed (\(content.count) chars returned)")
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
