import Foundation

enum NavigationDestination: Hashable {
    case reader(ParsedDocument, BookMetadata)
}
