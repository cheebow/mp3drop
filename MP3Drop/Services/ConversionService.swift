import Foundation

enum CollisionChoice: Sendable {
    case replace
    case keepBoth
    case cancel
}

struct CollisionResolution: Sendable {
    let choice: CollisionChoice
    let applyToAll: Bool
}

struct BatchResult: Sendable {
    let convertedCount: Int
    let outputURLs: [URL]
}

/// Runs conversion jobs one at a time (sequential by design for stability),
/// handling name collisions, temporary files, cancellation, and cleanup.
@MainActor
final class ConversionService {
    private let encoder: any MP3Encoding
    private var batchTask: Task<Void, Never>?
    private(set) var isRunning = false

    init(encoder: any MP3Encoding = LAMEEncoder()) {
        self.encoder = encoder
    }

    /// Starts converting every queued job. `nextJob` lets the caller feed
    /// jobs added while the batch is running; `resolveCollision` presents
    /// the Replace / Keep Both / Cancel dialog.
    func start(
        preset: EncodingPreset,
        outputFolder: URL?,
        nextJob: @escaping @MainActor () -> ConversionJob?,
        ensureAccess: @escaping @MainActor (URL) -> URL?,
        resolveCollision: @escaping @MainActor (URL) -> CollisionResolution,
        onFinish: @escaping @MainActor (BatchResult) -> Void
    ) {
        guard !isRunning else { return }
        isRunning = true

        batchTask = Task { @MainActor [encoder] in
            var convertedURLs: [URL] = []
            var stickyChoice: CollisionChoice?
            var cancelledBatch = false

            while let job = nextJob() {
                if cancelledBatch || Task.isCancelled {
                    job.status = .cancelled
                    continue
                }

                let sourceURL = job.sourceURL
                let directory = outputFolder ?? sourceURL.deletingLastPathComponent()

                guard ensureAccess(directory) != nil else {
                    job.status = .failed(message: ConversionError.writeError.userMessage)
                    continue
                }

                var destination = FileService.outputURL(for: sourceURL, in: outputFolder)
                if FileManager.default.fileExists(atPath: destination.path) {
                    let choice: CollisionChoice
                    if let sticky = stickyChoice {
                        choice = sticky
                    } else {
                        let resolution = resolveCollision(destination)
                        if resolution.applyToAll {
                            stickyChoice = resolution.choice
                        }
                        choice = resolution.choice
                    }
                    switch choice {
                    case .replace:
                        break
                    case .keepBoth:
                        destination = FileService.uniqueURL(for: destination)
                    case .cancel:
                        job.status = .skipped
                        if stickyChoice == .cancel {
                            cancelledBatch = true
                        }
                        continue
                    }
                }

                let temporary = FileService.temporaryURL(for: destination)
                job.status = .encoding(progress: 0)
                do {
                    try await encoder.encode(
                        sourceURL: sourceURL,
                        destinationURL: temporary,
                        preset: preset
                    ) { fraction in
                        Task { @MainActor in
                            if case .encoding = job.status {
                                job.status = .encoding(progress: fraction)
                            }
                        }
                    }
                    FileService.removeIfExists(destination)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    job.status = .done(outputURL: destination)
                    convertedURLs.append(destination)
                } catch is CancellationError {
                    FileService.removeIfExists(temporary)
                    job.status = .cancelled
                    cancelledBatch = true
                } catch let error as ConversionError {
                    FileService.removeIfExists(temporary)
                    Log.conversionService.error("\(sourceURL.lastPathComponent): \(String(describing: error))")
                    job.status = .failed(message: error.userMessage)
                } catch {
                    FileService.removeIfExists(temporary)
                    Log.conversionService.error("\(sourceURL.lastPathComponent): \(error)")
                    job.status = .failed(message: ConversionError.writeError.userMessage)
                }
            }

            isRunning = false
            onFinish(BatchResult(convertedCount: convertedURLs.count, outputURLs: convertedURLs))
        }
    }

    func cancel() {
        batchTask?.cancel()
    }
}
