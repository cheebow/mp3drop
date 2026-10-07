import Foundation
import Observation

/// One source file queued for conversion, observed by the UI.
@MainActor
@Observable
final class ConversionJob: Identifiable {
    enum Status: Equatable {
        case queued
        case encoding(progress: Double)
        case done(outputURL: URL)
        case failed(message: String)
        case cancelled
        case skipped
    }

    let id = UUID()
    let sourceURL: URL
    var status: Status = .queued

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
    }

    var fileName: String { sourceURL.lastPathComponent }

    var isFinished: Bool {
        switch status {
        case .queued, .encoding: false
        case .done, .failed, .cancelled, .skipped: true
        }
    }
}
