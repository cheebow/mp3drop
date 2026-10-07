import AVFoundation
import CLAME
import Foundation

/// MP3 encoder backed by libmp3lame.
///
/// Uses the official LAME presets (V0 / insane) with no custom tuning, feeds
/// LAME the decoder's Float32 samples directly (no 16-bit intermediate, no
/// dithering), and keeps the input sample rate. Audio is streamed in chunks
/// so arbitrarily large files never load into memory at once.
struct LAMEEncoder: MP3Encoding {
    private static let chunkFrames: AVAudioFrameCount = 65536

    func encode(
        sourceURL: URL,
        destinationURL: URL,
        preset: EncodingPreset,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let decoder = try AudioDecoder(url: sourceURL)
        let info = decoder.info

        guard let lame = lame_init() else {
            throw ConversionError.writeError
        }
        defer { lame_close(lame) }

        lame_set_num_channels(lame, Int32(info.channelCount))
        lame_set_in_samplerate(lame, Int32(info.sampleRate))
        // Force the output rate to match the input: LAME must never resample.
        lame_set_out_samplerate(lame, Int32(info.sampleRate))
        switch preset {
        case .v0:
            lame_set_preset(lame, Int32(V0.rawValue))
        case .cbr320:
            lame_set_preset(lame, Int32(INSANE.rawValue))
        }

        guard lame_init_params(lame) >= 0 else {
            Log.lameEncoder.error("lame_init_params failed for \(sourceURL.lastPathComponent)")
            throw ConversionError.unsupportedFormat
        }

        guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
            throw ConversionError.writeError
        }
        let output: FileHandle
        do {
            output = try FileHandle(forWritingTo: destinationURL)
        } catch {
            throw ConversionError.mappingWriteError(error)
        }
        defer { try? output.close() }

        var mp3Buffer = [UInt8](repeating: 0, count: Int(Self.chunkFrames) * 5 / 4 + 7200)
        var framesDone: Int64 = 0

        while let buffer = try decoder.readChunk(frameCapacity: Self.chunkFrames) {
            try Task.checkCancellation()

            guard let channels = buffer.floatChannelData else {
                throw ConversionError.readError
            }
            let frames = Int32(buffer.frameLength)
            let left = channels[0]
            let right = info.channelCount > 1 ? channels[1] : channels[0]

            let byteCount = mp3Buffer.withUnsafeMutableBufferPointer { out in
                lame_encode_buffer_ieee_float(
                    lame, left, right, frames, out.baseAddress, Int32(out.count)
                )
            }
            guard byteCount >= 0 else {
                Log.lameEncoder.error("lame_encode_buffer returned \(byteCount)")
                throw ConversionError.writeError
            }
            try write(mp3Buffer, count: Int(byteCount), to: output)

            framesDone += Int64(frames)
            if info.frameCount > 0 {
                progress(min(1.0, Double(framesDone) / Double(info.frameCount)))
            }
        }

        try Task.checkCancellation()

        let flushedCount = mp3Buffer.withUnsafeMutableBufferPointer { out in
            lame_encode_flush(lame, out.baseAddress, Int32(out.count))
        }
        guard flushedCount >= 0 else {
            throw ConversionError.writeError
        }
        try write(mp3Buffer, count: Int(flushedCount), to: output)

        // Rewrite the first frame with the finished Xing/LAME tag so players
        // report correct duration and bitrate (essential for VBR).
        var tagBuffer = [UInt8](repeating: 0, count: 16384)
        let tagSize = tagBuffer.withUnsafeMutableBufferPointer { out in
            lame_get_lametag_frame(lame, out.baseAddress, out.count)
        }
        if tagSize > 0, tagSize <= tagBuffer.count {
            do {
                try output.seek(toOffset: 0)
            } catch {
                throw ConversionError.mappingWriteError(error)
            }
            try write(tagBuffer, count: Int(tagSize), to: output)
        }

        progress(1.0)
    }

    private func write(_ buffer: [UInt8], count: Int, to handle: FileHandle) throws {
        guard count > 0 else { return }
        do {
            try handle.write(contentsOf: Data(bytes: buffer, count: count))
        } catch {
            throw ConversionError.mappingWriteError(error)
        }
    }
}
