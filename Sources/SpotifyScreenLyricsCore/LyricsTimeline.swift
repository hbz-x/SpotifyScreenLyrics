import Foundation

public enum LyricsTimeline {
    public static func displayLines(for position: TimeInterval, lines: [LyricLine]) -> DisplayLyrics? {
        guard !lines.isEmpty else {
            return nil
        }

        var currentIndex = 0
        for (index, line) in lines.enumerated() {
            if line.time <= position {
                currentIndex = index
            } else {
                break
            }
        }

        let current = lines[currentIndex]
        let next = nextNonEmptyLine(after: currentIndex, in: lines)
        return DisplayLyrics(currentLine: current.text, nextLine: next?.text)
    }

    private static func nextNonEmptyLine(after index: Int, in lines: [LyricLine]) -> LyricLine? {
        let nextIndex = lines.index(after: index)
        guard nextIndex < lines.endIndex else {
            return nil
        }
        return lines[nextIndex...].first { !$0.text.isEmpty }
    }
}
