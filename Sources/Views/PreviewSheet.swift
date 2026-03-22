import SwiftUI

// MARK: - Preview Item

struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let categoryName: String
    let categoryColor: Color
    var sizeInBytes: Int64
    var isSelected: Bool = true

    var name: String { url.lastPathComponent }
    var parentPath: String { url.deletingLastPathComponent().path }
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
    var icon: String { isDirectory ? "folder.fill" : "doc.fill" }

    var formattedSize: String {
        ByteCountFormatter.formatted(sizeInBytes)
    }
}

// MARK: - PreviewSheet

struct PreviewSheet: View {
    @Binding var items: [PreviewItem]
    var onConfirmClean: ([PreviewItem]) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var sortOrder: SortOrder = .size
    @State private var filterText = ""

    enum SortOrder: String, CaseIterable {
        case size = "Size"
        case name = "Name"
        case category = "Category"
    }

    var filteredItems: [PreviewItem] {
        let base = filterText.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(filterText) ||
            $0.categoryName.localizedCaseInsensitiveContains(filterText)
        }
        switch sortOrder {
        case .size:     return base.sorted { $0.sizeInBytes > $1.sizeInBytes }
        case .name:     return base.sorted { $0.name < $1.name }
        case .category: return base.sorted { $0.categoryName < $1.categoryName }
        }
    }

    var selectedCount: Int  { items.filter { $0.isSelected }.count }
    var selectedBytes: Int64 { items.filter { $0.isSelected }.map { $0.sizeInBytes }.reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Preview Files to Clean")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("\(items.count) items • Deselect anything you want to keep")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(8)
            }
            .padding(20)

            Divider()

            // Toolbar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Filter by name or category…", text: $filterText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)

                Picker("Sort", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button(action: toggleAll) {
                    Text(selectedCount == items.count ? "Deselect All" : "Select All")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(7)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            // File List
            List {
                ForEach(filteredItems) { item in
                    PreviewRowView(item: item, isSelected: binding(for: item.id))
                }
            }
            .listStyle(.plain)

            Divider()

            // Footer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedCount) of \(items.count) items selected")
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(ByteCountFormatter.formatted(selectedBytes)) will be cleaned")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    let selected = items.filter { $0.isSelected }
                    dismiss()
                    onConfirmClean(selected)
                }) {
                    Label("Clean \(selectedCount) Items", systemImage: "trash.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .background(
                    LinearGradient(gradient: Gradient(colors: [.purple, .blue]),
                                   startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(10)
                .disabled(selectedCount == 0)
                .opacity(selectedCount == 0 ? 0.5 : 1.0)
            }
            .padding(20)
        }
        .frame(width: 740, height: 540)
    }

    // Helper to toggle all visible items
    private func toggleAll() {
        let allSelected = selectedCount == items.count
        for index in items.indices {
            items[index].isSelected = !allSelected
        }
    }

    // Binding into the `items` array by ID
    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { items.first(where: { $0.id == id })?.isSelected ?? false },
            set: { newValue in
                if let idx = items.firstIndex(where: { $0.id == id }) {
                    items[idx].isSelected = newValue
                }
            }
        )
    }
}

// MARK: - Preview Row

struct PreviewRowView: View {
    let item: PreviewItem
    @Binding var isSelected: Bool
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isSelected ? item.categoryColor : .secondary)
                .font(.system(size: 16))
                .onTapGesture { isSelected.toggle() }

            // File icon
            Image(systemName: item.icon)
                .foregroundColor(item.categoryColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(item.parentPath)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Category Tag
            Text(item.categoryName)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(item.categoryColor.opacity(0.12))
                .foregroundColor(item.categoryColor)
                .clipShape(Capsule())

            // Size
            Text(item.formattedSize)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovering ? Color.primary.opacity(0.04) : .clear)
        .cornerRadius(6)
        .onHover { isHovering = $0 }
        .opacity(isSelected ? 1.0 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
    }
}
