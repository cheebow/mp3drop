import Foundation
import Testing

@testable import MP3Drop

/// Spec §44 Tests 4-6: batch conversion, collision handling, cancellation.
@MainActor
struct ConversionServiceTests {
    private func runBatch(
        jobs: [ConversionJob],
        outputFolder: URL? = nil,
        collision: @escaping @MainActor (URL) -> CollisionResolution = { _ in
            CollisionResolution(choice: .keepBoth, applyToAll: false)
        },
        afterStart: (@MainActor (ConversionService) -> Void)? = nil
    ) async -> BatchResult {
        let service = ConversionService()
        var remaining = jobs
        return await withCheckedContinuation { continuation in
            service.start(
                preset: .v0,
                outputFolder: outputFolder,
                nextJob: {
                    remaining.first { $0.status == .queued }.map { job in
                        remaining.removeAll { $0 === job }
                        return job
                    } ?? nil
                },
                ensureAccess: { $0 },
                resolveCollision: collision,
                onFinish: { result in
                    continuation.resume(returning: result)
                }
            )
            afterStart?(service)
        }
    }

    // Test 4: multiple WAVs are all converted.
    @Test func convertsMultipleFiles() async throws {
        let directory = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        var jobs: [ConversionJob] = []
        for index in 1...3 {
            let wav = try TestAudioFactory.makeWAV(
                in: directory,
                name: "song0\(index).wav",
                sampleRate: 48000,
                bitDepth: 24,
                duration: 0.5
            )
            jobs.append(ConversionJob(sourceURL: wav))
        }

        let result = await runBatch(jobs: jobs)
        #expect(result.convertedCount == 3)
        for index in 1...3 {
            let mp3 = directory.appendingPathComponent("song0\(index).mp3")
            #expect(FileManager.default.fileExists(atPath: mp3.path))
        }
        // Sources are untouched (§58).
        for index in 1...3 {
            let wav = directory.appendingPathComponent("song0\(index).wav")
            #expect(FileManager.default.fileExists(atPath: wav.path))
        }
    }

    // Test 5: existing MP3 is never silently overwritten (Keep Both).
    @Test func keepBothDoesNotOverwrite() async throws {
        let directory = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let wav = try TestAudioFactory.makeWAV(
            in: directory,
            name: "song.wav",
            sampleRate: 44100,
            bitDepth: 16,
            duration: 0.5
        )
        let existing = directory.appendingPathComponent("song.mp3")
        let sentinel = Data("not really an mp3".utf8)
        try sentinel.write(to: existing)

        let result = await runBatch(jobs: [ConversionJob(sourceURL: wav)])
        #expect(result.convertedCount == 1)

        // The pre-existing file is byte-identical, and "song 2.mp3" was created.
        #expect(try Data(contentsOf: existing) == sentinel)
        let kept = directory.appendingPathComponent("song 2.mp3")
        #expect(FileManager.default.fileExists(atPath: kept.path))
    }

    // Test 5b: Cancel in the collision dialog skips the file.
    @Test func collisionCancelSkipsFile() async throws {
        let directory = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let wav = try TestAudioFactory.makeWAV(
            in: directory,
            name: "song.wav",
            sampleRate: 44100,
            bitDepth: 16,
            duration: 0.5
        )
        let existing = directory.appendingPathComponent("song.mp3")
        let sentinel = Data("keep me".utf8)
        try sentinel.write(to: existing)

        let job = ConversionJob(sourceURL: wav)
        let result = await runBatch(jobs: [job]) { _ in
            CollisionResolution(choice: .cancel, applyToAll: false)
        }
        #expect(result.convertedCount == 0)
        #expect(job.status == .skipped)
        #expect(try Data(contentsOf: existing) == sentinel)
    }

    // Test 6: cancelling mid-encode leaves no unfinished files behind.
    @Test func cancelRemovesUnfinishedFiles() async throws {
        let directory = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Long enough that cancellation lands mid-encode.
        let wav = try TestAudioFactory.makeWAV(
            in: directory,
            name: "long.wav",
            sampleRate: 48000,
            bitDepth: 24,
            duration: 30
        )
        let job = ConversionJob(sourceURL: wav)
        let result = await runBatch(jobs: [job]) { _ in
            CollisionResolution(choice: .replace, applyToAll: false)
        } afterStart: { service in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                service.cancel()
            }
        }

        #expect(result.convertedCount == 0)
        #expect(job.status == .cancelled)

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!contents.contains { $0.hasSuffix(".mp3") || $0.hasSuffix(".part") },
                "leftover files: \(contents)")
    }
}
