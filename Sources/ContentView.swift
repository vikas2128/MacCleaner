import SwiftUI

// MARK: - Root View

struct ContentView: View {
    @StateObject private var storageManager = StorageManager()

    var body: some View {
        NavigationView {
            SidebarView(manager: storageManager)
            DashboardView(manager: storageManager)
        }
        .navigationTitle("MacCleaner")
        .frame(minWidth: 960, minHeight: 640)
        .sheet(isPresented: $storageManager.showPreview) {
            PreviewSheet(items: $storageManager.previewItems) { selectedItems in
                storageManager.cleanConfirmed(selectedItems: selectedItems)
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @ObservedObject var manager: StorageManager

    var body: some View {
        VStack(spacing: 0) {
            List {
                // Developer Section
                categorySection(group: .developer)
                // General Section
                categorySection(group: .general)
                // System Data Section
                systemDataSection()
            }
            .listStyle(.sidebar)

            Divider()

            // Footer stats
            VStack(alignment: .leading, spacing: 6) {
                if manager.totalCleanedSize > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Freed \(ByteCountFormatter.formatted(manager.totalCleanedSize))")
                            .font(.caption.weight(.medium)).foregroundColor(.green)
                    }
                }
                if let err = manager.lastError {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text(err).font(.caption).foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
        }
        .frame(minWidth: 290)
    }

    @ViewBuilder
    func categorySection(group: CategoryGroup) -> some View {
        let indices = manager.categories.indices.filter { manager.categories[$0].type.group == group }
        Section(header: groupHeader(group)) {
            ForEach(indices, id: \.self) { idx in
                CategoryRowView(category: $manager.categories[idx])
            }
        }
    }

    @ViewBuilder
    func systemDataSection() -> some View {
        let indices = manager.categories.indices.filter { manager.categories[$0].type.group == .systemData }
        Section(header: groupHeader(.systemData)) {
            ForEach(indices, id: \.self) { idx in
                CategoryRowView(category: $manager.categories[idx])
            }

            // Tip row
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue.opacity(0.7))
                    .font(.caption)
                Text("Time Machine snapshots need admin permission to delete.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    func groupHeader(_ group: CategoryGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: groupIcon(group))
                .font(.caption.weight(.semibold))
            Text(group.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
        }
        .foregroundColor(.secondary)
        .padding(.top, 4)
    }

    func groupIcon(_ group: CategoryGroup) -> String {
        switch group {
        case .developer:  return "hammer"
        case .general:    return "folder"
        case .systemData: return "externaldrive"
        }
    }
}

// MARK: - Category Row

struct CategoryRowView: View {
    @Binding var category: StorageCategory
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(category.type.color.opacity(0.15)).frame(width: 34, height: 34)
                Image(systemName: category.type.icon)
                    .foregroundColor(category.type.color)
                    .font(.system(size: 14, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(category.type.rawValue)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    if let risk = category.type.riskLabel {
                        Text(risk)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(riskBadgeColor.opacity(0.15))
                            .foregroundColor(riskBadgeColor)
                            .clipShape(Capsule())
                    }
                }
                if category.isScanning {
                    Text("Calculating…").font(.caption).foregroundColor(.secondary)
                } else {
                    Text(category.sizeInBytes > 0 ? category.formattedSize : "Nothing to clean")
                        .font(.caption)
                        .foregroundColor(category.sizeInBytes > 0 ? .primary : .secondary)
                }
            }

            Spacer()

            if category.isScanning {
                ProgressView().controlSize(.small)
            } else if category.sizeInBytes > 0 {
                Toggle("", isOn: $category.isCheckedForClean)
                    .labelsHidden().toggleStyle(.checkbox)
            }
        }
        .padding(.vertical, 5)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .cornerRadius(6)
        .onHover { isHovering = $0 }
    }

    var riskBadgeColor: Color {
        switch category.type.safetyRisk {
        case .safe:     return .green
        case .moderate: return .orange
        case .caution:  return .red
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var manager: StorageManager
    @State private var rotation: Double = 0

    var totalSelectedSize: Int64 {
        manager.categories.filter { $0.isCheckedForClean }.map { $0.sizeInBytes }.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Ring
            ZStack {
                Circle().stroke(Color.gray.opacity(0.12), lineWidth: 24).frame(width: 260, height: 260)

                if manager.isScanning || manager.isCleaning {
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(
                            AngularGradient(gradient: Gradient(colors: [.blue, .purple, .blue]), center: .center),
                            style: StrokeStyle(lineWidth: 24, lineCap: .round)
                        )
                        .frame(width: 260, height: 260)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                } else {
                    let ratio = manager.totalScannedSize > 0
                        ? Double(totalSelectedSize) / Double(manager.totalScannedSize) : 0
                    Circle()
                        .trim(from: 0, to: CGFloat(min(max(ratio, 0.005), 1.0)))
                        .stroke(
                            LinearGradient(gradient: Gradient(colors: [.purple, .blue]),
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 24, lineCap: .round)
                        )
                        .frame(width: 260, height: 260)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: ratio)
                }

                VStack(spacing: 8) {
                    if manager.isScanning {
                        Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundColor(.blue)
                        Text("Scanning…").font(.system(size: 18, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                    } else if manager.isCleaning {
                        Image(systemName: "sparkles").font(.system(size: 32)).foregroundColor(.purple)
                        Text("Cleaning…").font(.system(size: 18, weight: .medium, design: .rounded)).foregroundColor(.secondary)
                    } else {
                        Text(ByteCountFormatter.formatted(totalSelectedSize))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .foregroundColor(.primary).lineLimit(1).minimumScaleFactor(0.5)
                        Text("of \(ByteCountFormatter.formatted(manager.totalScannedSize)) found")
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                    }
                }
                .frame(width: 190, height: 190)
            }
            .padding(.bottom, 40)

            // Risk Legend
            if !manager.isScanning && !manager.isCleaning {
                HStack(spacing: 18) {
                    legendItem(.green, "Safe")
                    legendItem(.orange, "Review")
                    legendItem(.red, "Careful")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.bottom, 28)
            }

            // Buttons
            HStack(spacing: 20) {
                Button(action: { rotation = 0; manager.startScan() }) {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(width: 130, height: 42)
                }
                .buttonStyle(.plain)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(11)
                .disabled(manager.isScanning || manager.isCleaning)

                // "Preview & Clean" — opens PreviewSheet
                Button(action: { rotation = 0; manager.requestCleanWithPreview() }) {
                    Label("Preview & Clean", systemImage: "eye.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .frame(width: 170, height: 42)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .background(
                    LinearGradient(gradient: Gradient(colors: [.purple, .blue]),
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(11)
                .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
                .disabled(manager.isScanning || manager.isCleaning || totalSelectedSize == 0)
                .opacity((manager.isScanning || manager.isCleaning || totalSelectedSize == 0) ? 0.5 : 1.0)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { manager.startScan() }
    }

    func legendItem(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }
}

// MARK: - ByteCountFormatter helper

extension ByteCountFormatter {
    static func formatted(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useAll]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
