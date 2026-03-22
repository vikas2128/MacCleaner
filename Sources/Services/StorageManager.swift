import Foundation
import SwiftUI

// MARK: - Clean Result

struct CleanResult {
    let categoryName: String
    let freedBytes: Int64
    let usedPermanentDelete: Bool
    let errors: [String]
}

// MARK: - StorageManager

@MainActor
class StorageManager: ObservableObject {

    @Published var categories: [StorageCategory] = StorageCategoryType.allCases.map { StorageCategory(type: $0) }
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var totalScannedSize: Int64 = 0
    @Published var totalCleanedSize: Int64 = 0
    @Published var cleanResults: [CleanResult] = []
    @Published var lastError: String? = nil

    // Preview items ready to show the user before cleaning
    @Published var previewItems: [PreviewItem] = []
    @Published var showPreview = false

    // MARK: - Scanning

    func startScan() {
        guard !isScanning && !isCleaning else { return }
        isScanning = true
        totalScannedSize = 0
        previewItems = []

        for index in categories.indices {
            categories[index].sizeInBytes = 0
            categories[index].cleanableItems = []
            categories[index].snapshotDates = []
            categories[index].isCheckedForClean = false
            categories[index].isScanning = true
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let types = StorageCategoryType.allCases

            await withTaskGroup(of: (Int, [URL], [String], Int64).self) { group in
                for (index, type) in types.enumerated() {
                    group.addTask {
                        let (items, snapshots, size) = await Self.scanCategory(type)
                        return (index, items, snapshots, size)
                    }
                }
                for await (index, items, snapshots, size) in group {
                    await MainActor.run {
                        self.categories[index].cleanableItems = items
                        self.categories[index].snapshotDates = snapshots
                        self.categories[index].sizeInBytes = size
                        self.categories[index].isScanning = false
                        self.totalScannedSize += size
                        // Auto-check only truly safe categories
                        if self.categories[index].type.safetyRisk == .safe && size > 0 {
                            self.categories[index].isCheckedForClean = true
                        }
                    }
                }
            }

            await MainActor.run { self.isScanning = false }
        }
    }

    // MARK: - Build Preview then Clean

    /// Called when user taps "Clean Now" — builds preview items, then shows the sheet.
    func requestCleanWithPreview() {
        guard !isScanning && !isCleaning else { return }

        var items: [PreviewItem] = []

        for cat in categories where cat.isCheckedForClean {
            // File-based items
            for url in cat.cleanableItems {
                let size = Self.calculateSize(for: url)
                items.append(PreviewItem(
                    url: url,
                    categoryName: cat.type.rawValue,
                    categoryColor: cat.type.color,
                    sizeInBytes: size
                ))
            }
            // Snapshot-based items (Time Machine)
            for snap in cat.snapshotDates {
                // Represent each snapshot as a synthetic URL for display
                let fakeURL = URL(fileURLWithPath: "/private/var/snapshots/\(snap)")
                items.append(PreviewItem(
                    url: fakeURL,
                    categoryName: cat.type.rawValue,
                    categoryColor: cat.type.color,
                    sizeInBytes: cat.snapshotDates.count > 0
                        ? cat.sizeInBytes / Int64(cat.snapshotDates.count) : 0
                ))
            }
        }

        previewItems = items.sorted { $0.sizeInBytes > $1.sizeInBytes }
        showPreview = true
    }

