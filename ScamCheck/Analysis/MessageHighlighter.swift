//
//  MessageHighlighter.swift
//  ScamCheck
//
//  WHAT THIS FILE IS
//  Splits a message into pieces: normal text and highlighted text.
//  The result card turns these pieces into styled text.
//
//  WHY IT IS SEPARATE FROM THE VIEW
//  Overlapping highlights are easy to get wrong (two reasons can point at
//  the same words). Keeping this as plain Swift means it can be unit tested
//  without any UI.
//
//  RULES
//  - Spans that fall outside the message are ignored, never crash.
//  - Overlapping or touching spans are merged into one highlight.
//  - Joining all pieces back together always gives the original message.
//

import Foundation

nonisolated struct HighlightSegment: Equatable, Sendable {
    let text: String
    let isHighlighted: Bool
}

nonisolated enum MessageHighlighter {

    static func segments(for message: String, highlighting spans: [TextSpan]) -> [HighlightSegment] {
        let characters = Array(message)
        let count = characters.count

        // 1. Keep only spans that fit inside the message, in reading order.
        let valid = spans
            .filter { $0.start >= 0 && $0.length > 0 && $0.end <= count }
            .sorted { $0.start < $1.start }

        // 2. Merge spans that overlap or touch.
        var merged: [TextSpan] = []
        for span in valid {
            if let last = merged.last, span.start <= last.end {
                let newEnd = max(last.end, span.end)
                merged[merged.count - 1] = TextSpan(start: last.start, length: newEnd - last.start)
            } else {
                merged.append(span)
            }
        }

        // 3. Walk through the message, emitting normal and highlighted pieces.
        var result: [HighlightSegment] = []
        var cursor = 0
        for span in merged {
            if span.start > cursor {
                result.append(HighlightSegment(text: String(characters[cursor..<span.start]), isHighlighted: false))
            }
            result.append(HighlightSegment(text: String(characters[span.start..<span.end]), isHighlighted: true))
            cursor = span.end
        }
        if cursor < count {
            result.append(HighlightSegment(text: String(characters[cursor..<count]), isHighlighted: false))
        }
        return result
    }
}
