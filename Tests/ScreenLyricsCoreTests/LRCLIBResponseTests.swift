import Foundation
import Testing
@testable import ScreenLyricsCore

@Test
func decodeLRCLIBResponse() throws {
    let json = """
    {
      "id": 1,
      "trackName": "Song",
      "artistName": "Artist",
      "albumName": "Album",
      "duration": 123,
      "plainLyrics": "Line",
      "syncedLyrics": "[00:01.00]Line"
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(LRCLIBResponse.self, from: json)

    #expect(response.trackName == "Song")
    #expect(response.artistName == "Artist")
    #expect(response.syncedLyrics == "[00:01.00]Line")
}