    /// Called from PreviewSheet when user confirms which items to delete.
    func cleanConfirmed(selectedItems: [PreviewItem]) {
        guard !isCleaning else { return }
        isCleaning = true
        cleanResults = []
        lastError = nil

        // Group by category name
        var filesByCategory: [String: [URL]] = [:]
        var snapshotsByCategory: [String: [String]] = [:]

        for item in selectedItems {
            if item.url.path.hasPrefix("/private/var/snapshots/") {
                // It's a snapshot — extract date from path
                let snapDate = item.url.lastPathComponent
                snapshotsByCategory[item.categoryName, default: []].append(snapDate)
            } else {
                filesByCategory[item.categoryName, default: []].append(item.url)
            }
        }

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Clean file-based items
            await withTaskGroup(of: CleanResult.self) { group in
                for (catName, urls) in filesByCategory {
                    group.addTask { await Self.cleanItems(urls, categoryName: catName) }
                }
                for (catName, dates) in snapshotsByCategory {
                    group.addTask { await Self.cleanSnapshots(dates, categoryName: catName) }
                }
                for await result in group {
                    await MainActor.run {
                        self.cleanResults.append(result)
                        self.totalCleanedSize += result.freedBytes
                        self.totalScannedSize = max(0, self.totalScannedSize - result.freedBytes)
                        if let idx = self.categories.firstIndex(where: { $0.type.rawValue == result.categoryName }) {
                            self.categories[idx].sizeInBytes = max(0, self.categories[idx].sizeInBytes - result.freedBytes)
                            self.categories[idx].cleanableItems = []
                            self.categories[idx].snapshotDates = []
                            self.categories[idx].isCheckedForClean = false
                        }
                        if result.usedPermanentDelete {
                            self.lastError = "'\(result.categoryName)': items were permanently deleted (Trash unavailable)."
                        }
                        if !result.errors.isEmpty {
                            self.lastError = "Errors in '\(result.categoryName)': \(result.errors.joined(separator: "; "))"
                        }
                    }
                }
            }

            await MainActor.run { self.isCleaning = false }
        }
    }

    // MARK: - Scan one category

    private static func scanCategory(_ type: StorageCategoryType) async -> ([URL], [String], Int64) {
        // Snapshot-based (Time Machine)
        if type.usesTmutil {
            let dates = ShellRunner.listLocalSnapshots()
            // Estimate snapshot size: rough heuristic of 500MB per snapshot
            // (real size requires sudo + diskutil apfs listSnapshots which we skip for safety)
            let estimatedSize = Int64(dates.count) * 500 * 1024 * 1024
            return ([], dates, estimatedSize)
        }

        // Project Build Caches (scanned rapidly via shell find)
        if type == .projectBuildFiles {
            let items = await scanProjectCaches()
            var totalSize: Int64 = 0
            for item in items { totalSize += calculateSize(for: item) }
            return (items, [], totalSize)
        }

        guard let root = type.path else { return ([], [], 0) }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return ([], [], 0) }

        guard let topLevel = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [] // Removed .skipsHiddenFiles because developer caches often contain hidden files we want to clean
        ) else { return ([], [], 0) }

        var cleanableItems: [URL] = []

        for item in topLevel {
            // Skip symlinks
            let isSymlink = (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            if isSymlink { continue }

            switch type {
            case .userCaches:
                let name = item.lastPathComponent
                let isSafe = StorageCategoryType.safeCachePrefixes.contains(where: { name.lowercased().hasPrefix($0.lowercased()) })
                if isSafe { cleanableItems.append(item) }

            case .xcodeArchives:
                // Drill into date-named folders for .xcarchive bundles
                if let dateFolders = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: []) {
                    for archive in dateFolders where archive.pathExtension == "xcarchive" {
                        cleanableItems.append(archive)
                    }
                }

            case .gradleCaches:
                let name = item.lastPathComponent.lowercased()
                if name.hasPrefix("modules-") ||
                   name.hasPrefix("jars-") ||
                   name.hasPrefix("transforms-") ||
                   name.hasPrefix("build-cache-") {
                    cleanableItems.append(item)
                }

            default:
                cleanableItems.append(item)
            }
        }

        var totalSize: Int64 = 0
        for item in cleanableItems { totalSize += calculateSize(for: item, fm: fm) }
        return (cleanableItems, [], totalSize)
    }

    // MARK: - Scan Project Caches
    private static func scanProjectCaches() async -> [URL] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let devPath = homePath + "/Developer"
        guard FileManager.default.fileExists(atPath: devPath) else { return [] }
        
        let args = [
            devPath,
            "-type", "d",
            "(",
            "-name", "node_modules",
            "-o", "-name", ".dart_tool",
            "-o", "-name", "Pods",
            "-o", "-name", ".next",
            "-o", "-name", "build",
            ")",
            "-prune"
        ]
        
        let (output, success) = ShellRunner.run("/usr/bin/find", args: args)
        guard success else { return [] }
        
        return output.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Size Calculation

    static func calculateSize(for url: URL, fm: FileManager = .default) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if isDir.boolValue {
            var total: Int64 = 0
            let opts: FileManager.DirectoryEnumerationOptions = []  // don't skip packages — we want real sizes
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey],
                options: opts
            ) else { return 0 }
            for case let fileURL as URL in enumerator {
                if (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
            return total
        } else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    // MARK: - Clean file-based items

    private static func cleanItems(_ items: [URL], categoryName: String) async -> CleanResult {
        let fm = FileManager.default
        var freedBytes: Int64 = 0
        var usedPermanentDelete = false
        var errors: [String] = []

        for item in items {
            guard fm.fileExists(atPath: item.path), isPathSafe(item) else {
                errors.append("Skipped unsafe/missing path: \(item.lastPathComponent)")
                continue
            }
            let size = calculateSize(for: item, fm: fm)
            do {
                try fm.trashItem(at: item, resultingItemURL: nil)
                freedBytes += size
            } catch {
                do {
                    try fm.removeItem(at: item)
                    freedBytes += size
                    usedPermanentDelete = true
                } catch let e {
                    errors.append("\(item.lastPathComponent): \(e.localizedDescription)")
                }
            }
        }
        return CleanResult(categoryName: categoryName, freedBytes: freedBytes, usedPermanentDelete: usedPermanentDelete, errors: errors)
    }

    // MARK: - Clean Time Machine snapshots

    private static func cleanSnapshots(_ dates: [String], categoryName: String) async -> CleanResult {
        var freedBytes: Int64 = 0
        var errors: [String] = []
        let estimatedPerSnapshot: Int64 = 500 * 1024 * 1024

        for date in dates {
            let success = ShellRunner.deleteLocalSnapshot(date)
            if success {
                freedBytes += estimatedPerSnapshot
            } else {
                errors.append("Could not delete snapshot \(date) — may need admin privileges.")
            }
        }
        return CleanResult(categoryName: categoryName, freedBytes: freedBytes, usedPermanentDelete: false, errors: errors)
    }

    // MARK: - Safety guard

    private static func isPathSafe(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardized
        let target = url.standardized
        if target.path.hasPrefix(home.path + "/") { return true }
        // macOS symlinks ~/Library/Logs/DiagnosticReports to the root /Library or /private/var
        // Allow these specifically since they are verified safe targets
        if target.path.hasPrefix("/Library/Logs/DiagnosticReports") ||
           target.path.hasPrefix("/private/var/db/DiagnosticReports") ||
           target.path.hasPrefix("/private/var/folders/") { return true }
        return false
    }
}
