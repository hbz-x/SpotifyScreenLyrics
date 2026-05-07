# SpotifyScreenLyrics

A native macOS menu bar app that displays synced lyrics for the currently playing Spotify desktop track.

## Build

```sh
swift build
swift test
Scripts/package_app.sh
open .build/SpotifyScreenLyrics.app
```

On first launch, macOS will ask for permission to control Spotify. Allow it so the app can read the current track and playback position.

## Notes

- Lyrics come from LRCLIB.
- Spotify OAuth is not required.
- The v1 app focuses on a draggable floating lyrics overlay and a small menu bar controller.

## Privacy and Security

- The app uses macOS Apple Events to read Spotify's current track, artist, album, duration, playback position, and play/pause state.
- When lyrics are not already cached locally, the app sends the current track name, artist, album, and duration to `https://lrclib.net/api/get`.
- Synced lyrics are cached locally under `~/Library/Application Support/SpotifyScreenLyrics/LyricsCache/`.
- Imported SpotifyScreenLyrics cache manifests only accept local `.lrc` file names inside the import folder's `lyrics/` directory.
