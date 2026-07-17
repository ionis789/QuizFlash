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

        XCTAssertFalse(literal.contains("\"\\\\neq\":"))
        XCTAssertFalse(literal.contains("\"\\\\ne\":"))
        XCTAssertFalse(literal.contains("\"\\\\epsilon\":"))
        XCTAssertTrue(literal.contains("\"\\\\eps\": \"\\\\epsilon\""))
    }

    func testHealNormalizesJSONEscapedLatexCommands() {
        let input = #"$x_1 \\neq x_2$ and $\forall x \in X$"#
        let healed = MathTextSanitizer.heal(input)

        XCTAssertTrue(healed.contains(#"$x_1 \neq x_2$"#))
        XCTAssertTrue(healed.contains(#"\forall"#))
        XCTAssertTrue(healed.contains(#"\in"#))
        XCTAssertFalse(healed.contains(#"\\neq"#))
        XCTAssertFalse(healed.contains(#"\\forall"#))
    }

    func testHealPreservesRawUnicodeMathNotation() {
        let input = "Fie f₁, …, fₘ : D(fᵢ) → ℝ. Atunci v ∈ V și n ≤ x."
        let healed = MathTextSanitizer.heal(input)

        XCTAssertTrue(healed.contains("f₁"))
        XCTAssertTrue(healed.contains("fₘ"))
        XCTAssertTrue(healed.contains("fᵢ"))
        XCTAssertTrue(healed.contains("→"))
        XCTAssertTrue(healed.contains("ℝ"))
        XCTAssertTrue(healed.contains("∈"))
        XCTAssertTrue(healed.contains("≤"))
        XCTAssertFalse(healed.contains(#"\to"#))
        XCTAssertFalse(healed.contains(#"\mathbb"#))
    }

    func testHealDoesNotRewriteCompactUnicodeDiagonalFormula() {
        let input = "Dacă S este matricea de trecere de la baza canonică la baza B, atunci diag(λ₁,…,λₙ) = S⁻¹·A·S."
        let healed = MathTextSanitizer.heal(input)
        let comparable = healed.replacingOccurrences(of: "\u{00A0}", with: " ")

        XCTAssertTrue(comparable.contains("diag(λ₁,…,λₙ) = S⁻¹·A·S"))
        XCTAssertFalse(healed.contains(#"\lambda"#))
        XCTAssertFalse(healed.contains(#"\cdot"#))
        XCTAssertFalse(healed.contains("$diag"))
    }

    func testHealDoesNotRewriteCompactUnicodeEigenSpaceFormula() {
        let input = "Subspațiul propriu V_λ = Ker(T - λ·1_V) = { u ∈ V | T(u) = λ·u }."
        let healed = MathTextSanitizer.heal(input)

        XCTAssertTrue(healed.contains("V_λ = Ker(T - λ·1_V)"))
        XCTAssertTrue(healed.contains("u ∈ V | T(u) = λ·u"))
        XCTAssertFalse(healed.contains(#"\lambda"#))
        XCTAssertFalse(healed.contains(#"\cdot"#))
        XCTAssertFalse(healed.contains("V_$"))
    }

    func testHealReattachesDetachedPunctuation() {
        let input = "în baza $B'$\n.\n\nFormula este $A=B$\n ;"
        let healed = MathTextSanitizer.heal(input)
        let normalizedSpacing = healed.replacingOccurrences(of: "\u{00A0}", with: " ")

        XCTAssertTrue(normalizedSpacing.contains("în baza $B'$."))
        XCTAssertTrue(normalizedSpacing.contains("Formula este $A=B$;"))
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

    func testStripTerminalZonePeriodPreservingWhitespaceKeepsAuthorSpacing() {
        XCTAssertEqual(
            MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace("\n\n  answer.  \n"),
            "\n\n  answer  \n"
        )
        XCTAssertEqual(
            MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace("\n\n  answer  \n"),
            "\n\n  answer  \n"
        )
        XCTAssertEqual(
            MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace("\n  etc...  \n"),
            "\n  etc...  \n"
        )
        XCTAssertEqual(
            MathTextSanitizer.stripTerminalZonePeriodPreservingWhitespace(".  \n"),
            "  \n"
        )
    }
}
