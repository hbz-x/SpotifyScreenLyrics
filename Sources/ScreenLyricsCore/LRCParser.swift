import Foundation

public enum LRCParser {
    public static func parse(_ source: String) -> [LyricLine] {
        source
            .split(whereSeparator: \.isNewline)
            .flatMap { parseLine(String($0)) }
            .filter { !$0.text.isEmpty }
            .sorted { lhs, rhs in
                if lhs.time == rhs.time {
                    return lhs.text < rhs.text
                }
                return lhs.time < rhs.time
            }
    }

    private static func parseLine(_ line: String) -> [LyricLine] {
        let matches = timestampMatches(in: line)
        guard !matches.isEmpty else {
            return []
        }

        let textStart = matches.last?.upperBound ?? line.startIndex
        let text = String(line[textStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return matches.compactMap { match in
            guard let timestamp = parseTimestamp(String(line[match])) else {
                return nil
            }
            return LyricLine(time: timestamp, text: text)
        }
    }

    private static func timestampMatches(in line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var cursor = line.startIndex

        while cursor < line.endIndex, line[cursor] == "[" {
            guard let close = line[cursor...].firstIndex(of: "]") else {
                break
            }
            let afterClose = line.index(after: close)
            ranges.append(cursor..<afterClose)
            cursor = afterClose
        }

        return ranges
    }

    private static func parseTimestamp(_ timestamp: String) -> TimeInterval? {
        let trimmed = timestamp.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let minutes = TimeInterval(parts[0]),
              let seconds = TimeInterval(parts[1]) else {
            return nil
        }

        return minutes * 60 + seconds
    }
}
