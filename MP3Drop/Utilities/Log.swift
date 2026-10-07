import OSLog

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "MP3Drop"

    static let audioDecoder = Logger(subsystem: subsystem, category: "AudioDecoder")
    static let lameEncoder = Logger(subsystem: subsystem, category: "LAMEEncoder")
    static let conversionService = Logger(subsystem: subsystem, category: "ConversionService")
    static let fileService = Logger(subsystem: subsystem, category: "FileService")
}
