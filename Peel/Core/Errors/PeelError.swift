import Foundation

enum PeelError: Error, LocalizedError, Equatable, Sendable {
    case unreadableFile, invalidBackup, corruptSavedData, unsupportedFormat
    case invalidJSON, tooLarge, persistence, exportFailed, offline, timeout
    case http(Int), rateLimited(Date), loginRequired, browserTerminated, unavailable
    case invalidArchive, wrongList
    case invalidURL, exportCleanupFailed

    var text: LocalizedStringResource {
        switch self {
        case .unreadableFile: "The file cannot be read. Choose it again in Files."
        case .invalidBackup: "This backup contains invalid progress. Your existing data has been kept."
        case .corruptSavedData: "Saved progress could not be read. The original data has been kept. Retry or restore a valid backup."
        case .unsupportedFormat: "This Instagram format is not supported. Request a new Followers and following export in JSON or HTML."
        case .invalidJSON: "The JSON file is damaged or incomplete. Download the export again."
        case .tooLarge: "This file exceeds the safe import size. Choose a smaller export."
        case .persistence: "Progress could not be saved. Your last saved state has been kept. Retry before continuing."
        case .exportFailed: "The backup could not be written. Check available storage and try again."
        case .exportCleanupFailed: "A temporary backup could not be removed from Peel’s temporary storage. Retry cleanup. Your saved progress has not been changed."
        case .offline: "You appear to be offline. Check your connection and retry."
        case .timeout: "The request timed out. Check your connection and retry."
        case .http(let status): "Instagram returned an error (\(status)). Try again later."
        case .rateLimited: "Instagram is limiting requests. Wait before retrying."
        case .loginRequired: "Instagram opened a sign-in or verification page. Complete it on Instagram, then retry the profile."
        case .browserTerminated: "The web page stopped unexpectedly. Retry to reload it."
        case .unavailable: "The page or image is unavailable. Try again later."
        case .invalidArchive: "This ZIP is damaged, incomplete, encrypted, or uses unsupported compression. Download a new JSON or HTML export."
        case .wrongList: "This file contains the other list. Choose the matching Following or Followers file."
        case .invalidURL: "This Instagram address could not be opened."
        }
    }

    var errorDescription: String? { String(localized: text) }

    var retryAfter: Date? {
        if case .rateLimited(let date) = self { return date }
        return nil
    }

    static func map(_ error: Error) -> PeelError {
        if let error = error as? PeelError { return error }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost: return .offline
            case .timedOut: return .timeout
            default: return .unavailable
            }
        }
        if let error = error as? InstagramZIPError {
            switch error {
            case .tooLarge: return .tooLarge
            case .missingLists: return .unsupportedFormat
            default: return .invalidArchive
            }
        }
        if let error = error as? ImportError {
            switch error {
            case .wrongType: return .wrongList
            case .unreadable: return .unreadableFile
            case .empty: return .unsupportedFormat
            case .invalidBackup: return .invalidBackup
            }
        }
        if error is DecodingError { return .invalidBackup }
        if error is CocoaError { return .unreadableFile }
        return .unavailable
    }
}
