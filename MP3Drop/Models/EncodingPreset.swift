import Foundation

/// MP3 quality presets exposed to the user. Internally these map to the
/// official LAME presets (V0 and "insane" 320 CBR); no custom tuning.
enum EncodingPreset: String, CaseIterable, Identifiable, Sendable {
    case v0
    case cbr320

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .v0: String(localized: "High Quality (V0)")
        case .cbr320: String(localized: "320 kbps")
        }
    }

    var detail: String {
        switch self {
        case .v0:
            String(localized: "Best balance of quality and file size. Uses LAME V0 variable bitrate.")
        case .cbr320:
            String(localized: "Maximum constant bitrate. Recommended when 320 kbps is required.")
        }
    }
}
