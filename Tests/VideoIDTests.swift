import Testing
@testable import transcript

@Suite("VideoID Parsing")
struct VideoIDTests {

    // MARK: - Standard URLs

    @Test("standard watch URL")
    func standardWatchURL() throws {
        let id = try VideoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    @Test("watch URL with extra params")
    func watchURLWithParams() throws {
        let id = try VideoID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120&list=PLtest")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    @Test("watch URL without www")
    func watchURLNoWWW() throws {
        let id = try VideoID(from: "https://youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    @Test("mobile URL")
    func mobileURL() throws {
        let id = try VideoID(from: "https://m.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    // MARK: - Short URLs

    @Test("youtu.be short URL")
    func shortURL() throws {
        let id = try VideoID(from: "https://youtu.be/dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    @Test("youtu.be with timestamp")
    func shortURLWithTimestamp() throws {
        let id = try VideoID(from: "https://youtu.be/dQw4w9WgXcQ?t=42")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    // MARK: - Path-based URLs

    @Test("embed URL")
    func embedURL() throws {
        let id = try VideoID(from: "https://www.youtube.com/embed/dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    @Test("shorts URL")
    func shortsURL() throws {
        let id = try VideoID(from: "https://www.youtube.com/shorts/dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    @Test("live URL")
    func liveURL() throws {
        let id = try VideoID(from: "https://www.youtube.com/live/dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    // MARK: - Raw IDs

    @Test("raw 11-character ID")
    func rawID() throws {
        let id = try VideoID(from: "dQw4w9WgXcQ")
        #expect(id.value == "dQw4w9WgXcQ")
    }

    @Test("raw ID with hyphens and underscores")
    func rawIDWithSpecialChars() throws {
        let id = try VideoID(from: "a-B_c1D2e3f")
        #expect(id.value == "a-B_c1D2e3f")
    }

    // MARK: - Invalid Inputs

    @Test("rejects empty string")
    func emptyString() {
        #expect(throws: TranscriptError.self) {
            try VideoID(from: "")
        }
    }

    @Test("rejects random text")
    func randomText() {
        #expect(throws: TranscriptError.self) {
            try VideoID(from: "not a video id")
        }
    }

    @Test("rejects too-short ID")
    func tooShortID() {
        #expect(throws: TranscriptError.self) {
            try VideoID(from: "abc")
        }
    }

    @Test("rejects too-long ID")
    func tooLongID() {
        #expect(throws: TranscriptError.self) {
            try VideoID(from: "abcdefghijkl")
        }
    }

    @Test("rejects non-YouTube URL")
    func nonYouTubeURL() {
        #expect(throws: TranscriptError.self) {
            try VideoID(from: "https://vimeo.com/12345")
        }
    }

    @Test("rejects youtu.be with empty path")
    func shortURLEmptyPath() {
        #expect(throws: TranscriptError.self) {
            try VideoID(from: "https://youtu.be/")
        }
    }
}
