import Foundation

/// Abstraction over the MP3 encoder so the implementation stays swappable.
protocol MP3Encoding: Sendable {
    /// Encodes `sourceURL` to an MP3 at `destinationURL` (which must not
    /// exist yet; the caller manages temporary files and renames).
    /// `progress` is called with values in 0...1 from a background context.
    func encode(
        sourceURL: URL,
        destinationURL: URL,
        preset: EncodingPreset,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}
