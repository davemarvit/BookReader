import Foundation

struct PDFImportTextCleanup {
    private static let preservedHyphenatedWords: Set<String> = {
        guard let url = Bundle.main.url(forResource: "pdf_hyphenation_preserve_list", withExtension: "txt"),
              let string = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return Set(
            string
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }()

    static func normalizeExtractedPDFText(_ text: String) -> String {
        var result = text
        result = replaceCandidates(in: result, pattern: #"([\p{L}]+)-[ \t]*\n[ \t]*([\p{L}]+)"#)
        result = replaceCandidates(in: result, pattern: #"([\p{L}]+)-[ ]+([\p{L}]+)"#)
        return result
    }

    private static func replaceCandidates(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        let nsText = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsText.length))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let leftRange = Range(match.range(at: 1), in: result),
                  let rightRange = Range(match.range(at: 2), in: result) else {
                continue
            }

            let left = String(result[leftRange])
            let right = String(result[rightRange])
            let hyphenated = "\(left)-\(right)".lowercased()
            let replacement = preservedHyphenatedWords.contains(hyphenated) ? "\(left)-\(right)" : "\(left)\(right)"
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }
}
