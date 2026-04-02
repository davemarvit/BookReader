import Foundation
import PDFKit
import UniformTypeIdentifiers
import ZIPFoundation

struct ParsedDocument: Hashable {
    let title: String
    let author: String?
    let text: String
    let paragraphCount: Int
    let coverImage: Data?
    var initialParagraphIndex: Int = 0
    var chapters: [Chapter] = []
    
    var summary: String? = nil
    var tags: [String]? = nil
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(author)
        hasher.combine(paragraphCount)
        // Skip large text/image for performance hashing, rely on title + count usually being unique enough for momentary state
        // or combine prefix of text
        hasher.combine(text.prefix(100))
    }
    
    static func == (lhs: ParsedDocument, rhs: ParsedDocument) -> Bool {
        return lhs.title == rhs.title &&
               lhs.author == rhs.author &&
               lhs.paragraphCount == rhs.paragraphCount &&
               lhs.text == rhs.text // Equality must still check full text if hash collides
    }
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
    
    private static func smartClean(_ text: String) -> [String] {
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
        
        return cleanedBlocks
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
        let rawTitle = pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
        let cleanTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = cleanTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : cleanTitle
        
        // Generate Thumbnail
        var coverData: Data? = nil
        if let firstPage = pdf.page(at: 0) {
            let thumbnail = firstPage.thumbnail(of: CGSize(width: 300, height: 450), for: .mediaBox)
            coverData = thumbnail.jpegData(compressionQuality: 0.8)
        }
        
        let cleanedBlocks = smartClean(fullText)
        let cleanedText = cleanedBlocks.joined(separator: "\n\n")
        let author = pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
        let autoTags = KeywordExtractor.extract(from: cleanedText)
        return ParsedDocument(title: title, author: author, text: cleanedText, paragraphCount: cleanedBlocks.count, coverImage: coverData, initialParagraphIndex: 0, chapters: [], summary: nil, tags: autoTags.isEmpty ? nil : autoTags)
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
            var allCleanedBlocks: [String] = []
            var initialParagraphIndex = 0
            var chapters: [Chapter] = []
            var foundStart = false
            
            for idref in spineRefs {
                if let href = manifest[idref] {
                    let htmlURL = opfDir.appendingPathComponent(href)
                    if let htmlContent = try? String(contentsOf: htmlURL) {
                        let stripped = stripHTML(htmlContent)
                        let blocks = smartClean(stripped)
                        if blocks.isEmpty { continue }
                        
                        // Intelligent Front Matter Skipping (filename + content heuristics)
                        if !foundStart {
                            let lower = href.lowercased()
                            
                            // Track 1: filename contains known front-matter keywords
                            let nameIsFrontMatter = lower.contains("title") || lower.contains("cover") ||
                                lower.contains("copy") || lower.contains("toc") || lower.contains("nav") ||
                                lower.contains("dedic") || lower.contains("ack") || lower.contains("halftitle") ||
                                lower.contains("half-title") || lower.contains("epigraph") || lower.contains("prolog")
                            
                            // Track 2: content heuristic — very short spine items (≤3 paragraphs,
                            // each under 200 chars) are almost certainly cover/title/copyright pages.
                            let isShortPage = blocks.count <= 3 && blocks.allSatisfy { $0.count < 200 }
                            
                            if !nameIsFrontMatter && !isShortPage {
                                initialParagraphIndex = allCleanedBlocks.count
                                foundStart = true
                            }
                        }
                        
                        // Only record as a chapter if it's real content (not front matter).
                        // Prefer h2/h3 semantic headings over blocks[0] — h1 is usually the
                        // repeating book title, not the chapter name.
                        if foundStart {
                            let rawHeading = extractChapterHeading(from: htmlContent)
                            let chapterTitle: String
                            if let heading = rawHeading, heading.count > 1 {
                                chapterTitle = String(heading.prefix(80))
                            } else {
                                chapterTitle = String(blocks[0].prefix(80).trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if chapterTitle.count > 1 {
                                let chapter = Chapter(title: chapterTitle, paragraphIndex: allCleanedBlocks.count)
                                chapters.append(chapter)
                            }
                        }
                        
                        allCleanedBlocks.append(contentsOf: blocks)
                    }
                }
            }
            
            // Deduplicate TOC: if any title appears in the majority of entries it's a
            // repeating running header (book title), not a real chapter name — remove it.
            let titleCounts = Dictionary(chapters.map { ($0.title, 1) }, uniquingKeysWith: +)
            let maxRepeats = max(2, chapters.count / 4)   // allow up to 25% repeats
            let deduped = chapters.filter { titleCounts[$0.title, default: 0] <= maxRepeats }
            
            let rawTitle = findTagContent(in: opfContent, tag: "dc:title")
            let cleanTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = cleanTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : cleanTitle
            let author = findTagContent(in: opfContent, tag: "dc:creator")
            // Extract the new metadata
            let rawSummary = findTagContent(in: opfContent, tag: "dc:description")
            let summary = rawSummary.map { cleanSummary($0) }
            let tags = findMultipleTagContent(in: opfContent, tag: "dc:subject")
            
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
            
            let finalJoinedText = allCleanedBlocks.joined(separator: "\n\n")
            // Use EPUB-embedded subject tags if present, otherwise extract via TF
            let finalTags: [String]?
            if !tags.isEmpty {
                finalTags = tags
            } else {
                let autoTags = KeywordExtractor.extract(from: finalJoinedText)
                finalTags = autoTags.isEmpty ? nil : autoTags
            }
            return ParsedDocument(title: title, author: author, text: finalJoinedText, paragraphCount: allCleanedBlocks.count, coverImage: coverData, initialParagraphIndex: initialParagraphIndex, chapters: deduped, summary: summary, tags: finalTags)
            
        } catch {
            print("EPUB Error: \(error)")
            try? fileManager.removeItem(at: tempDir)
            return nil
        }
    }
    
    private static func parseText(url: URL) -> ParsedDocument? {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let cleanedBlocks = smartClean(text)
            let cleanedText = cleanedBlocks.joined(separator: "\n\n")
            let autoTags = KeywordExtractor.extract(from: cleanedText)
            return ParsedDocument(title: url.deletingPathExtension().lastPathComponent, author: nil, text: cleanedText, paragraphCount: cleanedBlocks.count, coverImage: nil, initialParagraphIndex: 0, chapters: [], summary: nil, tags: autoTags.isEmpty ? nil : autoTags)
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    /// Cleans a raw dc:description field:
    /// - Decodes double-encoded HTML entities (&lt;p&gt; → <p>)
    /// - Strips all remaining HTML tags
    /// - Collapses whitespace
    /// - Truncates to 200 words
    private static func cleanSummary(_ raw: String) -> String {
        var text = raw
        
        // Step 1: Decode double-encoded entities so &lt;p&gt; becomes <p>
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&#160;", with: " ")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        
        // Step 2: Strip all HTML tags (now that encoded ones are decoded)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        
        // Step 3: Collapse multiple spaces/newlines into single spaces
        text = text.replacingOccurrences(of: "[\\s]+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Step 4: Truncate to 200 words
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        if words.count > 200 {
            text = words.prefix(200).joined(separator: " ") + "…"
        }
        
        return text
    }
    
    /// Extracts the most semantically appropriate chapter heading from raw HTML.
    /// Prefers h2/h3 over h1, since h1 is usually the running book title.
    private static func extractChapterHeading(from html: String) -> String? {
        let tags = [("h2", 0), ("h3", 0), ("h1", 0)]
        for (tag, _) in tags {
            let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
            if let raw = regexFirstMatchGroup(pattern: pattern, in: html) {
                // Strip any nested HTML tags inside the heading
                let clean = raw
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if clean.count > 1 { return clean }
            }
        }
        return nil
    }
    
    private static func findAttribute(in xml: String, attribute: String) -> String? {
        let pattern = "\(attribute)=\"([^\"]+)\""
        return regexFirstMatch(pattern: pattern, in: xml)
    }
    
    private static func findTagContent(in xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        return regexFirstMatchGroup(pattern: pattern, in: xml)
    }
    
    private static func findMultipleTagContent(in xml: String, tag: String) -> [String] {
        let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        return regexAllMatchesGroup(pattern: pattern, in: xml)
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
    
    private static func regexFirstMatchGroup(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        if let match = results.first, match.numberOfRanges > 1 {
            return nsString.substring(with: match.range(at: 1))
        }
        return nil
    }
    
    private static func regexAllMatchesGroup(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        return results.compactMap {
            if $0.numberOfRanges > 1 {
                return nsString.substring(with: $0.range(at: 1))
            }
            return nil
        }
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
