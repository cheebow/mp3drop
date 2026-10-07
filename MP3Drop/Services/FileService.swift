import AppKit
import Foundation

enum OutputMode: String, CaseIterable, Sendable {
    case sameFolder
    case customFolder
}

enum FileService {
    /// Destination MP3 URL for a source file: same base name, .mp3 extension.
    static func outputURL(for source: URL, in folder: URL?) -> URL {
        let directory = folder ?? source.deletingLastPathComponent()
        let baseName = source.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent(baseName).appendingPathExtension("mp3")
    }

    /// First non-existing variant: "song.mp3", "song 2.mp3", "song 3.mp3", ...
    static func uniqueURL(for url: URL) -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return url }
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 2
        while true {
            let candidate = directory
                .appendingPathComponent("\(baseName) \(counter)")
                .appendingPathExtension(ext)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            counter += 1
        }
    }

    /// Hidden in-progress file next to the destination (same volume, so the
    /// final rename is atomic). Deleted on cancel or failure so no broken
    /// MP3 is ever left behind.
    static func temporaryURL(for destination: URL) -> URL {
        let directory = destination.deletingLastPathComponent()
        let name = ".\(destination.lastPathComponent).\(UUID().uuidString.prefix(8)).part"
        return directory.appendingPathComponent(name)
    }

    static func removeIfExists(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// All audio files inside a folder, recursively, in natural name order.
    /// Hidden files and package contents are skipped.
    static func audioFiles(in folder: URL, acceptedExtensions: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  acceptedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }
            files.append(url)
        }
        return files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
    }
}

/// Manages sandbox write access to output folders.
///
/// A file dragged from Finder grants access to that file only, not to its
/// folder, so writing "song.mp3" next to "song.wav" needs a one-time grant
/// from the user. The grant dialog defaults to the home folder, so a single
/// grant covers every folder inside it. Grants are persisted as
/// security-scoped bookmarks and restored (and kept active) on every launch,
/// so the dialog never reappears for a covered folder.
@MainActor
final class FolderAccessManager {
    private static let bookmarksKey = "folderBookmarks"
    private var grantsLoaded = false

    /// Returns a writable URL for `folder`, prompting the user once if the
    /// sandbox denies access. Returns nil if the user declines.
    func ensureWriteAccess(to folder: URL) -> URL? {
        restoreGrantsIfNeeded()
        if FileManager.default.isWritableFile(atPath: folder.path) {
            return folder
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = Self.realHomeDirectory
        panel.message = String(localized: "MP3 Drop needs your permission to save MP3 files. Grant access to your home folder once to cover all folders inside it, or pick a specific folder.")
        panel.prompt = String(localized: "Grant Access")
        guard panel.runModal() == .OK, let granted = panel.url else {
            return nil
        }
        saveBookmark(for: granted)
        if granted.startAccessingSecurityScopedResource() == false {
            Log.fileService.error("startAccessing failed for \(granted.path)")
        }

        // The granted folder may not cover the one we actually need.
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            return nil
        }
        return folder
    }

    /// Resolves every stored bookmark and starts its security scope for the
    /// lifetime of the app, so plain file APIs work anywhere under a grant.
    private func restoreGrantsIfNeeded() {
        guard !grantsLoaded else { return }
        grantsLoaded = true

        var bookmarks = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
        var changed = false
        for (path, data) in bookmarks {
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                Log.fileService.error("Dropping unresolvable bookmark for \(path)")
                bookmarks[path] = nil
                changed = true
                continue
            }
            if resolved.startAccessingSecurityScopedResource() == false {
                Log.fileService.error("startAccessing failed for \(resolved.path)")
            }
            if isStale,
               let fresh = try? resolved.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                bookmarks[path] = fresh
                changed = true
            }
        }
        if changed {
            UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
        }
    }

    private func saveBookmark(for folder: URL) {
        guard let data = try? folder.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            Log.fileService.error("Could not create bookmark for \(folder.path)")
            return
        }
        var bookmarks = UserDefaults.standard.dictionary(forKey: Self.bookmarksKey) as? [String: Data] ?? [:]
        bookmarks[folder.path] = data
        UserDefaults.standard.set(bookmarks, forKey: Self.bookmarksKey)
    }

    /// The user's real home directory. In a sandboxed app, NSHomeDirectory()
    /// points at the container, but the passwd entry still has the real one.
    private static var realHomeDirectory: URL {
        if let passwd = getpwuid(getuid()), let dir = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
