import Testing

@testable import MP3Drop

struct EncodingPresetTests {
    @Test func presetIdentity() {
        #expect(EncodingPreset.allCases.count == 2)
        #expect(EncodingPreset.v0.id == "v0")
        #expect(EncodingPreset.cbr320.id == "cbr320")
        // Display names are localized; just make sure they resolve.
        for preset in EncodingPreset.allCases {
            #expect(!preset.displayName.isEmpty)
            #expect(!preset.detail.isEmpty)
        }
    }
}
