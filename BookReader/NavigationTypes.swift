import Foundation

enum NavigationDestination: Hashable {
    case library
    case reader(ParsedDocument, BookMetadata)
}
