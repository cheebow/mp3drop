import Foundation

/// Metadata of a validated input audio file.
struct AudioFileInfo: Sendable, Equatable {
    let url: URL
    let sampleRate: Double
    let channelCount: Int
    let bitDepth: Int?
    let frameCount: Int64

    var duration: TimeInterval {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }
}

/// Sample rates that the MP3 format itself supports (MPEG-1/2/2.5).
/// Inputs at any other rate would force a resample, which this app never
/// does automatically, so they are rejected as unsupported.
enum MP3Format {
    static let supportedSampleRates: Set<Int> = [
        8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000,
    ]

    static func supports(sampleRate: Double) -> Bool {
        supportedSampleRates.contains(Int(sampleRate.rounded()))
    }
}
