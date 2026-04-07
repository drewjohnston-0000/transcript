import Foundation
import Testing
@testable import transcript

// MARK: - Test Helpers

private func makeEvent(startMs: Int, durationMs: Int, text: String) -> JSON3Response.Event {
    JSON3Response.Event(
        tStartMs: startMs,
        dDurationMs: durationMs,
        segs: [.init(utf8: text)]
    )
}

private let sampleMetadata = VideoMetadata(
    videoId: "dQw4w9WgXcQ",
    title: "Test Video",
    author: "Test Channel",
    publishDate: "2024-01-15",
    duration: "3:45",
    viewCount: "1000000",
    description: "A test video",
    keywords: ["test"]
)

private let sampleTrack = CaptionTrack(
    baseUrl: "https://example.com/captions",
    languageCode: "en",
    kind: nil,
    name: TrackName(simpleText: "English", runs: nil)
)

// MARK: - HTML Entity Decoding

@Suite("HTML Entity Decoding")
struct EntityDecodingTests {

    @Test("decodes named entities")
    func namedEntities() {
        #expect(Formatter.decodeEntities("&amp;") == "&")
        #expect(Formatter.decodeEntities("&lt;") == "<")
        #expect(Formatter.decodeEntities("&gt;") == ">")
        #expect(Formatter.decodeEntities("&quot;") == "\"")
        #expect(Formatter.decodeEntities("&#39;") == "'")
        #expect(Formatter.decodeEntities("&apos;") == "'")
        #expect(Formatter.decodeEntities("&nbsp;") == " ")
    }

    @Test("decodes numeric entities")
    func numericEntities() {
        #expect(Formatter.decodeEntities("&#65;") == "A")
        #expect(Formatter.decodeEntities("&#8212;") == "\u{2014}") // em dash
    }

    @Test("decodes hex entities")
    func hexEntities() {
        #expect(Formatter.decodeEntities("&#x27;") == "'")
        #expect(Formatter.decodeEntities("&#x2F;") == "/")
    }

    @Test("decodes multiple entities in one string")
    func multipleEntities() {
        #expect(Formatter.decodeEntities("Tom &amp; Jerry &lt;3") == "Tom & Jerry <3")
    }

    @Test("leaves plain text unchanged")
    func plainText() {
        #expect(Formatter.decodeEntities("hello world") == "hello world")
    }
}

// MARK: - Raw Text Extraction

@Suite("Raw Text")
struct RawTextTests {

    @Test("joins event text with spaces")
    func joinsText() {
        let events = [
            makeEvent(startMs: 0, durationMs: 1000, text: "Hello"),
            makeEvent(startMs: 1000, durationMs: 1000, text: "world"),
        ]
        #expect(Formatter.rawText(from: events) == "Hello world")
    }

    @Test("skips empty segments")
    func skipsEmpty() {
        let events = [
            makeEvent(startMs: 0, durationMs: 1000, text: "Hello"),
            makeEvent(startMs: 1000, durationMs: 1000, text: "  "),
            makeEvent(startMs: 2000, durationMs: 1000, text: "world"),
        ]
        #expect(Formatter.rawText(from: events) == "Hello world")
    }

    @Test("decodes entities in raw text")
    func decodesEntities() {
        let events = [
            makeEvent(startMs: 0, durationMs: 1000, text: "rock &amp; roll"),
        ]
        #expect(Formatter.rawText(from: events) == "rock & roll")
    }
}

// MARK: - Text Formatting

@Suite("Text Formatting")
struct TextFormattingTests {

    @Test("groups close events into a paragraph")
    func singleParagraph() {
        let events = [
            makeEvent(startMs: 0, durationMs: 1000, text: "Hello"),
            makeEvent(startMs: 1000, durationMs: 1000, text: "world"),
        ]
        let result = Formatter.format(events, metadata: sampleMetadata, track: sampleTrack, as: .text)
        #expect(result.contains("Hello world"))
    }

    @Test("splits paragraphs on time gaps > 2s")
    func paragraphSplitOnGap() {
        let events = [
            makeEvent(startMs: 0, durationMs: 1000, text: "First part"),
            makeEvent(startMs: 5000, durationMs: 1000, text: "Second part"),
        ]
        let result = Formatter.format(events, metadata: sampleMetadata, track: sampleTrack, as: .text)
        #expect(result.contains("First part\n\nSecond part"))
    }
}

// MARK: - SRT Formatting

@Suite("SRT Formatting")
struct SRTFormattingTests {

