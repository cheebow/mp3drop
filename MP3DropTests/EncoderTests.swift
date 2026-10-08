import AVFoundation
import Foundation
import Testing

@testable import MP3Drop

/// Spec §44 Tests 1-3 plus format/quality verification (§45-46, §58).
struct EncoderTests {
    private func encode(
        sampleRate: Double,
        bitDepth: Int,
        duration: TimeInterval = 2.0,
        preset: EncodingPreset
    ) async throws -> (source: URL, output: URL, directory: URL) {
        let directory = try TestAudioFactory.makeTemporaryDirectory()
        let source = try TestAudioFactory.makeWAV(
            in: directory,
            name: "test.wav",
            sampleRate: sampleRate,
            bitDepth: bitDepth,
            duration: duration
        )
        let output = directory.appendingPathComponent("test.mp3")
        try await LAMEEncoder().encode(
            sourceURL: source,
            destinationURL: output,
            preset: preset,
            progress: { _ in }
        )
        return (source, output, directory)
    }

    // Test 1: 48kHz/24bit/stereo WAV → V0 MP3.
    @Test func encode48k24bitStereoToV0() async throws {
        let result = try await encode(sampleRate: 48000, bitDepth: 24, preset: .v0)
        defer { try? FileManager.default.removeItem(at: result.directory) }

        let attributes = try FileManager.default.attributesOfItem(atPath: result.output.path)
        let size = (attributes[.size] as? Int64) ?? 0
        #expect(size > 1000)

        let decoded = try AVAudioFile(forReading: result.output)
        #expect(decoded.processingFormat.sampleRate == 48000)
        #expect(decoded.processingFormat.channelCount == 2)
    }

    // Test 2: 48kHz/24bit/stereo WAV → 320kbps CBR MP3.
    @Test func encode48k24bitStereoTo320() async throws {
        let duration = 2.0
        let result = try await encode(sampleRate: 48000, bitDepth: 24, duration: duration, preset: .cbr320)
        defer { try? FileManager.default.removeItem(at: result.directory) }

        let attributes = try FileManager.default.attributesOfItem(atPath: result.output.path)
        let size = Double((attributes[.size] as? Int64) ?? 0)
        // CBR 320 kbps = 40,000 bytes/s. Allow a few percent for headers.
        let expected = 40_000.0 * duration
        #expect(abs(size - expected) / expected < 0.05, "size \(size) not ~\(expected)")

        let decoded = try AVAudioFile(forReading: result.output)
        #expect(decoded.processingFormat.sampleRate == 48000)
    }

    // Test 3: 44.1kHz input stays 44.1kHz (no resampling).
    @Test func sampleRateIsPreserved() async throws {
        let result = try await encode(sampleRate: 44100, bitDepth: 16, preset: .v0)
        defer { try? FileManager.default.removeItem(at: result.directory) }

        let decoded = try AVAudioFile(forReading: result.output)
        #expect(decoded.processingFormat.sampleRate == 44100)
    }

    // §46: V0 is VBR — for a plain sine it must come out well below 320 CBR.
    @Test func v0IsSmallerThanCBR320ForSimpleSignal() async throws {
        let v0 = try await encode(sampleRate: 48000, bitDepth: 24, preset: .v0)
        defer { try? FileManager.default.removeItem(at: v0.directory) }
        let cbr = try await encode(sampleRate: 48000, bitDepth: 24, preset: .cbr320)
        defer { try? FileManager.default.removeItem(at: cbr.directory) }

        let v0Size = (try FileManager.default.attributesOfItem(atPath: v0.output.path)[.size] as? Int64) ?? 0
        let cbrSize = (try FileManager.default.attributesOfItem(atPath: cbr.output.path)[.size] as? Int64) ?? 0
        #expect(v0Size > 0 && cbrSize > 0)
        #expect(Double(v0Size) < Double(cbrSize) * 0.8)
    }

    // LAME marks VBR files with a "Xing" header and CBR files with "Info".
    @Test func v0IsVBRAndCBR320IsCBR() async throws {
        let v0 = try await encode(sampleRate: 44100, bitDepth: 16, preset: .v0)
        defer { try? FileManager.default.removeItem(at: v0.directory) }
        let cbr = try await encode(sampleRate: 44100, bitDepth: 16, preset: .cbr320)
        defer { try? FileManager.default.removeItem(at: cbr.directory) }

        #expect(try headerTag(of: v0.output) == "Xing")
        #expect(try headerTag(of: cbr.output) == "Info")
    }

    private func headerTag(of url: URL) throws -> String? {
        let head = try Data(contentsOf: url).prefix(4096)
        for tag in ["Xing", "Info"] where head.range(of: Data(tag.utf8)) != nil {
            return tag
        }
        return nil
    }

    // §58: no volume change — peak must survive the round trip (within
    // lossy-codec tolerance).
    @Test func volumeIsUnchanged() async throws {
        let result = try await encode(sampleRate: 48000, bitDepth: 24, preset: .cbr320)
        defer { try? FileManager.default.removeItem(at: result.directory) }

        let sourcePeak = try TestAudioFactory.peak(of: result.source)
        let outputPeak = try TestAudioFactory.peak(of: result.output)
        // ±0.5 dB tolerance for codec artifacts.
        let ratio = outputPeak / sourcePeak
        #expect(ratio > 0.94 && ratio < 1.06, "peak ratio \(ratio)")
    }

    // Unsupported rates (e.g. 96kHz) are rejected instead of resampled.
    @Test func unsupportedSampleRateIsRejected() async throws {
        let directory = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try TestAudioFactory.makeWAV(
            in: directory,
            name: "hires.wav",
            sampleRate: 96000,
            bitDepth: 24,
            duration: 0.5
        )
        let output = directory.appendingPathComponent("hires.mp3")
        await #expect(throws: ConversionError.unsupportedFormat) {
            try await LAMEEncoder().encode(
                sourceURL: source,
                destinationURL: output,
                preset: .v0,
                progress: { _ in }
            )
        }
    }
}
