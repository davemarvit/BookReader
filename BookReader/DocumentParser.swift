import Foundation
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

struct ParsedDocument {
    let title: String
    let author: String?
    let text: String
    let paragraphCount: Int
    let coverImage: Data?
}

class DocumentParser {
    
    static func parse(url: URL) -> ParsedDocument? {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let ext = url.pathExtension.lowercased()
        
        if ext == "pdf" {
            return parsePDF(url: url)
        } else if ext == "txt" {
            return parseText(url: url)
        } else if ext == "epub" {
            return parseEPUB(url: url)
        }
        
        return nil
    }
    
    // MARK: - Smart Text Cleaning
    
    private static func smartClean(_ text: String) -> String {
        // 1. Normalize line endings
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        
        // 2. Split into "blocks" based on double newlines (paragraphs)
        let blocks = normalized.components(separatedBy: "\n\n")
        
        var cleanedBlocks: [String] = []
        
        for block in blocks {
            // Within a block, join lines that seem to be "hard wrapped".
            // A hard wrap typically happens if a line ends with a letter or comma, not a period.
            // But we need to be careful not to merge lists or headers.
            
            let lines = block.components(separatedBy: "\n")
            var mergedBlock = ""
            
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                
                mergedBlock += trimmed
                
                // Decide whether to add a space or a newline
                if index < lines.count - 1 {
                    if shouldMergeNextLine(currentLine: trimmed) {
                        mergedBlock += " "
                    } else {
                        mergedBlock += "\n"
                    }
                }
            }
            
            if !mergedBlock.isEmpty {
                // Chunk HUGE blocks to prevent TTS failure
                let subBlocks = chunkBlock(mergedBlock, limit: 2000)
                cleanedBlocks.append(contentsOf: subBlocks)
            }
        }
        
