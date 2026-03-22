import Foundation
import SwiftUI

// MARK: - Safety Risk Level

enum SafetyRisk {
    case safe        // Fully safe to delete
    case moderate    // Usually safe, but worth a warning
    case caution     // User should know what they're deleting
}

// MARK: - Category Group

enum CategoryGroup: String {
    case developer  = "Developer"
    case general    = "General"
    case systemData = "System Data"
}

// MARK: - Storage Category Type

enum StorageCategoryType: String, CaseIterable, Identifiable {
    // Developer
    case xcodeDerivedData  = "Xcode Derived Data"
    case xcodeArchives     = "Xcode Archives"
    case xcodeSimulators   = "CoreSimulator Devices"
    case gradleCaches      = "Android Gradle Cache"
    case npmCache          = "NPM Cache"
    case cocoaPodsCache    = "CocoaPods Cache"
    case flutterPubCache   = "Flutter Pub Cache"
    case projectBuildFiles = "Project Build Files"
    // General
    case userCaches        = "App Caches"
    case userLogs          = "User Logs"
    // System Data
    case iosBackups        = "iPhone/iPad Backups"
    case crashReports      = "Crash Reports"
    case timeMachineSnaps  = "Time Machine Snapshots"

    var id: String { rawValue }

    // Group membership
    var group: CategoryGroup {
        switch self {
        case .xcodeDerivedData, .xcodeArchives, .xcodeSimulators,
             .gradleCaches, .npmCache, .cocoaPodsCache, .flutterPubCache, .projectBuildFiles:
            return .developer
        case .userCaches, .userLogs:
            return .general
        case .iosBackups, .crashReports, .timeMachineSnaps:
            return .systemData
        }
    }

    /// The top-level URL for this category (nil for tmutil-based types)
    var path: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .xcodeDerivedData:  return home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        case .xcodeArchives:     return home.appendingPathComponent("Library/Developer/Xcode/Archives")
        case .xcodeSimulators:   return home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        case .gradleCaches:      return home.appendingPathComponent(".gradle/caches")
        case .npmCache:          return home.appendingPathComponent(".npm")
        case .cocoaPodsCache:    return home.appendingPathComponent("Library/Caches/CocoaPods")
        case .flutterPubCache:   return home.appendingPathComponent(".pub-cache")
        case .projectBuildFiles: return nil // custom scanned path
        case .userCaches:        return home.appendingPathComponent("Library/Caches")
        case .userLogs:          return home.appendingPathComponent("Library/Logs")
        case .iosBackups:        return home.appendingPathComponent("Library/Application Support/MobileSync/Backup")
        case .crashReports:      return home.appendingPathComponent("Library/Logs/DiagnosticReports")
        case .timeMachineSnaps:  return nil   // handled via tmutil, not FileManager
        }
    }

    /// Whether to use tmutil instead of FileManager
    var usesTmutil: Bool { self == .timeMachineSnaps }

    /// Whether we delete CONTENTS of the root, or use a curated whitelist
    var deletesRawContents: Bool {
        switch self {
        case .xcodeDerivedData, .gradleCaches, .npmCache, .cocoaPodsCache, .flutterPubCache:
            return true
        case .xcodeArchives:     return false
        case .xcodeSimulators:   return false
        case .projectBuildFiles: return false   // each project folder individually
        case .userCaches:        return false   // whitelisted
        case .userLogs:          return true
        case .iosBackups:        return false   // each backup folder
        case .crashReports:      return true
        case .timeMachineSnaps:  return false   // each snapshot individually
        }
    }

    /// For userCaches: only delete caches from known SAFE third-party apps.
    static let safeCachePrefixes: [String] = [
        "com.google.Chrome", "com.google.chrome", "com.mozilla.firefox",
        "com.microsoft", "com.spotify", "com.getdropbox", "com.slack",
        "com.tinyspeck", "com.jetbrains", "io.cleanmaster", "com.adobe",
        "com.zoom", "us.zoom", "com.figma", "com.notion", "com.atlassian",
        "com.sublimetext", "com.panic", "com.github", "com.sourcegraph",
        "com.vscodium", "com.microsoft.VSCode", "org.llvm", "org.swift", "pip"
    ]

    var safetyRisk: SafetyRisk {
        switch self {
        case .xcodeDerivedData, .gradleCaches, .npmCache, .cocoaPodsCache, .flutterPubCache:
            return .safe
        case .userLogs:          return .safe
        case .crashReports:      return .safe
        case .userCaches:        return .moderate
        case .projectBuildFiles: return .moderate
        case .xcodeSimulators:   return .caution
        case .xcodeArchives:     return .caution
        case .iosBackups:        return .caution
        case .timeMachineSnaps:  return .moderate
        }
    }

    var riskLabel: String? {
        switch safetyRisk {
        case .safe:     return nil
        case .moderate: return "Review items"
        case .caution:  return "Careful"
        }
    }

    var icon: String {
        switch self {
        case .xcodeDerivedData:  return "hammer.fill"
        case .xcodeArchives:     return "archivebox.fill"
        case .xcodeSimulators:   return "ipad.and.iphone"
        case .gradleCaches:      return "ant.fill" // Android/Gradle
        case .npmCache:          return "n.circle.fill"
        case .cocoaPodsCache:    return "c.circle.fill"
        case .flutterPubCache:   return "f.circle.fill"
        case .projectBuildFiles: return "folder.badge.minus"
        case .userCaches:        return "clock.arrow.circlepath"
        case .userLogs:          return "doc.text.fill"
        case .iosBackups:        return "iphone"
        case .crashReports:      return "exclamationmark.triangle.fill"
        case .timeMachineSnaps:  return "camera.on.rectangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .xcodeDerivedData:  return .blue
        case .xcodeArchives:     return .purple
        case .xcodeSimulators:   return .indigo
        case .gradleCaches:      return .green
        case .npmCache:          return .red
        case .cocoaPodsCache:    return .orange
        case .flutterPubCache:   return .blue
        case .projectBuildFiles: return .teal
        case .userCaches:        return .orange
        case .userLogs:          return .gray
        case .iosBackups:        return Color(red: 0.15, green: 0.6, blue: 0.95)
        case .crashReports:      return .red
        case .timeMachineSnaps:  return Color(red: 0.4, green: 0.8, blue: 0.6)
        }
    }
}

// MARK: - Storage Category Model

struct StorageCategory: Identifiable {
    let id = UUID()
    let type: StorageCategoryType
    /// Cleanable items discovered during scan
    var cleanableItems: [URL] = []
    /// For tmutil snapshots: date strings rather than URLs
    var snapshotDates: [String] = []
    var sizeInBytes: Int64 = 0
    var isScanning: Bool = false
    var isCheckedForClean: Bool = false

    var formattedSize: String {
        ByteCountFormatter.formatted(sizeInBytes)
    }
}
