import Foundation
import Testing
@testable import transcript

// MARK: - Test Helpers

private let sampleMetadata = VideoMetadata(
    videoId: "dQw4w9WgXcQ",
    title: "Interview With Jane Smith",
    author: "Example Channel",
    publishDate: "2024-01-15",
    duration: "3:45",
    viewCount: "1000000",
    description: "A test video",
    keywords: ["test"]
)

/// Builds text of roughly `sentences` sentences, each ~60 chars.
private func makeSentences(_ count: Int) -> String {
    (1...count)
        .map { "This is sentence number \($0) with some padding words in it." }
        .joined(separator: " ")
}

// MARK: - Chunk Splitting

@Suite("AI Chunk Splitting")
struct ChunkSplittingTests {

    @Test("returns short text as a single chunk unchanged")
    func shortTextSingleChunk() {
        let text = "One short sentence. And another one."
        let chunks = AIFormatter.splitIntoChunks(text, targetSize: 1000)
        #expect(chunks == [text])
    }

    @Test("splits long text into multiple chunks")
    func splitsLongText() {
        let text = makeSentences(100)
        let chunks = AIFormatter.splitIntoChunks(text, targetSize: 1000)
        #expect(chunks.count > 1)
    }

    @Test("is lossless — rejoined chunks reproduce the input")
    func lossless() {
        let text = makeSentences(100)
        let chunks = AIFormatter.splitIntoChunks(text, targetSize: 1000)
        #expect(chunks.joined(separator: " ") == text)
    }

    @Test("cuts chunks at sentence boundaries")
    func sentenceBoundaries() {
        let text = makeSentences(100)
        let chunks = AIFormatter.splitIntoChunks(text, targetSize: 1000)
        for chunk in chunks.dropLast() {
            let last = chunk.last
            #expect(last == "." || last == "!" || last == "?")
        }
    }

    @Test("keeps chunks near the target size")
    func chunkSizes() {
        let text = makeSentences(200)
        let target = 1000
        let chunks = AIFormatter.splitIntoChunks(text, targetSize: target)
        for chunk in chunks.dropLast() {
            #expect(chunk.count >= target)
            #expect(chunk.count <= target * 3 / 2)
        }
    }

    @Test("never splits a word")
    func wordsIntact() {
        let text = makeSentences(100)
        let inputWords = text.split(separator: " ")
        let outputWords = AIFormatter.splitIntoChunks(text, targetSize: 1000)
            .flatMap { $0.split(separator: " ") }
        #expect(inputWords == outputWords)
    }

    @Test("hard cap splits text with no sentence punctuation")
    func hardCapWithoutPunctuation() {
        let text = Array(repeating: "word", count: 500).joined(separator: " ")
        let target = 500
        let chunks = AIFormatter.splitIntoChunks(text, targetSize: target)
        #expect(chunks.count > 1)
        // The cap is checked after a word is appended, so a chunk may
        // overshoot it by at most one word.
        let slack = " word".count
        for chunk in chunks.dropLast() {
            #expect(chunk.count <= target * 3 / 2 + slack)
        }
        #expect(chunks.joined(separator: " ") == text)
    }
}

// MARK: - System Prompt

@Suite("AI System Prompt")
struct SystemPromptTests {

    @Test("includes video title and channel for speaker inference")
    func includesMetadata() {
        let prompt = AIFormatter.makeSystemPrompt(index: 0, total: 1, metadata: sampleMetadata)
        #expect(prompt.contains("Interview With Jane Smith"))
        #expect(prompt.contains("Example Channel"))
    }

    @Test("asks for bold speaker labels, named first with generic fallback")
    func speakerLabelRule() {
        let prompt = AIFormatter.makeSystemPrompt(index: 0, total: 1, metadata: sampleMetadata)
        #expect(prompt.contains("bold speaker label"))
        #expect(prompt.contains("name the speakers"))
        #expect(prompt.contains("channel name usually identifies the host"))
        #expect(prompt.contains("Fall back to **Host:** and **Guest:** only"))
    }

    @Test("forbids summarizing")
    func forbidsSummarizing()  {
        let prompt = AIFormatter.makeSystemPrompt(index: 0, total: 1, metadata: sampleMetadata)
        #expect(prompt.contains("Do NOT summarize"))
    }

    @Test("single chunk gets whole-video heading guidance and no part note")
    func singleChunkPrompt() {
        let prompt = AIFormatter.makeSystemPrompt(index: 0, total: 1, metadata: sampleMetadata)
        #expect(prompt.contains("4-6 headings"))
        #expect(!prompt.contains("part 1 of 1"))
    }

    @Test("multi-chunk prompt identifies the part and limits headings")
    func multiChunkPrompt() {
        let prompt = AIFormatter.makeSystemPrompt(index: 1, total: 4, metadata: sampleMetadata)
        #expect(prompt.contains("part 2 of 4"))
        #expect(prompt.contains("at most 1-2 ## headings"))
        #expect(prompt.contains("do not add an introduction"))
        #expect(!prompt.contains("4-6 headings"))
    }

    @Test("later chunks carry the previous chunk's tail for continuity")
    func continuityTail() {
        let tail = "**Host:** And that brings us to the next topic."
        let prompt = AIFormatter.makeSystemPrompt(
            index: 1, total: 4, metadata: sampleMetadata, previousTail: tail
        )
        #expect(prompt.contains(tail))
        #expect(prompt.contains("Continue seamlessly"))
    }

    @Test("later chunks require the established speaker labels")
    func knownLabelsRequired() {
        let prompt = AIFormatter.makeSystemPrompt(
            index: 2, total: 4, metadata: sampleMetadata,
            knownLabels: ["**Host:**", "**Guest:**"]
        )
        #expect(prompt.contains("**Host:** and **Guest:**"))
        #expect(prompt.contains("label EVERY speaking turn"))
    }

    @Test("first chunk has no continuity section")
    func noTailOnFirstChunk() {
        let prompt = AIFormatter.makeSystemPrompt(index: 0, total: 4, metadata: sampleMetadata)
        #expect(!prompt.contains("Continue seamlessly"))
        #expect(!prompt.contains("label EVERY speaking turn"))
    }
}

// MARK: - Speaker Label Extraction

@Suite("Speaker Label Extraction")
struct SpeakerLabelTests {

    @Test("collects labels in order of first appearance without duplicates")
    func collectsLabels() {
        let parts = [
            "**Host:** Hello.\n\n**Guest:** Hi.\n\n**Host:** Welcome.",
            "**Guest:** Thanks.",
        ]
        #expect(AIFormatter.speakerLabels(in: parts) == ["**Host:**", "**Guest:**"])
    }

    @Test("returns empty for unlabeled text")
    func noLabels() {
        let parts = ["Just a monologue with **bold emphasis** but no labels."]
        #expect(AIFormatter.speakerLabels(in: parts).isEmpty)
    }
}
