import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

struct SourceItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let url: URL
    let isDirectory: Bool

    var name: String { url.lastPathComponent }

    init(url: URL) {
        self.id = UUID()
        self.url = url.standardizedFileURL
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: self.url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
    }
}

struct DestinationInfo: Equatable {
    var url: URL
    var volumeURL: URL
    var name: String
    var format: String
    var freeBytes: Int64
    var totalBytes: Int64
    var isExFAT: Bool
    var isReadOnly: Bool
    var isEjectable: Bool
}

enum AppPhase: Equatable {
    case idle
    case copying
    case syncing
    case success
}

@MainActor
@Observable
final class AppModel {
    var sources: [SourceItem] = []
    var itemSizes: [UUID: Int64] = [:]
    var totalBytes: Int64 = 0
    var destination: DestinationInfo?
    var phase: AppPhase = .idle
    var progress = CopyProgress()
    var errorMessage: String?
    var showError = false
    var isSourceTargeted = false
    var isDestTargeted = false
    var isEjecting = false

    @ObservationIgnored private var sizeTask: Task<Void, Never>?
    @ObservationIgnored private var copyTask: Task<Void, Never>?
    @ObservationIgnored private let cancelFlag = CancelFlag()
    @ObservationIgnored private let progressTicker = ProgressTicker()

    var canCopy: Bool {
        !sources.isEmpty && destination != nil && !isBusy && !insufficientSpace && !(destination?.isReadOnly ?? false)
    }

    var isBusy: Bool {
        phase == .copying || phase == .syncing
    }

    var insufficientSpace: Bool {
        guard let destination else { return false }
        return totalBytes > 0 && destination.freeBytes < totalBytes
    }

    func add(urls: [URL]) {
        guard !isBusy else { return }
        for url in urls {
            let item = SourceItem(url: url)
            if !sources.contains(where: { $0.url == item.url }) {
                sources.append(item)
            }
        }
        if phase == .success { phase = .idle }
        refreshSizes()
    }

    func remove(_ item: SourceItem) {
        guard !isBusy else { return }
        sources.removeAll { $0.id == item.id }
        itemSizes[item.id] = nil
        totalBytes = itemSizes.values.reduce(0, +)
        if phase == .success { phase = .idle }
    }

    func clearSources() {
        guard !isBusy else { return }
        sources.removeAll()
        itemSizes.removeAll()
        totalBytes = 0
        if phase == .success { phase = .idle }
    }

    func pickFiles() {
        presentOpenPanel(files: true, folders: false, multiple: true, message: "选择要拷贝的文件")
    }

    func pickFolder() {
        presentOpenPanel(files: false, folders: true, multiple: false, message: "选择要拷贝的文件夹")
    }

    func pickDestination() {
        presentOpenPanel(files: false, folders: true, multiple: false, message: "选择 exFAT 磁盘上的目标文件夹") { [weak self] urls in
            guard let self, let url = urls.first else { return }
            self.setDestination(url)
        }
    }

    func setDestination(_ url: URL) {
        guard !isBusy else { return }
        destination = DestinationProbe.inspect(url)
        if phase == .success { phase = .idle }
    }

    func startCopy() {
        guard canCopy, let destination else { return }
        cancelFlag.isCancelled = false
        phase = .copying
        progress = CopyProgress(bytesTotal: totalBytes)
        let items = sources
        let destURL = destination.url
        let ticker = progressTicker
        ticker.start { snapshot in
            self.progress = snapshot
            if snapshot.stage == .syncing {
                self.phase = .syncing
            }
        }
        copyTask = Task {
            defer { ticker.stop() }
            do {
                try await CopyEngine.copy(
                    sources: items,
                    destination: destURL,
                    cancelFlag: cancelFlag,
                    onProgress: { snapshot in
                        ticker.update(snapshot)
                    }
                )
                try Task.checkCancellation()
                phase = .success
                NSSound(named: "Glass")?.play()
            } catch is CancellationError {
                phase = .idle
            } catch CopyError.cancelled {
                phase = .idle
            } catch {
                phase = .idle
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    func cancelCopy() {
        cancelFlag.isCancelled = true
        copyTask?.cancel()
    }

    func resetAfterSuccess() {
        phase = .idle
        progress = CopyProgress()
        sources.removeAll()
        itemSizes.removeAll()
        totalBytes = 0
    }

    func revealDestination() {
        guard let destination else { return }
        NSWorkspace.shared.open(destination.url)
    }

    func ejectDestination() {
        guard !isBusy, !isEjecting, let destination, destination.isEjectable else { return }
        isEjecting = true
        let volumeURL = destination.volumeURL
        let name = destination.name
        Task {
            defer { isEjecting = false }
            do {
                try await DiskEject.eject(volumeURL)
                self.destination = nil
                if phase == .success {
                    phase = .idle
                    progress = CopyProgress()
                }
                NSSound(named: "Submarine")?.play()
            } catch {
                errorMessage = "无法弹出「\(name)」：\(error.localizedDescription)"
                showError = true
            }
        }
    }

    func handleDrop(_ providers: [NSItemProvider], toDestination: Bool) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }
        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await Self.loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            await MainActor.run {
                if toDestination, let first = urls.first {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
                    self.setDestination(isDir.boolValue ? first : first.deletingLastPathComponent())
                } else {
                    self.add(urls: urls)
                }
            }
        }
        return true
    }

