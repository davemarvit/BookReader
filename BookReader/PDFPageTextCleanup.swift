import Foundation

struct PDFPageTextCleanup {
    
    static func cleanPageText(_ text: String, documentTitle: String?) -> String {
        let lines = text.components(separatedBy: .newlines)
        if lines.isEmpty { return text }
        
        var nonEmptyIndices = [Int]()
        for (i, line) in lines.enumerated() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                nonEmptyIndices.append(i)
            }
        }
        
        if nonEmptyIndices.isEmpty { return text }
        
        var indicesToRemove = Set<Int>()
        
        // Front checks: first 1 to 3 non-empty lines
        let frontLimit = min(3, nonEmptyIndices.count)
        for i in 0..<frontLimit {
            let idx = nonEmptyIndices[i]
            if isHeaderOrFooterCandidate(lines[idx], documentTitle: documentTitle) {
                indicesToRemove.insert(idx)
            }
        }
        
        // Back checks: last 1 to 2 non-empty lines
        let backLimit = min(2, nonEmptyIndices.count)
        for i in 0..<backLimit {
            let revIndex = nonEmptyIndices.count - 1 - i
            let idx = nonEmptyIndices[revIndex]
            if isHeaderOrFooterCandidate(lines[idx], documentTitle: documentTitle) {
                indicesToRemove.insert(idx)
            }
        }
        
        var resultLines = [String]()
        for (i, line) in lines.enumerated() {
            if !indicesToRemove.contains(i) {
                resultLines.append(line)
            }
        }
        
        return resultLines.joined(separator: "\n")
    }
    
    private static func isHeaderOrFooterCandidate(_ line: String, documentTitle: String?) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Standalone page number
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil {
            return true
        }
        
        // 2. Page number followed by uppercase/title text (e.g., "26 THE WORLDS OF HERMAN KAHN")
        if trimmed.range(of: #"^\d+\s+[A-Z0-9][A-Z0-9\s'&:,\.\-]+$"#, options: .regularExpression) != nil {
            return true
        }
        
        // 2b. Uppercase/title text followed by page number (e.g., "THE WORLDS OF HERMAN KAHN 26")
        if trimmed.range(of: #"^[A-Z0-9][A-Z0-9\s'&:,\.\-]+\s+\d+$"#, options: .regularExpression) != nil {
            return true
        }
        
        // 2c. Page number followed by short Title Case heading (e.g., "14 Chapter Three")
        if trimmed.range(of: #"^\d+\s+[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,5}$"#, options: .regularExpression) != nil {
            return true
        }
        
        // 2d. Short Title Case heading followed by page number (e.g., "Chapter Three 14")
        if trimmed.range(of: #"^[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,5}\s+\d+$"#, options: .regularExpression) != nil {
            return true
        }
        
        // 3. Line matches document title (case-insensitive)
        if let title = documentTitle, !title.trimmingCharacters(in: .whitespaces).isEmpty {
            let lowerLine = trimmed.lowercased()
            let lowerTitle = title.lowercased()
            
            if lowerLine == lowerTitle {
                return true
            }
            
            // Matches title with a page number
            if lowerLine.hasPrefix(lowerTitle) {
                let remainder = lowerLine.dropFirst(lowerTitle.count).trimmingCharacters(in: .whitespaces)
                if remainder.range(of: #"^\d+$"#, options: .regularExpression) != nil {
                    return true
                }
            }
            if lowerLine.hasSuffix(lowerTitle) {
                let remainder = lowerLine.dropLast(lowerTitle.count).trimmingCharacters(in: .whitespaces)
                if remainder.range(of: #"^\d+$"#, options: .regularExpression) != nil {
                    return true
                }
            }
        }
        
        return false
    }
}
