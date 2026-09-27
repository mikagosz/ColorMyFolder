import SwiftUI

/// The small window opened from Finder: saved colour dots, a colour picker, and "restore".
struct PickerView: View {
    let folders: [URL]
    @State var palette: [RGB]
    @State private var custom: Color = .pink

    let onPick: (RGB) -> Void
    let onSave: (RGB) -> Void
    let onForget: (RGB) -> Void
    let onRestore: () -> Void

    private var title: String {
        folders.count == 1 ? folders[0].lastPathComponent : String(localized: "Folders: \(folders.count)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline).lineLimit(1).truncationMode(.middle)

            if palette.isEmpty {
                Text("No saved colors yet — pick a color below and click “Save Dot”.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 308, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 10), count: 8), alignment: .leading, spacing: 10) {
                    ForEach(palette, id: \.self) { rgb in
                        Button { onPick(rgb) } label: {
                            Circle().fill(Color(nsColor: rgb.color))
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Color Folder")
                        .contextMenu {
                            Button("Delete Dot") {
                                onForget(rgb)
                                palette.removeAll { $0 == rgb }
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                ColorPicker("Other Color", selection: $custom, supportsOpacity: false)
                Spacer()
                Button("Save Dot") {
                    guard let rgb = RGB(NSColor(custom)) else { return }
                    onSave(rgb)
                    if !palette.contains(rgb) { palette.append(rgb) }
                }
                Button("Color Folder") {
                    guard let rgb = RGB(NSColor(custom)) else { return }
                    onPick(rgb)
                }
                .keyboardShortcut(.defaultAction)
            }
            // Never truncate the labels (Polish “Inny kolor” did at 340 pt) — the window grows instead.
            .fixedSize()

            HStack {
                Button("Restore System Look", role: .destructive) { onRestore() }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 340, alignment: .leading)
    }
}
