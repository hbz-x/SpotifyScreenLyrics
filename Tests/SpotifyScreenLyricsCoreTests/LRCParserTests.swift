import Testing
@testable import SpotifyScreenLyricsCore

@Test
func parseSingleTimestampLine() {
    let lines = LRCParser.parse("[00:12.34]Hello world")

    #expect(lines == [
        LyricLine(time: 12.34, text: "Hello world")
    ])
}

@Test
func parseMultipleTimestampLine() {
    let lines = LRCParser.parse("[00:01.00][00:03.50]Repeat")

    #expect(lines == [
        LyricLine(time: 1.0, text: "Repeat"),
        LyricLine(time: 3.5, text: "Repeat")
    ])
}

@Test
func parseSortsLinesByTimestamp() {
    let source = """
    [00:05.00]Later
    [00:01.00]Earlier
    """

    let lines = LRCParser.parse(source)

    #expect(lines.map(\.text) == ["Earlier", "Later"])
}

@Test
func parseSkipsMetadataAndEmptyText() {
    let source = """
    [ar:Artist]
    [00:01.00]
    [00:02.00]Line
    """

    let lines = LRCParser.parse(source)

    #expect(lines == [
        LyricLine(time: 2.0, text: "Line")
    ])
}
