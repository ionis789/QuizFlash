//
//  MixedMathTextView.swift
//  QuizFlash
//
//  Created by Ion Socol on 20.02.2026.


import SwiftUI
import LaTeXSwiftUI

// MARK: - Componentele Textului
enum MathComponent: Identifiable {
    case text(String)
    case space
    case inlineMath(String)
    case blockMath(String)
    var id: UUID { UUID() }
}

// MARK: - Parser Inteligent (Separă textul normal de formule)
func parseMixedText(_ text: String) -> [MathComponent] {
    var result: [MathComponent] = []
    let scanner = Scanner(string: text)
    scanner.charactersToBeSkipped = nil

    while !scanner.isAtEnd {
        // Căutăm text normal până la primul '$'
        if let normalText = scanner.scanUpToString("$") {
            let words = normalText.components(separatedBy: .whitespaces)
            for (i, word) in words.enumerated() {
                if !word.isEmpty {
                    result.append(.text(word))
                }
                if i < words.count - 1 {
                    result.append(.space)
                }
            }
        }

        if scanner.isAtEnd { break }

        // Verificăm dacă e Block Math ($$) sau Inline Math ($)
        if scanner.scanString("$$") != nil {
            if let math = scanner.scanUpToString("$$") {
                result.append(.blockMath(math))
                _ = scanner.scanString("$$")
            } else {
                let rest = scanner.string[scanner.currentIndex...]
                result.append(.text("$$" + String(rest)))
                break
            }
        } else if scanner.scanString("$") != nil {
            if let math = scanner.scanUpToString("$") {
                result.append(.inlineMath(math))
                _ = scanner.scanString("$")
            } else {
                let rest = scanner.string[scanner.currentIndex...]
                result.append(.text("$" + String(rest)))
                break
            }
        }
    }
    return result
}

// MARK: - View Principal
struct MixedMathTextView: View {
    let text: String
    let font: Font
    let textColor: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            // Împărțim mai întâi textul în paragrafe pe baza noilor rânduri
            let paragraphs = text.components(separatedBy: "\n")
            
            ForEach(paragraphs, id: \.self) { paragraph in
                if !paragraph.isEmpty {
                    ParagraphView(text: paragraph, font: font, textColor: textColor, alignment: alignment)
                }
            }
        }
    }
}

// MARK: - Paragraph View (Aplică FlowLayout pentru wrapping)
private struct ParagraphView: View {
    let text: String
    let font: Font
    let textColor: Color
    let alignment: HorizontalAlignment

    var body: some View {
        let components = parseMixedText(text)
        
        // Dacă este o singură formulă mare, o randăm pe centru
        if components.count == 1, case .blockMath(let math) = components.first! {
            LaTeX("$$\(math)$$")
                .parsingMode(.all)
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
        } else {
            MathFlowLayout(alignment: alignment, spacing: 4, lineSpacing: 4) {
                ForEach(components) { component in
                    switch component {
                    case .text(let str):
                        Text(str)
                            .font(font)
                            .foregroundColor(textColor)
                    case .space:
                        Text(" ")
                            .font(font)
                    case .inlineMath(let math):
                        LaTeX("$\(math)$")
                            .parsingMode(.all)
                            .foregroundColor(textColor)
                    case .blockMath(let math):
                        LaTeX("$$\(math)$$")
                            .parsingMode(.all)
                            .foregroundColor(textColor)
                    }
                }
            }
        }
    }
}

// MARK: - Flow Layout (Aranjează cuvintele și formulele exact ca Apple Notes)
struct MathFlowLayout: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? UIScreen.main.bounds.width, subviews: subviews, spacing: spacing, lineSpacing: lineSpacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing, lineSpacing: lineSpacing)
        for row in result.rows {
            let rowXOffset: CGFloat
            switch alignment {
            case .leading: rowXOffset = 0
            case .center: rowXOffset = (bounds.width - row.width) / 2
            case .trailing: rowXOffset = bounds.width - row.width
            default: rowXOffset = 0
            }

            for element in row.elements {
                let x = bounds.minX + rowXOffset + element.xOffset
                let y = bounds.minY + row.yOffset
                // Centrează elementele vertical pe același rând
                let yOffset = (row.height - element.view.sizeThatFits(.unspecified).height) / 2
                element.view.place(at: CGPoint(x: x, y: y + yOffset), proposal: .unspecified)
            }
        }
    }

    struct FlowResult {
        var rows: [Row] = []
        var size: CGSize = .zero

        struct Row {
            var elements: [(view: LayoutSubview, xOffset: CGFloat)] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
            var yOffset: CGFloat = 0
        }

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat, lineSpacing: CGFloat) {
            var currentRow = Row()
            var y: CGFloat = 0

            for view in subviews {
                let viewSize = view.sizeThatFits(.unspecified)
                let isBlock = viewSize.width > maxWidth * 0.8 // Forțează blockMath să sară pe rând nou
                
                if currentRow.width + viewSize.width > maxWidth || isBlock {
                    if !currentRow.elements.isEmpty {
                        currentRow.yOffset = y
                        rows.append(currentRow)
                        y += currentRow.height + lineSpacing
                        currentRow = Row()
                    }
                }

                let xOffset = currentRow.width == 0 ? 0 : currentRow.width + spacing
                currentRow.elements.append((view, xOffset))
                currentRow.width += viewSize.width + (currentRow.width == 0 ? 0 : spacing)
                currentRow.height = max(currentRow.height, viewSize.height)
                
                if isBlock {
                    currentRow.yOffset = y
                    rows.append(currentRow)
                    y += currentRow.height + lineSpacing
                    currentRow = Row()
                }
            }

            if !currentRow.elements.isEmpty {
                currentRow.yOffset = y
                rows.append(currentRow)
                y += currentRow.height
            }

            size = CGSize(width: maxWidth, height: y)
        }
    }
}
