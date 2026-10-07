import AVFoundation
import Foundation

/// Streams PCM from an audio file in fixed-size chunks as non-interleaved
/// Float32, preserving the source sample rate and channel count exactly.
/// No resampling, gain change, dithering, or any other processing happens
/// here — samples pass through untouched.
final class AudioDecoder {
    private let file: AVAudioFile
    let info: AudioFileInfo

    init(url: URL) throws {
        do {
            file = try AVAudioFile(
                forReading: url,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            Log.audioDecoder.error("Failed to open \(url.lastPathComponent): \(error)")
            throw Self.mapOpenError(error)
        }

        let format = file.processingFormat
        let asbd = file.fileFormat.streamDescription.pointee
        info = AudioFileInfo(
            url: url,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            bitDepth: asbd.mBitsPerChannel > 0 ? Int(asbd.mBitsPerChannel) : nil,
            frameCount: file.length
        )

        // Mono and stereo only (v1), and only sample rates MP3 can represent:
        // anything else would force a resample, which this app never does.
        guard (1...2).contains(info.channelCount),
              MP3Format.supports(sampleRate: info.sampleRate) else {
            throw ConversionError.unsupportedFormat
        }
        guard info.frameCount > 0 else {
            throw ConversionError.invalidAudio
        }
    }

    /// Reads the next chunk. Returns nil at end of file.
    func readChunk(frameCapacity: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        // AVAudioFile.read throws a generic error when called at EOF rather
        // than returning an empty buffer, so stop before that happens.
        guard file.framePosition < file.length else { return nil }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCapacity
        ) else {
            throw ConversionError.readError
        }
        do {
            try file.read(into: buffer, frameCount: frameCapacity)
        } catch {
            Log.audioDecoder.error("Read failed in \(self.info.url.lastPathComponent): \(error)")
            throw ConversionError.invalidAudio
        }
        return buffer.frameLength > 0 ? buffer : nil
    }

    private static func mapOpenError(_ error: Error) -> ConversionError {
        let code = (error as NSError).code
        switch code {
        case Int(kAudioFileUnsupportedFileTypeError),
             Int(kAudioFileUnsupportedDataFormatError),
             Int(kAudioFileUnspecifiedError):
            return .unsupportedFormat
        case Int(kAudioFileInvalidFileError),
             Int(kAudioFileInvalidChunkError),
             Int(kAudioFileDoesNotAllow64BitDataSizeError):
            return .invalidAudio
        default:
            return .readError
        }
    }
}
