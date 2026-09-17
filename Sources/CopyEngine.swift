import Darwin
import Foundation

struct CopyProgress: Equatable, Sendable {
    enum Stage: Equatable {
        case copying
        case syncing
    }

    var stage: Stage = .copying
    var currentName: String = ""
    var filesDone: Int = 0
    var filesTotal: Int = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0

    var fraction: Double {
        guard bytesTotal > 0 else {
            guard filesTotal > 0 else { return 0 }
            return Double(filesDone) / Double(filesTotal)
        }
        return min(1, Double(bytesDone) / Double(bytesTotal))
    }
}

enum CopyError: LocalizedError {
    case cancelled
    case noDestination
    case nestedDestination
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "已取消"
        case .noDestination:
            return "未选择目标文件夹"
        case .nestedDestination:
            return "目标位置不能位于源文件夹内部"
        case .copyFailed(let message):
            return message
        }
    }
}

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    var isCancelled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }
        set {
            lock.lock()
            _isCancelled = newValue
            lock.unlock()
        }
    }
}

final class ProgressTicker: @unchecked Sendable {
    private let lock = NSLock()
    private var latest = CopyProgress()
    private var timer: DispatchSourceTimer?

    func start(_ handler: @escaping @MainActor (CopyProgress) -> Void) {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let snapshot = self.latest
            self.lock.unlock()
            MainActor.assumeIsolated {
                handler(snapshot)
            }
        }
        timer.resume()
        self.timer = timer
    }

    func update(_ progress: CopyProgress) {
        lock.lock()
        latest = progress
        lock.unlock()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

enum CopyEngine {
    private static let readSize = 1024 * 1024
    private static let writeSize = 256 * 1024

    static func byteSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) {
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                if values?.isRegularFile == true {
                    total += Int64(values?.fileSize ?? 0)
                }
            }
        }
        return total
    }

    static func copy(
        sources: [SourceItem],
        destination: URL,
        cancelFlag: CancelFlag,
        onProgress: @escaping @Sendable (CopyProgress) -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try run(
                sources: sources,
                destination: destination,
                cancelFlag: cancelFlag,
                onProgress: onProgress
            )
        }.value
    }

    private static func run(
        sources: [SourceItem],
        destination: URL,
        cancelFlag: CancelFlag,
        onProgress: @escaping @Sendable (CopyProgress) -> Void
    ) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: destination.path, isDirectory: &isDir), isDir.boolValue else {
            throw CopyError.noDestination
        }

        let destPath = destination.standardizedFileURL.path
        for item in sources where item.isDirectory {
            let sourcePath = item.url.standardizedFileURL.path
            if destPath == sourcePath || destPath.hasPrefix(sourcePath + "/") {
                throw CopyError.nestedDestination
            }
        }

        let jobs = try collectJobs(sources: sources, destination: destination)
        var progress = CopyProgress(
            filesTotal: jobs.filter(\.isFile).count,
            bytesTotal: jobs.reduce(0) { $0 + $1.size }
        )
        onProgress(progress)

        var inFlightPartial: URL?
        do {
            for job in jobs {
                if cancelFlag.isCancelled || Task.isCancelled {
                    throw CopyError.cancelled
                }
                if job.isFile {
                    progress.currentName = job.displayName
                    onProgress(progress)
                    let partial = partialURL(for: job.destination)
                    inFlightPartial = partial
                    try copyFile(from: job.source, to: partial) { chunk in
                        if cancelFlag.isCancelled { throw CopyError.cancelled }
                        progress.bytesDone += chunk
                        onProgress(progress)
                    }
                    try promotePartial(partial, to: job.destination)
                    inFlightPartial = nil
                    progress.filesDone += 1
                    onProgress(progress)
                } else {
                    try fm.createDirectory(at: job.destination, withIntermediateDirectories: true)
                }
            }
        } catch {
            removeIncompleteFile(inFlightPartial)
            try? fullSync(at: destination)
            throw error
        }

        progress.stage = .syncing
        progress.currentName = "正在同步磁盘缓存"
        progress.bytesDone = progress.bytesTotal
        onProgress(progress)
        try fullSync(at: destination)
    }

    private struct Job {
        var source: URL
        var destination: URL
        var isFile: Bool
        var size: Int64
        var displayName: String
    }

    private static func collectJobs(sources: [SourceItem], destination: URL) throws -> [Job] {
        let fm = FileManager.default
        var jobs: [Job] = []

        for item in sources {
            if item.isDirectory {
                let folderDest = destination.appendingPathComponent(item.name, isDirectory: true)
                jobs.append(
                    Job(source: item.url, destination: folderDest, isFile: false, size: 0, displayName: item.name)
                )
                guard let enumerator = fm.enumerator(
                    at: item.url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
                    options: []
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
                    let relative = fileURL.path.replacingOccurrences(of: item.url.path, with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let destURL = folderDest.appendingPathComponent(relative)
                    if values.isDirectory == true {
                        jobs.append(
                            Job(source: fileURL, destination: destURL, isFile: false, size: 0, displayName: fileURL.lastPathComponent)
                        )
                    } else if values.isRegularFile == true {
                        jobs.append(
                            Job(
                                source: fileURL,
                                destination: destURL,
                                isFile: true,
                                size: Int64(values.fileSize ?? 0),
                                displayName: fileURL.lastPathComponent
                            )
                        )
                    }
                }
            } else {
                let destURL = destination.appendingPathComponent(item.name)
                let size = (try? fm.attributesOfItem(atPath: item.url.path)[.size] as? Int64) ?? 0
                jobs.append(
                    Job(source: item.url, destination: destURL, isFile: true, size: size, displayName: item.name)
                )
            }
        }
        return jobs
    }

    private static func partialURL(for destination: URL) -> URL {
        URL(fileURLWithPath: destination.path + ".partial")
    }

    private static func promotePartial(_ partial: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: partial, to: destination)
    }

    private static func removeIncompleteFile(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func copyFile(
        from source: URL,
        to destination: URL,
        onChunk: (Int64) throws -> Void
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        let srcFD = source.withUnsafeFileSystemRepresentation { ptr -> Int32 in
            guard let ptr else { return -1 }
            return open(ptr, O_RDONLY)
        }
        guard srcFD >= 0 else {
            throw CopyError.copyFailed("无法读取 \(source.lastPathComponent)")
        }
        defer { close(srcFD) }

        let destFD = destination.withUnsafeFileSystemRepresentation { ptr -> Int32 in
            guard let ptr else { return -1 }
            return open(ptr, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        }
        guard destFD >= 0 else {
            throw CopyError.copyFailed("无法写入 \(destination.lastPathComponent)")
        }
        defer { close(destFD) }
        _ = fcntl(destFD, F_NOCACHE, 1)

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: readSize)
        defer { buffer.deallocate() }

        while true {
            let n = Darwin.read(srcFD, buffer, readSize)
            if n == 0 { break }
            if n < 0 {
                throw CopyError.copyFailed("读取失败：\(source.lastPathComponent)")
            }
            var offset = 0
            while offset < n {
                let chunk = min(writeSize, n - offset)
                let written = Darwin.write(destFD, buffer + offset, chunk)
                if written <= 0 {
                    throw CopyError.copyFailed("写入失败：\(destination.lastPathComponent)")
                }
                offset += written
                try onChunk(Int64(written))
            }
        }

        if let attrs = try? fm.attributesOfItem(atPath: source.path),
           let date = attrs[.modificationDate] as? Date {
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: destination.path)
        }
    }

    /// Flush OS cache then force the destination volume to write through.
    /// This is the critical step that prevents exFAT corruption on unsafe eject.
    private static func fullSync(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sync")
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw CopyError.copyFailed("sync 失败（状态码 \(process.terminationStatus)）")
        }

        let fd = open(url.path, O_RDONLY)
        if fd >= 0 {
            _ = fcntl(fd, F_FULLFSYNC)
            close(fd)
        }
    }
}
