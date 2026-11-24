//
//  QuoteAndHighlightTests.swift
//  ScamCheckTests
//
//  WHAT THESE TESTS PROVE
//  - A quote is only accepted if it is really in the message.
//  - Positions are correct even with emoji (a common source of bugs).
//  - Highlighting never loses or duplicates text, even when highlights overlap
//    or a span is out of range.
//
//  All messages here are invented (synthetic), as CLAUDE.md requires.
//

import Testing
@testable import ScamCheck

struct QuoteLocatorTests {

    @Test func findsExactQuoteAndPosition() {
        let message = "Your parcel is held. Pay now at bit.ly/x1"
        let found = QuoteLocator.locate("Pay now", in: message)
        #expect(found?.exactText == "Pay now")
        #expect(found?.span == TextSpan(start: 21, length: 7))
    }

    @Test func rejectsQuoteThatIsNotInTheMessage() {
        #expect(QuoteLocator.locate("send OTP", in: "Hello, see you at 6") == nil)
    }

    @Test func rejectsEmptyQuote() {
        #expect(QuoteLocator.locate("", in: "Anything") == nil)
    }

    @Test func caseInsensitiveMatchKeepsTheMessageSpelling() {
        let found = QuoteLocator.locate("otp", in: "Share your OTP now", caseInsensitive: true)
        #expect(found?.exactText == "OTP")
    }

    @Test func caseSensitiveByDefault() {
        #expect(QuoteLocator.locate("otp", in: "Share your OTP now") == nil)
    }

    @Test func emojiDoNotShiftPositions() {
        let message = "🎉🎁 You won! Pay the processing fee"
        let found = QuoteLocator.locate("processing fee", in: message)
        let text = found.flatMap { $0.span.substring(in: message) }.map(String.init)
        #expect(text == "processing fee")
    }

    @Test func reasonCannotBeBuiltWithInventedQuote() {
        let reason = Reason(
            category: .credentialRequest,
            quote: "share your PIN",
            explanation: "test",
            in: "Your balance is Rs 2,000."
        )
        #expect(reason == nil)
    }
}

struct MessageHighlighterTests {

    @Test func splitsAroundOneSpan() {
        let segments = MessageHighlighter.segments(for: "abcdef", highlighting: [TextSpan(start: 2, length: 2)])
        #expect(segments == [
            HighlightSegment(text: "ab", isHighlighted: false),
            HighlightSegment(text: "cd", isHighlighted: true),
            HighlightSegment(text: "ef", isHighlighted: false),
        ])
    }

    @Test func mergesOverlappingSpans() {
        let segments = MessageHighlighter.segments(
            for: "abcdefg",
            highlighting: [TextSpan(start: 2, length: 3), TextSpan(start: 1, length: 3)]
        )
        #expect(segments == [
            HighlightSegment(text: "a", isHighlighted: false),
            HighlightSegment(text: "bcde", isHighlighted: true),
            HighlightSegment(text: "fg", isHighlighted: false),
        ])
    }

    @Test func ignoresSpansOutsideTheMessage() {
        let segments = MessageHighlighter.segments(for: "abc", highlighting: [TextSpan(start: 2, length: 5)])
        #expect(segments == [HighlightSegment(text: "abc", isHighlighted: false)])
    }

    @Test func emptyMessageGivesNoSegments() {
        #expect(MessageHighlighter.segments(for: "", highlighting: []).isEmpty)
    }

    @Test func joiningSegmentsGivesBackTheOriginal() {
        let message = "🚚 Parcel held. Pay ₹25 at bit.ly/abc within 2 hrs"
        let spans = [TextSpan(start: 16, length: 3), TextSpan(start: 27, length: 6), TextSpan(start: 0, length: 1)]
        let joined = MessageHighlighter.segments(for: message, highlighting: spans).map(\.text).joined()
        #expect(joined == message)
    }
}