    private func presentOpenPanel(
        files: Bool,
        folders: Bool,
        multiple: Bool,
        message: String,
        onPick: (([URL]) -> Void)? = nil
    ) {
        let urls = FilePicker.choose(
            files: files,
            folders: folders,
            multiple: multiple,
            message: message
        )
        guard !urls.isEmpty else { return }
        if let onPick {
            onPick(urls)
        } else {
            add(urls: urls)
        }
    }

    private func refreshSizes() {
        sizeTask?.cancel()
        let items = sources
        sizeTask = Task.detached(priority: .utility) {
            var map: [UUID: Int64] = [:]
            var total: Int64 = 0
            for item in items {
                if Task.isCancelled { return }
                let size = CopyEngine.byteSize(of: item.url)
                map[item.id] = size
                total += size
            }
            let sized = map
            let summed = total
            await MainActor.run {
                self.itemSizes = sized
                self.totalBytes = summed
            }
        }
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data,
                   let str = String(data: data, encoding: .utf8),
                   let url = URL(string: str) {
                    continuation.resume(returning: url)
                    return
                }
                if let str = item as? String, let url = URL(string: str) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }
}

enum DestinationProbe {
    static func inspect(_ url: URL) -> DestinationInfo {
        let values = try? url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeAvailableCapacityKey,
            .volumeTotalCapacityKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsReadOnlyKey,
            .volumeURLKey,
            .volumeIsEjectableKey,
            .volumeIsRemovableKey
        ])
        let fs = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
        let format = values?.volumeLocalizedFormatDescription ?? "未知格式"

        let resourceFree = values?.volumeAvailableCapacity.map { Int64($0) } ?? 0
        let fsFree = (fs?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let free = max(resourceFree, fsFree)

        let resourceTotal = values?.volumeTotalCapacity.map { Int64($0) } ?? 0
        let fsTotal = (fs?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let total = max(resourceTotal, fsTotal)

        let volumeURL = (values?.allValues[.volumeURLKey] as? URL)
            ?? volumeRoot(for: url)
        let bootVolume = (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeURLKey]))
            .flatMap { $0.allValues[.volumeURLKey] as? URL }
        let isBoot = bootVolume.map { $0.standardizedFileURL == volumeURL.standardizedFileURL } ?? (volumeURL.path == "/")
        let isEjectable = !isBoot && (
            (values?.volumeIsEjectable ?? false)
            || (values?.volumeIsRemovable ?? false)
            || volumeURL.path.hasPrefix("/Volumes/")
        )

        return DestinationInfo(
            url: url.standardizedFileURL,
            volumeURL: volumeURL.standardizedFileURL,
            name: values?.volumeName ?? url.lastPathComponent,
            format: format,
            freeBytes: free,
            totalBytes: total,
            isExFAT: format.localizedCaseInsensitiveContains("exfat"),
            isReadOnly: values?.volumeIsReadOnly ?? false,
            isEjectable: isEjectable
        )
    }

    private static func volumeRoot(for url: URL) -> URL {
        let parts = url.standardizedFileURL.pathComponents
        if parts.count >= 3, parts[1] == "Volumes" {
            return URL(fileURLWithPath: "/Volumes/\(parts[2])")
        }
        return url.standardizedFileURL
    }
}

enum DiskEject {
    enum Failure: LocalizedError {
        case failed

        var errorDescription: String? {
            "磁盘正忙，或已被其他程序占用"
        }
    }

    static func eject(_ volumeURL: URL) async throws {
        let ejected = await MainActor.run {
            NSWorkspace.shared.unmountAndEjectDevice(atPath: volumeURL.path)
        }
        if ejected { return }
        try await Task.detached(priority: .userInitiated) {
            try runDiskUtil(volumeURL)
        }.value
    }

    private static func runDiskUtil(_ volumeURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["eject", volumeURL.path]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.failed
        }
    }
}
