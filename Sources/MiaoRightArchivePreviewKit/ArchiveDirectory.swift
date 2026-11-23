import CArchive
import Darwin
import Foundation

public struct ArchiveDirectory: Sendable {
    public struct Entry: Sendable {
        public let name: String
        public let size: Int64?
        public let modified: Date?
        public let children: [Entry]?
    }

    public let entries: [Entry]
    public let files: Int
    public let folders: Int
    public let bytes: Int64
    public let isPartial: Bool

    public enum ReadError: Error {
        case unreadable
        case encrypted
    }

    public static func read(_ url: URL, entryLimit: Int = 40_000, timeLimit: Duration = .seconds(3)) throws -> Self {
        guard let archive = archive_read_new() else { throw ReadError.unreadable }
        defer { _ = archive_read_free(archive) }
        archive_read_support_format_zip_seekable(archive)
        archive_read_support_format_7zip(archive)
        archive_read_support_format_rar(archive)
        archive_read_support_format_rar5(archive)
        archive_read_support_format_tar(archive)
        archive_read_support_format_cpio(archive)
        archive_read_support_format_empty(archive)
        let isCompressedStream = ["gz", "bz2", "xz"].contains(url.pathExtension.lowercased())
        if isCompressedStream { archive_read_support_format_raw(archive) }
        archive_read_support_filter_gzip(archive)
        archive_read_support_filter_bzip2(archive)
        archive_read_support_filter_xz(archive)
        guard url.withUnsafeFileSystemRepresentation({ archive_read_open_filename(archive, $0, 64 * 1024) }) == CArchiveOK else {
            throw readError(archive)
        }

        let deadline = ContinuousClock.now + timeLimit
        let root = Folder()
        var count = 0
        var files = 0
        var folders = 0
        var bytes: Int64 = 0
        var partial = false
        while true {
            try Task.checkCancellation()
            if ContinuousClock.now >= deadline {
                partial = true
                break
            }
            var header: OpaquePointer?
            let status = archive_read_next_header(archive, &header)
            if status == CArchiveEOF {
                if archive_format(archive) == CArchiveEmpty { throw ReadError.unreadable }
                break
            }
            guard let header, status == CArchiveOK || status == CArchiveWarn else { throw readError(archive) }
            if archive_format(archive) == CArchiveRaw {
                guard archive_filter_code(archive, 0) > 0 else { throw ReadError.unreadable }
                let entry = Entry(name: url.deletingPathExtension().lastPathComponent, size: nil, modified: nil, children: nil)
                return Self(entries: [entry], files: 1, folders: 0, bytes: 0, isPartial: false)
            }
            if count >= entryLimit { partial = true; break }
            count += 1
            guard let raw = archive_entry_pathname_utf8(header) ?? archive_entry_pathname(header) else {
                partial = true
                continue
            }
            let path = String(cString: raw)
            let isDirectory = archive_entry_filetype(header) == S_IFDIR || path.hasSuffix("/")
            let components = path.split(separator: "/").filter { $0 != "." }
            if components.isEmpty { continue }
            guard components.count <= 64, path.utf8.count <= 16_384, !components.contains("..") else {
                partial = true
                continue
            }
            if folders + components.count > 80_000 {
                partial = true
                break
            }
            var folder = root
            let directories = isDirectory ? components[...] : components.dropLast()
            for component in directories {
                let name = String(component)
                if let existing = folder.folders[name] {
                    folder = existing
                } else {
                    let newFolder = Folder()
                    folder.folders[name] = newFolder
                    folder = newFolder
                    folders += 1
                }
            }
            let date = archive_entry_mtime_is_set(header) != 0
                ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(header))) : nil
            if isDirectory {
                folder.modified = date
            } else if let name = components.last {
                let size = archive_entry_size_is_set(header) != 0 ? max(0, archive_entry_size(header)) : nil
                folder.files.append(Entry(name: String(name), size: size, modified: date, children: nil))
                files += 1
                bytes = bytes > Int64.max - (size ?? 0) ? Int64.max : bytes + (size ?? 0)
            }
        }
        return Self(entries: root.entries(), files: files, folders: folders, bytes: bytes, isPartial: partial)
    }

    private static func readError(_ archive: OpaquePointer) -> ReadError {
        let message = archive_error_string(archive).map { String(cString: $0).lowercased() } ?? ""
        return message.contains("encrypt") || message.contains("passphrase") ? .encrypted : .unreadable
    }

    private final class Folder {
        var folders: [String: Folder] = [:]
        var files: [Entry] = []
        var modified: Date?

        func entries() -> [Entry] {
            folders.keys.sorted(by: ordered).compactMap { name in
                folders[name].map { Entry(name: name, size: nil, modified: $0.modified, children: $0.entries()) }
            } + files.sorted { ordered($0.name, $1.name) }
        }

        private func ordered(_ lhs: String, _ rhs: String) -> Bool {
            let comparison = lhs.localizedStandardCompare(rhs)
            return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
        }
    }
}
