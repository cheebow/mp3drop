import Foundation

/// User-facing conversion failures. Technical details go to the log,
/// never into these messages.
enum ConversionError: Error, Equatable {
    case unsupportedFormat
    case readError
    case writeError
    case diskFull
    case invalidAudio

    var userMessage: String {
        switch self {
        case .unsupportedFormat: String(localized: "This audio format is not supported.")
        case .readError: String(localized: "Could not read the source file.")
        case .writeError: String(localized: "Could not write the MP3 file.")
        case .diskFull: String(localized: "There is not enough free disk space.")
        case .invalidAudio: String(localized: "The audio file appears to be damaged.")
        }
    }

    /// Maps an arbitrary thrown error from file writing to a user-facing error.
    static func mappingWriteError(_ error: Error) -> ConversionError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == NSFileWriteOutOfSpaceError {
            return .diskFull
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(ENOSPC) {
            return .diskFull
        }
        return .writeError
    }
}
