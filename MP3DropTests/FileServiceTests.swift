import Foundation
import Testing

@testable import MP3Drop

struct FileServiceTests {
    private let accepted: Set<String> = ["wav", "aiff", "aif", "aifc", "flac"]

    @Test func findsAudioFilesRecursivelyInNaturalOrder() throws {
        let root = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("stems")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        // Natural sort check: track10 must come after track2.
        for name in ["track10.wav", "track2.wav", "notes.txt", ".hidden.wav"] {
            FileManager.default.createFile(atPath: root.appendingPathComponent(name).path, contents: Data())
        }
        FileManager.default.createFile(atPath: nested.appendingPathComponent("vocal.aiff").path, contents: Data())

        let found = FileService.audioFiles(in: root, acceptedExtensions: accepted)
        let names = found.map { $0.lastPathComponent }
        #expect(Set(names) == ["track2.wav", "track10.wav", "vocal.aiff"])
        // track2 sorts before track10 (natural order).
        #expect(names.firstIndex(of: "track2.wav")! < names.firstIndex(of: "track10.wav")!)
        // Hidden files and non-audio files are excluded.
        #expect(!names.contains(".hidden.wav") && !names.contains("notes.txt"))
    }

    @Test func emptyFolderYieldsNoFiles() throws {
        let root = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(FileService.audioFiles(in: root, acceptedExtensions: accepted).isEmpty)
    }

    @Test func detectsDirectories() throws {
        let root = try TestAudioFactory.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.wav")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        #expect(FileService.isDirectory(root))
        #expect(!FileService.isDirectory(file))
    }
}
