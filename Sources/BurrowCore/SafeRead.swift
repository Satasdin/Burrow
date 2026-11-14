import Foundation

/// Reading a file someone else may have put there (a teammate's folder, a shared or cloned vault) without being led
/// anywhere by it (D-112). The file is opened once, without blocking and, where asked, without following a symlink; then
/// what was opened is checked: a regular file, no larger than the cap. Only then is it read, and never past the cap.
/// A FIFO or a device opened this way never blocks the read, and a file swapped for a link after a check is not followed,
/// because the check is made on what was opened.
public enum SafeRead {
    public enum Refusal: Error, Equatable, CustomStringConvertible, Sendable {
        case missing
        case link
        case notRegular
        case tooLarge(Int)
        case unreadable

        public var description: String {
            switch self {
            case .missing: return "not there"
            case .link: return "a symbolic link, never followed"
            case .notRegular: return "not a regular file (a pipe, a device or a folder)"
            case let .tooLarge(size): return "larger than allowed (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))"
            case .unreadable: return "could not be read"
            }
        }
    }

    /// What a path is, without following a final symlink and without opening it.
    public static func kind(_ path: String) -> FileAttributeType? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
    }

    /// True for a real folder, not a link to one.
    public static func isRealFolder(_ path: String) -> Bool { kind(path) == .typeDirectory }

    /// The bytes of a regular file of at most `cap` bytes. `followLinks: false` refuses a path whose last part is a link.
    public static func data(_ path: String, cap: Int, followLinks: Bool = false) -> Result<Data, Refusal> {
        if !followLinks, kind(path) == .typeSymbolicLink { return .failure(.link) }
        let flags = O_RDONLY | O_NONBLOCK | O_CLOEXEC | (followLinks ? 0 : O_NOFOLLOW)
        let fd = open(path, flags)
        guard fd >= 0 else {
            switch errno {
            case ENOENT: return .failure(.missing)
            case ELOOP: return .failure(.link)
            default: return .failure(.unreadable)
            }
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { return .failure(.unreadable) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { return .failure(.notRegular) }
        guard info.st_size <= off_t(cap) else { return .failure(.tooLarge(Int(info.st_size))) }
        // Back to blocking for a regular file: the read ends at the file's end.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while out.count <= cap {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 { return .failure(.unreadable) }
            if count == 0 { break }
            out.append(contentsOf: buffer[0..<count])
        }
        // A file that grew past the cap after it was measured is refused, never read on.
        guard out.count <= cap else { return .failure(.tooLarge(out.count)) }
        return .success(out)
    }

    /// The same, as UTF-8 text.
    public static func text(_ path: String, cap: Int, followLinks: Bool = false) -> Result<String, Refusal> {
        switch data(path, cap: cap, followLinks: followLinks) {
        case let .failure(refusal): return .failure(refusal)
        case let .success(bytes):
            guard let text = String(data: bytes, encoding: .utf8) else { return .failure(.unreadable) }
            return .success(text)
        }
    }
}
