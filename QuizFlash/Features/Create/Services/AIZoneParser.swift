import Foundation

struct AIZoneParser {
    static func parse(text: String) -> ZoneModel {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 🛡️ REPARAREA SUPREMĂ: Tăiem dolarii abuzivi ÎNAINTE să spargem textul pe rânduri!
        // Asta previne lăsarea unui $ desperecheat pe prima sau ultima linie.
        while cleanText.hasPrefix("$") && cleanText.hasSuffix("$") && !cleanText.hasPrefix("$$") {
            let inner = String(cleanText.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if inner.contains(" ") || inner.contains("\n") {
                cleanText = inner
            } else {
                break
            }
        }
        
        // 1. Acum putem sparge textul pe rânduri în siguranță
        let lines = cleanText.components(separatedBy: "\n")
        var blocks: [String] = []
        var currentBlock = ""
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Detectăm listele
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentBlock = ""
                }
                blocks.append(trimmed)
            } else if trimmed.isEmpty {
                // Rând gol = final de paragraf
                if !currentBlock.isEmpty {
                    blocks.append(currentBlock.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentBlock = ""
                }
            } else {
                currentBlock += (currentBlock.isEmpty ? "" : "\n") + line
            }
        }
        
        if !currentBlock.isEmpty {
            blocks.append(currentBlock.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        blocks = blocks.filter { !$0.isEmpty }
        
        if blocks.isEmpty { return .empty() }
        if blocks.count == 1 { return parseSingleBlock(blocks[0]) }
        
        let childZones = blocks.map { parseSingleBlock($0) }
        return ZoneModel.container(direction: .vertical, children: childZones)
    }

    private static func parseSingleBlock(_ text: String) -> ZoneModel {
        var zone = ZoneModel.text("")
        var contentToClean = text.trimmingCharacters(in: .whitespaces)
        
        if contentToClean.hasPrefix("- ") || contentToClean.hasPrefix("* ") {
            zone.hasBullet = true
            contentToClean = String(contentToClean.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        
        if contentToClean.hasPrefix("$$") && contentToClean.hasSuffix("$$") {
            zone.textAlignment = .center
            zone.text = contentToClean
            return zone
        }
        
        zone.text = contentToClean
        return zone
    }
}
