# ScreenLyrics

A native macOS menu bar app that displays synced lyrics for the currently playing Spotify desktop track.

## Build

```sh
swift build
swift test
Scripts/package_app.sh
open .build/ScreenLyrics.app
```

On first launch, macOS will ask for permission to control Spotify. Allow it so the app can read the current track and playback position.

## Notes

- Lyrics come from LRCLIB.
- Spotify OAuth is not required.
- The v1 app focuses on a draggable floating lyrics overlay and a small menu bar controller.
