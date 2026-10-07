import AVFoundation
import Foundation

/// Generates test WAV files programmatically so no binary fixtures need to
/// be committed.
enum TestAudioFactory {
    /// Writes a stereo (or mono) sine-wave WAV and returns its URL.
    static func makeWAV(
        in directory: URL,
        name: String,
        sampleRate: Double,
        bitDepth: Int,
        channels: Int = 2,
        duration: TimeInterval,
        amplitude: Float = 0.5
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channels),
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frameCount

        let frequency = 440.0
        for channel in 0..<channels {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(frameCount) {
                let phase = 2.0 * Double.pi * frequency * Double(frame) / sampleRate
                samples[frame] = amplitude * Float(sin(phase))
            }
        }
        try file.write(from: buffer)
        return url
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MP3DropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Peak absolute sample value of an audio file (decoded as Float32).
    static func peak(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw CocoaError(.fileReadUnknown)
        }
        try file.read(into: buffer)
        var peak: Float = 0
        for channel in 0..<Int(file.processingFormat.channelCount) {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(samples[frame]))
            }
        }
        return peak
    }
}
