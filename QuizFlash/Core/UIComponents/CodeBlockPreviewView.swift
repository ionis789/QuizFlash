//
//  CodeBlockPreviewView.swift
//  QuizFlash
//
//  Renderer vizual pentru zone de tip cod (fontFamily == .monospaced).
//  Afișat în ZonePreviewView și ZoneContentView (modul read-only).
//
//  ─────────────────────────────────────────────────────────────
//  IMPORTANT — FontFamily.monospaced
//  ─────────────────────────────────────────────────────────────
//  Adaugă acest case în enum-ul tău FontFamily:
//
//    case monospaced
//
//  Și implementările:
//
//    func font(size: CGFloat, weight: Font.Weight) -> Font {
//        switch self {
//        case .system:    return .system(size: size, weight: weight)
//        case .monospaced: return .system(size: size, weight: weight, design: .monospaced)
//        // ... restul case-urilor
//        }
//    }
//
//    func uiFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
//        switch self {
//        case .system:    return .systemFont(ofSize: size, weight: weight)
//        case .monospaced: return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
//        // ... restul case-urilor
//        }
//    }
//  ─────────────────────────────────────────────────────────────

import SwiftUI

// =============================================================================
// MARK: - CodeBlockPreviewView
//
// View folosit în ZonePreviewView pentru a afișa un bloc de cod.
// Design:
//   ┌─────────────────────────────────────────┐
//   │ JAVA                              [copy] │  ← header bar
//   ├─────────────────────────────────────────┤
//   │ public class Animal {                   │
//   │     private String name;               │  ← code body
//   │     public Animal(String name) {        │    scroll orizontal pentru linii lungi
//   │         this.name = name;              │
//   │     }                                   │
//   │ }                                       │
//   └─────────────────────────────────────────┘
// =============================================================================

struct CodeBlockPreviewView: View {
    let zoneText: String
    var showCopyButton: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    private var helper: CodeZoneHelper { CodeZoneHelper(zoneText: zoneText) }

    // Culori adaptate la dark/light mode — seamless cu UI-ul aplicației
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar — limbaj + copy button
            headerBar

            // Code body — scrollabil orizontal pentru linii lungi
            codeBody
        }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.0), lineWidth: 1)
        )
            .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            // Puncte decorative (style Terminal)
            HStack(spacing: 5) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 8, height: 8)
                Circle().fill(Color.yellow.opacity(0.7)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 8, height: 8)
            }

            Spacer()

            // Limbaj
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation { copied = false }
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
            // fixedSize: permite textului să ocupe toată lățimea necesară
            // fără word-wrap care ar rupe indentarea codului
            .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(codeBg)
    }
}

// =============================================================================
// MARK: - InlineCodeView
//
// View pentru cod inline în text mixt (ex: "Metoda `toString()` returnează...")
// Folosit de MixedMathTextView dacă textul conține `backtick code`.
// =============================================================================

struct InlineCodeChip: View {
    let code: String
    @Environment(\.colorScheme) private var colorScheme

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

struct CodeZoneHelper {
    let displayLanguage: String
    let code: String

    init(zoneText: String) {
        let text = zoneText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Verificăm dacă textul începe cu un tag de limbaj, ex: "[LANG:swift]"
        if text.hasPrefix("[LANG:") {
            if let endBracketIndex = text.firstIndex(of: "]") {
                // Extragem limbajul dintre "[LANG:" și "]"
                let langStartIndex = text.index(text.startIndex, offsetBy: 6)
                let lang = String(text[langStartIndex..<endBracketIndex])
                
                self.displayLanguage = lang.uppercased()
                
                // Extragem restul textului (codul propriu-zis)
                var codeStartIndex = text.index(after: endBracketIndex)
                
                // Sărim peste linia nouă care urmează după tag (dacă există)
                if codeStartIndex < text.endIndex && text[codeStartIndex] == "\n" {
                    codeStartIndex = text.index(after: codeStartIndex)
                }
                
                self.code = String(text[codeStartIndex...])
                return
            }
        }
        
        // Fallback dacă nu există tag-ul [LANG:...]
        self.displayLanguage = "CODE"
        self.code = text
    }

    // Funcția care lipsea: Verifică dacă un ZoneModel este de tip cod
    static func isCodeZone(_ zone: ZoneModel) -> Bool {
        // Dacă zona are fontul monospaced setat manual din UI
        if zone.fontFamily == .mono {
            return true
        }
        
        // Fallback automat: Dacă textul brut începe cu tag-ul de cod
        let text = zone.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("[LANG:") {
            return true
        }
        
        return false
    }
}
