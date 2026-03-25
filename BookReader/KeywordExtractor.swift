import Foundation
import NaturalLanguage

/// Extracts meaningful keywords from a body of text using lemmatization + TF scoring.
struct KeywordExtractor {
    
    // MARK: - Public API
    
    /// Returns the top `maxKeywords` keywords extracted from `text`.
    static func extract(from text: String, maxKeywords: Int = 15) -> [String] {
        let lemmas = lemmatize(text)
        let filtered = lemmas.filter { !stopwords.contains($0) && $0.count > 2 }
        let scored = termFrequency(filtered)
        let sorted = scored.sorted { $0.value > $1.value }
        return Array(sorted.prefix(maxKeywords).map { $0.key })
    }
    
    // MARK: - Lemmatization via Apple NaturalLanguage
    
    private static func lemmatize(_ text: String) -> [String] {
        var results: [String] = []
        
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        // Run only on a representative sample to keep import fast (~8k words)
        let sample = String(text.prefix(50_000))
        tagger.string = sample
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
        
        tagger.enumerateTags(in: sample.startIndex..<sample.endIndex, unit: .word, scheme: .lemma, options: options) { tag, range in
            // Only keep content words: nouns, verbs, adjectives
            let lexTag = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0
            let isContentWord = lexTag == .noun || lexTag == .verb || lexTag == .adjective
            
            guard isContentWord else { return true }
            
            let lemma: String
            if let tagValue = tag?.rawValue, !tagValue.isEmpty {
                lemma = tagValue.lowercased()
            } else {
                lemma = String(sample[range]).lowercased()
            }
            
            results.append(lemma)
            return true
        }
        
        return results
    }
    
    // MARK: - Term Frequency Scoring
    
    private static func termFrequency(_ tokens: [String]) -> [String: Double] {
        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }
        let total = Double(tokens.count)
        guard total > 0 else { return [:] }
        var tf: [String: Double] = [:]
        for (word, count) in counts {
            tf[word] = Double(count) / total
        }
        return tf
    }
    
    // MARK: - English Stopwords
    
    private static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "nor", "so", "yet",
        "in", "on", "at", "by", "for", "with", "about", "against",
        "between", "into", "through", "during", "before", "after",
        "above", "below", "up", "down", "out", "off", "over", "under",
        "again", "further", "then", "once", "here", "there", "when",
        "where", "why", "how", "all", "both", "each", "few", "more",
        "most", "other", "some", "such", "no", "not", "only", "own",
        "same", "than", "too", "very", "s", "t", "can", "will",
        "just", "don", "should", "now", "d", "ll", "m", "o", "re",
        "ve", "y", "ain", "aren", "couldn", "didn", "doesn", "hadn",
        "hasn", "haven", "isn", "ma", "mightn", "mustn", "needn",
        "shan", "shouldn", "wasn", "weren", "won", "wouldn",
        "i", "me", "my", "myself", "we", "our", "ours", "ourselves",
        "you", "your", "yours", "yourself", "he", "him", "his",
        "himself", "she", "her", "hers", "herself", "it", "its",
        "itself", "they", "them", "their", "theirs", "themselves",
        "what", "which", "who", "whom", "this", "that", "these",
        "those", "am", "is", "are", "was", "were", "be", "been",
        "being", "have", "has", "had", "having", "do", "does", "did",
        "doing", "would", "could", "ought", "may", "might", "shall",
        "must", "need", "dare", "used", "to", "of", "from", "as",
        "if", "while", "although", "because", "since", "unless",
        "until", "though", "also", "even", "get", "make", "know",
        "think", "see", "come", "go", "say", "tell", "said", "like",
        "well", "back", "little", "good", "great", "long", "much",
        "new", "old", "right", "big", "high", "different", "small",
        "large", "next", "early", "young", "important", "public",
        "private", "real", "best", "free", "sure", "every", "never",
        "always", "still", "something", "nothing", "everything",
        "anything", "more", "less", "however", "thus", "therefore",
        "hence", "accordingly", "indeed", "actually", "however",
        "one", "two", "three", "first", "second", "last", "upon",
        "around", "across", "toward", "towards", "within", "without",
        "already", "quite", "rather", "perhaps", "maybe", "soon",
        "look", "take", "went", "come", "came", "put", "give", "gave",
        "find", "found", "want", "ask", "seem", "feel", "try", "leave",
        "call", "keep", "let", "begin", "show", "hear", "play", "run",
        "move", "live", "believe", "hold", "bring", "happen", "write",
        "provide", "sit", "stand", "lose", "pay", "meet", "include",
        "continue", "set", "learn", "change", "lead", "understand",
        "watch", "follow", "stop", "create", "speak", "read", "spend",
        "grow", "open", "walk", "win", "offer", "remember", "love",
        "consider", "appear", "buy", "wait", "serve", "die", "send",
        "expect", "build", "stay", "fall", "cut", "reach", "kill",
        "remain", "suggest", "raise", "pass", "sell", "require",
        "report", "decide", "pull"
    ]
}
