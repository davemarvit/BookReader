import Foundation

enum NavigationDestination: Hashable {
    case reader(ParsedDocument, BookMetadata)
    case metadata(BookMetadata)
}