        return cleanedBlocks.joined(separator: "\n\n")
    }
    
    private static func chunkBlock(_ text: String, limit: Int = 1000) -> [String] {
        if text.count <= limit { return [text] }
        
        var chunks: [String] = []
        // Split by sentence ending punctuation
        let sentences = text.components(separatedBy: ". ") // Simple split, could be better
        
        var currentChunk = ""
        for sentence in sentences {
            let candidate = currentChunk.isEmpty ? sentence : currentChunk + ". " + sentence
            if candidate.count > limit {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk + ".")
                }
                currentChunk = sentence
            } else {
                currentChunk = candidate
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        // Fallback: If a single sentence is huge, force split
        return chunks.flatMap { chunk -> [String] in
            if chunk.count > limit {
               // Hard split
               var result: [String] = []
               var current = chunk
               while current.count > limit {
                   let index = current.index(current.startIndex, offsetBy: limit)
                   result.append(String(current[..<index]))
                   current = String(current[index...])
               }
               result.append(current)
               return result
            }
            return [chunk]
        }
    }
    
    private static func shouldMergeNextLine(currentLine: String) -> Bool {
        // If line ends in hyphen, definitely merge (and remove hyphen? Optional polish)
        if currentLine.hasSuffix("-") { return true }
        
        // If line ends in punctuation [.?!], likely end of sentence -> Keep newline
        let punctuation = CharacterSet(charactersIn: ".?!:;\"”")
        if let lastChar = currentLine.unicodeScalars.last, punctuation.contains(lastChar) {
            return false
        }
        
        // Otherwise (ends in letter, comma, etc), merge
        return true
    }
    
    // MARK: - Parsing Logic
    
    private static func parsePDF(url: URL) -> ParsedDocument? {
        guard let pdf = PDFDocument(url: url) else { return nil }
        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let pageText = page.string {
                fullText += pageText + "\n\n"
            }
        }
        let title = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String ?? url.lastPathComponent
        
        // Generate Thumbnail
        var coverData: Data? = nil
        if let firstPage = pdf.page(at: 0) {
            let thumbnail = firstPage.thumbnail(of: CGSize(width: 300, height: 450), for: .mediaBox)
            coverData = thumbnail.jpegData(compressionQuality: 0.8)
        }
        
        let cleanedText = smartClean(fullText)

        let count = cleanedText.components(separatedBy: "\n\n").count
        let author = pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        return ParsedDocument(title: title, author: author, text: cleanedText, paragraphCount: count, coverImage: coverData)
    }
    
     private static func parseEPUB(url: URL) -> ParsedDocument? {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            try fileManager.unzipItem(at: url, to: tempDir)
            
            // 1. Find container.xml
            let containerURL = tempDir.appendingPathComponent("META-INF/container.xml")
            guard let containerData = try? Data(contentsOf: containerURL),
                  let containerXML = String(data: containerData, encoding: .utf8) else { return nil }
            
            guard let opfPath = findAttribute(in: containerXML, attribute: "full-path") else { return nil }
            let opfURL = tempDir.appendingPathComponent(opfPath)
            let opfDir = opfURL.deletingLastPathComponent()
            
            // 2. Parse OPF
            guard let opfData = try? Data(contentsOf: opfURL),
                  let opfContent = String(data: opfData, encoding: .utf8) else { return nil }
            
            let spineRefs = findSpineRefs(in: opfContent)
            let manifest = findManifestMap(in: opfContent)
            
            // 3. Extract text
            var fullText = ""
            
            for idref in spineRefs {
                if let href = manifest[idref] {
                    let htmlURL = opfDir.appendingPathComponent(href)
                    if let htmlContent = try? String(contentsOf: htmlURL) {
                        fullText += stripHTML(htmlContent) + "\n\n"
                    }
                }
            }
            
            let title = findTagContent(in: opfContent, tag: "dc:title") ?? url.lastPathComponent
            let author = findTagContent(in: opfContent, tag: "dc:creator")
            
            // 4. Extract Cover
            var coverData: Data? = nil
            // Method A: Look for <item properties="cover-image" href="...">
            if let coverHref = regexFirstMatch(pattern: "href=\"([^\"]+)\"[^>]*properties=\"cover-image\"", in: opfContent) ??
                               regexFirstMatch(pattern: "properties=\"cover-image\"[^>]*href=\"([^\"]+)\"", in: opfContent) {
                let coverURL = opfDir.appendingPathComponent(coverHref)
                coverData = try? Data(contentsOf: coverURL)
            }
            // Method B: Look for <meta name="cover" content="item_id"> -> Look up item_id in manifest
            if coverData == nil,
               let coverID = regexFirstMatch(pattern: "<meta[^>]*name=\"cover\"[^>]*content=\"([^\"]+)\"", in: opfContent) ??
                             regexFirstMatch(pattern: "<meta[^>]*content=\"([^\"]+)\"[^>]*name=\"cover\"", in: opfContent),
               let coverHref = manifest[coverID] {
                let coverURL = opfDir.appendingPathComponent(coverHref)
                coverData = try? Data(contentsOf: coverURL)
            }
            
            try? fileManager.removeItem(at: tempDir)
            
            let cleanedText = smartClean(fullText)
            let count = cleanedText.components(separatedBy: "\n\n").count
            return ParsedDocument(title: title, author: author, text: cleanedText, paragraphCount: count, coverImage: coverData)
            
        } catch {
            print("EPUB Error: \(error)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }
    
    private static func parseText(url: URL) -> ParsedDocument? {
        do {
            let text = try String(contentsOf: url)
            let cleanedText = smartClean(text)
            let count = cleanedText.components(separatedBy: "\n\n").count
            return ParsedDocument(title: url.lastPathComponent, author: nil, text: cleanedText, paragraphCount: count, coverImage: nil)
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private static func findAttribute(in xml: String, attribute: String) -> String? {
        let pattern = "\(attribute)=\"([^\"]+)\""
        return regexFirstMatch(pattern: pattern, in: xml)
    }
    
    private static func findTagContent(in xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        return regexFirstMatch(pattern: pattern, in: xml)
    }
    
    private static func findSpineRefs(in opf: String) -> [String] {
        let pattern = "idref=\"([^\"]+)\""
        return regexAllMatches(pattern: pattern, in: opf)
    }
    
    private static func findManifestMap(in opf: String) -> [String: String] {
        var map: [String: String] = [:]
        let items = opf.components(separatedBy: "<item ")
        for item in items.dropFirst() {
            guard let id = findAttribute(in: item, attribute: "id"),
                  let href = findAttribute(in: item, attribute: "href") else { continue }
            map[id] = href
        }
        return map
    }
    
    private static func regexFirstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        if let match = results.first, match.numberOfRanges > 1 {
            return nsString.substring(with: match.range(at: 1))
        }
        return nil
    }
    
    private static func regexAllMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        return results.map { nsString.substring(with: $0.range(at: 1)) }
    }
    
    private static func stripHTML(_ html: String) -> String {
        var text = html
        
        // 1. Remove style/script blocks
        text = text.replacingOccurrences(of: "<script.*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<style.*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        
        // 2. Replace block tags with double newlines
        let blockTags = ["p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "li", "br"]
        for tag in blockTags {
            // Closing tags </p> -> \n\n
            text = text.replacingOccurrences(of: "</\(tag)>", with: "\n\n", options: .caseInsensitive)
            // <br> or <br/> -> \n
            if tag == "br" {
                text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            }
        }
        
        // 3. Remove all other tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        
        // 4. Decode entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        
        // 5. Collapse multiple spaces (but preserve newlines)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        
        // 6. Collapse multiple newlines > 2
        text = text.replacingOccurrences(of: "\n\\s*\n", with: "\n\n", options: .regularExpression)
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
