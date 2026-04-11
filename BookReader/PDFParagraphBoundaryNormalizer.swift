import Foundation

struct PDFParagraphBoundaryNormalizer {
    
    static func normalize(_ text: String) -> String {
        let blocks = text.components(separatedBy: "\n\n")
        if blocks.count <= 1 { return text }
        
        var normalizedBlocks: [String] = []
        normalizedBlocks.append(blocks[0])
        
        // Includes typical terminal punctuation including quotes to avoid merging dialogue ends
        let strongPunctuation = CharacterSet(charactersIn: ".!?\"'")
        
        for i in 1..<blocks.count {
            let previous = normalizedBlocks.last!
            let next = blocks[i]
            
            let prevTrimmed = previous.trimmingCharacters(in: .whitespacesAndNewlines)
            let nextTrimmed = next.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if prevTrimmed.isEmpty || nextTrimmed.isEmpty {
                normalizedBlocks.append(next)
                continue
            }
            
            let prevEndsWithHyphen = prevTrimmed.hasSuffix("-")
            let prevEndsWithComma = prevTrimmed.hasSuffix(",")
            let prevEndsWithStrongPunct = prevTrimmed.unicodeScalars.last.map { strongPunctuation.contains($0) } ?? false
            
            let nextStartsLowercase = nextTrimmed.first?.isLowercase ?? false
            
            var shouldMerge = false
            
            // Core Conservative Merge Logic
            if prevEndsWithHyphen {
                shouldMerge = true
            } else if prevEndsWithComma {
                shouldMerge = true
            } else if !prevEndsWithStrongPunct && nextStartsLowercase {
                shouldMerge = true
            }
            
            if shouldMerge {
                // Collapse the double newline boundary into a single newline
                // This converts a fractured block back into an intra-paragraph line wrap
                let merged = previous + "\n" + next
                normalizedBlocks[normalizedBlocks.count - 1] = merged
            } else {
                normalizedBlocks.append(next)
            }
        }
        
        return normalizedBlocks.joined(separator: "\n\n")
    }
}
