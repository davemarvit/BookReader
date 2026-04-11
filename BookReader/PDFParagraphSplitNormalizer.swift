import Foundation

struct PDFParagraphSplitNormalizer {
    
    static func normalize(_ text: String) -> String {
        var result = text
        
        // Pattern 1: Strong Indentation Cue
        // Look for sentence-ending punctuation, exactly one newline, ONE OR MORE space/tabs, then an uppercase letter.
        let indentPattern = #"([.!?]["']?)\n[ \t]+([\p{Lu}])"#
        if let regex = try? NSRegularExpression(pattern: indentPattern, options: []) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let left = nsText.substring(with: match.range(at: 1))
                let right = nsText.substring(with: match.range(at: 2))
                let replacement = "\(left)\n\n\(right)"
                guard let range = Range(match.range(at: 0), in: result) else { continue }
                result.replaceSubrange(range, with: replacement)
            }
        }
        
        return result
    }
}
