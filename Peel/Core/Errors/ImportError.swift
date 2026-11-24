import Foundation

enum ImportError: LocalizedError {
    case unreadable, wrongType(String), empty, invalidBackup
    var errorDescription: String? {
        switch self {
        case .unreadable: String(localized: "Unable to read selected file.")
        case .wrongType(let file): String(localized: "Wrong file: \(file). Select the matching Instagram export instead.")
        case .empty: String(localized: "No usernames found.")
        case .invalidBackup: String(localized: "Not a Peel progress file.")
        }
    }
}