    @Test("produces valid SRT blocks")
    func basicSRT() {
        let events = [
            makeEvent(startMs: 0, durationMs: 2000, text: "Hello"),
            makeEvent(startMs: 3000, durationMs: 1500, text: "World"),
        ]
        let result = Formatter.format(events, metadata: sampleMetadata, track: sampleTrack, as: .srt)
        #expect(result.contains("1\n00:00:00,000 --> 00:00:02,000\nHello"))
        #expect(result.contains("2\n00:00:03,000 --> 00:00:04,500\nWorld"))
    }

    @Test("formats hours correctly")
    func hoursInTimestamp() {
        let events = [
            makeEvent(startMs: 3_661_500, durationMs: 1000, text: "Late"),
        ]
        let result = Formatter.format(events, metadata: sampleMetadata, track: sampleTrack, as: .srt)
        #expect(result.contains("01:01:01,500 --> 01:01:02,500"))
    }

    @Test("skips events without start time")
    func skipsNoStart() {
        let events = [
            JSON3Response.Event(tStartMs: nil, dDurationMs: 1000, segs: [.init(utf8: "orphan")]),
            makeEvent(startMs: 1000, durationMs: 1000, text: "valid"),
        ]
        let result = Formatter.format(events, metadata: sampleMetadata, track: sampleTrack, as: .srt)
        #expect(!result.contains("orphan"))
        #expect(result.contains("1\n00:00:01,000"))
    }

    @Test("uses 3s default duration when missing")
    func defaultDuration() {
        let events = [
            JSON3Response.Event(tStartMs: 0, dDurationMs: nil, segs: [.init(utf8: "Hello")]),
        ]
        let result = Formatter.format(events, metadata: sampleMetadata, track: sampleTrack, as: .srt)
        #expect(result.contains("00:00:00,000 --> 00:00:03,000"))
    }
}

// MARK: - JSON Formatting

@Suite("JSON Formatting")
struct JSONFormattingTests {

    @Test("produces valid JSON array")
    func validJSON() throws {
        let events = [
            makeEvent(startMs: 1500, durationMs: 2000, text: "Hello"),
        ]
        let result = Formatter.format(events, metadata: sampleMetadata, track: sampleTrack, as: .json)
        // Extract the JSON part — find the first '[' which starts the array
        let startIndex = result.firstIndex(of: "[")!
        let jsonPart = String(result[startIndex...])
        let data = jsonPart.data(using: .utf8)!

        struct Entry: Decodable {
            let start: String
            let durationMs: Int
            let text: String
        }

        let entries = try JSONDecoder().decode([Entry].self, from: data)
        #expect(entries.count == 1)
        #expect(entries[0].start == "00:00:01.500")
        #expect(entries[0].durationMs == 2000)
        #expect(entries[0].text == "Hello")
    }
}

// MARK: - Header

@Suite("Header Formatting")
struct HeaderTests {

    @Test("includes title as markdown heading")
    func title() {
        let header = Formatter.header(metadata: sampleMetadata, track: sampleTrack)
        #expect(header.contains("# Test Video"))
    }

    @Test("includes channel name")
    func channel() {
        let header = Formatter.header(metadata: sampleMetadata, track: sampleTrack)
        #expect(header.contains("Test Channel"))
    }

    @Test("includes video URL")
    func videoURL() {
        let header = Formatter.header(metadata: sampleMetadata, track: sampleTrack)
        #expect(header.contains("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test("labels manual captions")
    func manualCaptions() {
        let header = Formatter.header(metadata: sampleMetadata, track: sampleTrack)
        #expect(header.contains("English (Manual)"))
    }

    @Test("labels auto-generated captions")
    func autoCaptions() {
        let autoTrack = CaptionTrack(
            baseUrl: "https://example.com",
            languageCode: "en",
            kind: "asr",
            name: TrackName(simpleText: "English", runs: nil)
        )
        let header = Formatter.header(metadata: sampleMetadata, track: autoTrack)
        #expect(header.contains("English (Auto-generated)"))
    }

    @Test("skips auto label when display name already says auto")
    func autoInName() {
        let autoTrack = CaptionTrack(
            baseUrl: "https://example.com",
            languageCode: "en",
            kind: "asr",
            name: TrackName(simpleText: "English (auto-generated)", runs: nil)
        )
        let header = Formatter.header(metadata: sampleMetadata, track: autoTrack)
        // Should NOT double-label
        #expect(!header.contains("(auto-generated) (Auto-generated)"))
        #expect(header.contains("English (auto-generated)"))
    }
}
