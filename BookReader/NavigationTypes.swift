import Foundation

enum NavigationDestination: Hashable {
    case reader(ParsedDocument, BookMetadata)
    case metadata(BookMetadata)
    
    // Custom Equatable to bypass brutal payload equality checks during SwiftUI path resolution
    static func == (lhs: NavigationDestination, rhs: NavigationDestination) -> Bool {
        switch (lhs, rhs) {
        case let (.reader(_, lBook), .reader(_, rBook)):
            return lBook.id == rBook.id
        case let (.metadata(lBook), .metadata(rBook)):
            return lBook.id == rBook.id
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .reader(_, let book):
            hasher.combine(0)
            hasher.combine(book.id)
        case .metadata(let book):
            hasher.combine(1)
            hasher.combine(book.id)
        }
    }
}
