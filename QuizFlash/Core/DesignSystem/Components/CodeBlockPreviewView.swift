//
//  CodeBlockPreviewView.swift
//  QuizFlash
//

import SwiftUI

// =============================================================================
// MARK: - CodeBlockPreviewView
//
// Design:
//   ┌─────────────────────────────────────────┐
//   │ JAVA                              [copy]│  ← header bar
//   ├─────────────────────────────────────────┤
//   │ public class Animal {                   │
//   │     private String name;                │  ← code body
//   │     public Animal(String name) {        │    horizontal scroll for long lines
//   │         this.name = name;               │
//   │     }                                   │
//   │ }                                       │
//   └─────────────────────────────────────────┘
// =============================================================================

/// A styled code block view that renders raw source code with a terminal-inspired
/// header bar showing the detected language and a copy-to-clipboard button.
///
/// Supports an optional `[LANG:swift]` prefix tag to identify the programming language.
/// If no tag is present, defaults to `"CODE"` as the header label.
struct CodeBlockPreviewView: View {

    // MARK: - Configuration

    /// The raw zone text, optionally prefixed with `[LANG:language]`.
    let zoneText: String

    /// When `true`, a copy-to-clipboard button is shown in the header bar. Defaults to `true`.
    var showCopyButton: Bool = true

    // MARK: - State

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false
    @State private var copiedResetTask: Task<Void, Never>?

    // MARK: - Derived

    private var helper: CodeZoneHelper { CodeZoneHelper(zoneText: zoneText) }

    // Adaptive colours for dark/light mode — seamless with the application UI.
    private var headerBg: Color {
        colorScheme == .dark
            ? Color(white: 0.18)
        : Color(white: 0.88)
    }
    private var codeBg: Color {
        colorScheme == .dark
            ? Color(white: 0.12)
        : Color(white: 0.94)
    }
    private var langColor: Color {
        colorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }
    private var codeColor: Color {
        colorScheme == .dark ? Color(red: 0.85, green: 0.95, blue: 0.85) : Color(red: 0.1, green: 0.3, blue: 0.1)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar — language label + copy button
            headerBar

            // Code body — horizontal scroll for lines that exceed the view width
            codeBody
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.0), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .onDisappear {
            copiedResetTask?.cancel()
            copiedResetTask = nil
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Decorative traffic-light dots (Terminal style)
            HStack(spacing: 5) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 8, height: 8)
                Circle().fill(Color.yellow.opacity(0.7)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 8, height: 8)
            }

            Spacer()

            // Language label
            Text(helper.displayLanguage)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(langColor)

            Spacer()

            // Copy button
            if showCopyButton {
                copyButton
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(headerBg)
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = helper.code
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                copied = true
            }
            copiedResetTask?.cancel()
            copiedResetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation {
                    copied = false
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                if copied {
                    Text("Copied!")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(copied ? Color.green : langColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: copied)
    }

    // MARK: - Code Body

    private var codeBody: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(helper.code)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(codeColor)
                .lineSpacing(4)
                .textSelection(.enabled)
                // fixedSize prevents word-wrap that would break code indentation.
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(codeBg)
    }
}

// =============================================================================
// MARK: - InlineCodeChip
//
// Renders inline code inside mixed text (e.g. "The method `toString()` returns…").
// Used by MixedMathTextView when the content contains `backtick code`.
// =============================================================================

/// A styled chip that renders a short inline code snippet within mixed text.
struct InlineCodeChip: View {

    // MARK: - Configuration

    /// The raw code string to display.
    let code: String

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Body

    var body: some View {
        Text(code)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(colorScheme == .dark
                ? Color(red: 0.85, green: 0.95, blue: 0.85)
                : Color(red: 0.1, green: 0.3, blue: 0.1)
            )
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.88))
            )
    }
}

// =============================================================================
// MARK: - Preview Helper
// =============================================================================

#if DEBUG
struct CodeBlockPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            CodeBlockPreviewView(zoneText: "[LANG:java]\npublic class Animal {\n    private String name;\n\n    public Animal(String name) {\n        this.name = name;\n    }\n\n    public String getName() {\n        return this.name;\n    }\n}")

            CodeBlockPreviewView(zoneText: "def fibonacci(n):\n    if n <= 1:\n        return n\n    return fibonacci(n-1) + fibonacci(n-2)")

            CodeBlockPreviewView(zoneText: "[LANG:swift]\nlet numbers = [1, 2, 3, 4, 5]\nlet doubled = numbers.map { $0 * 2 }\nprint(doubled) // [2, 4, 6, 8, 10]")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif

// =============================================================================
// MARK: - CodeZoneHelper
// =============================================================================

/// A value type that parses a raw zone text string and extracts the programming
/// language identifier and code body.
///
/// Supports an optional `[LANG:language]` prefix tag:
/// ```
/// [LANG:swift]
/// let x = 42
/// ```
/// When no tag is present, `displayLanguage` defaults to `"CODE"`.
struct CodeZoneHelper {

    // MARK: - Properties

    /// The uppercased language label to display in the header bar (e.g. `"SWIFT"`, `"JAVA"`).
    let displayLanguage: String

    /// The extracted code body, with the language tag and trailing newline stripped.
    let code: String

    // MARK: - Initializer

    init(zoneText: String) {
        let text = zoneText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check whether the text starts with a language tag, e.g. "[LANG:swift]".
        if text.hasPrefix("[LANG:") {
            if let endBracketIndex = text.firstIndex(of: "]") {
                // Extract the language identifier between "[LANG:" and "]".
                let langStartIndex = text.index(text.startIndex, offsetBy: 6)
                let lang = String(text[langStartIndex..<endBracketIndex])

                self.displayLanguage = lang.uppercased()

                // Extract the remaining text (the actual code).
                var codeStartIndex = text.index(after: endBracketIndex)

                // Skip the newline following the tag, if present.
                if codeStartIndex < text.endIndex && text[codeStartIndex] == "\n" {
                    codeStartIndex = text.index(after: codeStartIndex)
                }

                self.code = String(text[codeStartIndex...])
                return
            }
        }

        // Fallback if no [LANG:…] tag is present.
        self.displayLanguage = "CODE"
        self.code = text
    }

    // MARK: - Static Helpers

    /// Determines whether a `ZoneModel` represents code content.
    ///
    /// A zone is classified as code if it has a monospaced font family set,
    /// or if its raw text begins with a `[LANG:…]` tag.
    ///
    /// - Parameter zone: The zone model to inspect.
    /// - Returns: `true` if the zone should be rendered as a code block.
    static func isCodeZone(_ zone: ZoneModel) -> Bool {
        // If the zone has a monospaced font manually set from the UI.
        if zone.fontFamily == .mono {
            return true
        }

        // Automatic fallback: check raw text for the code tag.
        let text = zone.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("[LANG:") {
            return true
        }

        return false
    }
}
