import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ConversionViewModel {
    // MARK: Conversion state

    var jobs: [ConversionJob] = []
    var lastBatchResult: BatchResult?

    private let service = ConversionService()
    private let folderAccess = FolderAccessManager()

    var isConverting: Bool { service.isRunning }

    // MARK: Persisted settings (§31)

    @ObservationIgnored
    private let defaults = UserDefaults.standard

    var preset: EncodingPreset {
        didSet { defaults.set(preset.rawValue, forKey: "qualityPreset") }
    }

    var outputMode: OutputMode {
        didSet { defaults.set(outputMode.rawValue, forKey: "outputMode") }
    }

    var revealInFinder: Bool {
        didSet { defaults.set(revealInFinder, forKey: "revealInFinder") }
    }

    var playSound: Bool {
        didSet { defaults.set(playSound, forKey: "playSound") }
    }

    private(set) var outputFolderURL: URL?

    init() {
        preset = EncodingPreset(rawValue: defaults.string(forKey: "qualityPreset") ?? "") ?? .v0
        outputMode = OutputMode(rawValue: defaults.string(forKey: "outputMode") ?? "") ?? .sameFolder
        revealInFinder = defaults.object(forKey: "revealInFinder") as? Bool ?? true
        playSound = defaults.object(forKey: "playSound") as? Bool ?? false
        restoreOutputFolderBookmark()
    }

    // MARK: File intake

    static let acceptedExtensions: Set<String> = ["wav", "aiff", "aif", "aifc", "flac"]

    func addFiles(_ urls: [URL]) {
        // Each drop starts a fresh visible batch: this is a conversion list,
        // not a history log.
        jobs.removeAll(where: \.isFinished)
        lastBatchResult = nil
        for url in urls {
            if FileService.isDirectory(url) {
                // A dropped folder also grants write access to its whole
                // tree, so "Same Folder" output needs no permission dialog.
                let found = FileService.audioFiles(in: url, acceptedExtensions: Self.acceptedExtensions)
                if found.isEmpty {
                    let job = ConversionJob(sourceURL: url)
                    job.status = .failed(message: String(localized: "No audio files found in this folder."))
                    jobs.append(job)
                } else {
                    jobs.append(contentsOf: found.map { ConversionJob(sourceURL: $0) })
                }
            } else if Self.acceptedExtensions.contains(url.pathExtension.lowercased()) {
                jobs.append(ConversionJob(sourceURL: url))
            } else {
                let job = ConversionJob(sourceURL: url)
                job.status = .failed(message: ConversionError.unsupportedFormat.userMessage)
                jobs.append(job)
            }
        }
        startIfNeeded()
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.wav, .aiff, .folder]
        panel.allowsOtherFileTypes = true
        panel.message = String(localized: "Choose audio files, or folders to convert everything inside.")
        guard panel.runModal() == .OK else { return }
        addFiles(panel.urls)
    }

    // MARK: Conversion control

    private func startIfNeeded() {
        guard !isConverting, jobs.contains(where: { $0.status == .queued }) else { return }

        let outputFolder = outputMode == .customFolder ? outputFolderURL : nil
        service.start(
            preset: preset,
            outputFolder: outputFolder,
            nextJob: { [weak self] in
                self?.jobs.first { $0.status == .queued }
            },
            ensureAccess: { [weak self] folder in
                self?.folderAccess.ensureWriteAccess(to: folder)
            },
            resolveCollision: { [weak self] destination in
                self?.presentCollisionAlert(for: destination)
                    ?? CollisionResolution(choice: .cancel, applyToAll: true)
            },
            onFinish: { [weak self] result in
                self?.batchFinished(result)
            }
        )
    }

    func cancel() {
        service.cancel()
    }

    func clearFinished() {
        jobs.removeAll(where: \.isFinished)
        if jobs.isEmpty {
            lastBatchResult = nil
        }
    }

    private func batchFinished(_ result: BatchResult) {
        lastBatchResult = result
        guard result.convertedCount > 0 else { return }
        if revealInFinder {
            NSWorkspace.shared.activateFileViewerSelecting(result.outputURLs)
        }
        if playSound {
            NSSound(named: "Glass")?.play()
        }
    }

    // MARK: Collision dialog (§16)

    private func presentCollisionAlert(for destination: URL) -> CollisionResolution {
        let alert = NSAlert()
        alert.messageText = String(localized: "“\(destination.lastPathComponent)” already exists.")
        alert.informativeText = String(localized: "Replace the existing file, or keep both?")
        alert.addButton(withTitle: String(localized: "Replace"))
        alert.addButton(withTitle: String(localized: "Keep Both"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let remainingJobs = jobs.filter { !$0.isFinished }.count
        if remainingJobs > 1 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = String(localized: "Apply to All")
        }
        let response = alert.runModal()
        let applyToAll = alert.suppressionButton?.state == .on
        let choice: CollisionChoice = switch response {
        case .alertFirstButtonReturn: .replace
        case .alertSecondButtonReturn: .keepBoth
        default: .cancel
        }
        return CollisionResolution(choice: choice, applyToAll: applyToAll)
    }

    // MARK: Output folder

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else {
            if outputFolderURL == nil {
                outputMode = .sameFolder
            }
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        outputFolderURL = url
        outputMode = .customFolder
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(data, forKey: "outputFolderBookmark")
        }
    }

    private func restoreOutputFolderBookmark() {
        guard let data = defaults.data(forKey: "outputFolderBookmark") else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        outputFolderURL = url
    }

    func openOutputFolder() {
        let folder: URL? = switch outputMode {
        case .customFolder: outputFolderURL
        case .sameFolder: lastBatchResult?.outputURLs.first?.deletingLastPathComponent()
        }
        if let folder {
            NSWorkspace.shared.open(folder)
        }
    }

    // MARK: Progress summary (§22)

    var progressSummary: String? {
        guard isConverting else { return nil }
        let total = jobs.count
        let finished = jobs.filter(\.isFinished).count
        guard total > 1 else { return nil }
        return String(localized: "\(min(finished + 1, total)) / \(total) files")
    }
}
