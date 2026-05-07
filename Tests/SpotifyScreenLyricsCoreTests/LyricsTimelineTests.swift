import Testing
@testable import SpotifyScreenLyricsCore

@Test
func displayLinesBeforeFirstTimestampUsesFirstLine() {
    let lines = [
        LyricLine(time: 4.0, text: "First"),
        LyricLine(time: 8.0, text: "Second")
    ]

    let display = LyricsTimeline.displayLines(for: 1.0, lines: lines)

    #expect(display == DisplayLyrics(currentLine: "First", nextLine: "Second"))
}

@Test
func displayLinesSelectsCurrentAndNextLine() {
    let lines = [
        LyricLine(time: 1.0, text: "First"),
        LyricLine(time: 3.0, text: "Second"),
        LyricLine(time: 5.0, text: "Third")
    ]

    let display = LyricsTimeline.displayLines(for: 3.2, lines: lines)

    #expect(display == DisplayLyrics(currentLine: "Second", nextLine: "Third"))
}

@Test
func displayLinesAfterLastLineHasNoNextLine() {
    let lines = [
        LyricLine(time: 1.0, text: "First")
    ]

    let display = LyricsTimeline.displayLines(for: 9.0, lines: lines)

    #expect(display == DisplayLyrics(currentLine: "First", nextLine: nil))
}

@Test
func displayLinesReturnsNilForEmptyInput() {
    #expect(LyricsTimeline.displayLines(for: 1.0, lines: []) == nil)
}
