//
//  MathTextSanitizerTests.swift
//  QuizFlashTests
//
//  Guards shared KaTeX macro aliases against glyph-changing overrides.
//

import XCTest
@testable import QuizFlash

final class MathTextSanitizerTests: XCTestCase {
    func testKatexExtraMacrosStayConservative() {
        let macros = MathTextSanitizer.katexExtraMacros

        XCTAssertEqual(macros["\\eps"], "\\epsilon")
        XCTAssertNil(macros["\\epsilon"])
        XCTAssertNil(macros["\\neq"])
        XCTAssertNil(macros["\\ne"])
    }

    func testKatexExtraMacrosJSLiteralDoesNotContainDangerousOverrides() {
        let literal = MathTextSanitizer.katexExtraMacrosJSObjectLiteral

        XCTAssertFalse(literal.contains("\\\\neq"))
        XCTAssertFalse(literal.contains("\\\\ne"))
        XCTAssertFalse(literal.contains("\"\\\\epsilon\""))
        XCTAssertTrue(literal.contains("\"\\\\eps\": \"\\\\epsilon\""))
    }

    func testHealNormalizesJSONEscapedLatexCommands() {
        let input = #"$x_1 \\neq x_2$ and $\forall x \in X$"#
        let healed = MathTextSanitizer.heal(input)

        XCTAssertTrue(healed.contains(#"$x_1 \neq x_2$"#))
        XCTAssertTrue(healed.contains(#"$\forall x \in X$"#))
        XCTAssertFalse(healed.contains(#"\\neq"#))
        XCTAssertFalse(healed.contains(#"\\forall"#))
    }

    func testHealReattachesDetachedPunctuation() {
        let input = "în baza $B'$\n.\n\nFormula este $A=B$\n ;"
        let healed = MathTextSanitizer.heal(input)

        XCTAssertTrue(healed.contains("în baza $B'$."))
        XCTAssertTrue(healed.contains("Formula este $A=B$;"))
        XCTAssertFalse(healed.contains("\n."))
        XCTAssertFalse(healed.contains("\n ;"))
    }

    func testHealAppliesWidowControlToFinalBreak() {
        let input = "coordonatele lui $T(v)$ în baza $B'$."
        let healed = MathTextSanitizer.heal(input)

        XCTAssertTrue(healed.contains("baza\u{00A0}$B'$."))
    }

    func testStripTerminalZonePeriodRemovesOnlySingleFinalDot() {
        XCTAssertEqual(
            MathTextSanitizer.stripTerminalZonePeriod("în baza $B'$."),
            "în baza $B'$"
        )
        XCTAssertEqual(
            MathTextSanitizer.stripTerminalZonePeriod("etc..."),
            "etc..."
        )
        XCTAssertEqual(
            MathTextSanitizer.stripTerminalZonePeriod("ce urmează?"),
            "ce urmează?"
        )
    }
}
