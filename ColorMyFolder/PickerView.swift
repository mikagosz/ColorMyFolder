import SwiftUI

/// The ColorMyFolder window: folders to color, saved colors, a color picker, "restore",
/// and a gear with the list location. Opened from Finder with folders, or from the app icon without.
struct PickerView: View {
    @State var folders: [URL]
    @State var palette: [RGB]
    @State var storePath: String
    @State private var custom: Color = .pink
    @State private var showSettings = false

    let onPick: ([URL], RGB) -> Void
    let onSave: (RGB) -> Void
    let onForget: (RGB) -> Void
    let onRestore: ([URL]) -> Void
    let onChooseFolders: () -> [URL]
    let onChangeStore: () -> String?

    private var title: String {
        switch folders.count {
        case 0: return String(localized: "No folder chosen")
        case 1: return folders[0].lastPathComponent
        default: return String(localized: "Folders: \(folders.count)")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The window's title bar carries the app name; this line says what gets colored.
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(folders.isEmpty ? .secondary : .primary)
                Spacer()
                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .popover(isPresented: $showSettings, arrowEdge: .bottom) { settings }
            }

            HStack(spacing: 10) {
                Button(folders.isEmpty ? "Choose Folders…" : "Choose Other Folders…") {
                    let chosen = onChooseFolders()
                    if !chosen.isEmpty { folders = chosen }
                }
                Button("Restore System Look", role: .destructive) { onRestore(folders) }
                    .disabled(folders.isEmpty)
            }
            .fixedSize()

            if palette.isEmpty {
                Text("No saved colors yet — pick a color below and click “Save Color”.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 308, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 10), count: 8), alignment: .leading, spacing: 10) {
                    ForEach(palette, id: \.self) { rgb in
                        Button { onPick(folders, rgb) } label: { Self.dot(rgb) }
                            .buttonStyle(.plain)
                            .disabled(folders.isEmpty)
                            .help("Color Folder")
                            .contextMenu {
                                Button("Delete Color") {
                                    onForget(rgb)
                                    palette.removeAll { $0 == rgb }
                                }
                            }
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button("Save Color") {
                    guard let rgb = RGB(NSColor(custom)) else { return }
                    onSave(rgb)
                    if !palette.contains(rgb) { palette.append(rgb) }
                }
                Button("Color Folder") {
                    guard let rgb = RGB(NSColor(custom)) else { return }
                    onPick(folders, rgb)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folders.isEmpty)
            }
            .fixedSize()

            ColorPicker("Other Color", selection: $custom, supportsOpacity: false)
                .fixedSize()
        }
        .padding(16)
        .frame(minWidth: 340, alignment: .leading)
    }

    @ViewBuilder
    private static func dot(_ rgb: RGB) -> some View {
        let shape = Circle()
        Group {
            if rgb.finish == Logic.chrome {
                shape.fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.55), Color(white: 0.9), Color(white: 0.5)],
                                          startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(Color(nsColor: rgb.color))
            }
        }
        .overlay(shape.strokeBorder(.primary.opacity(0.15)))
        .frame(width: 24, height: 24)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("List location").font(.headline)
            Text(storePath.isEmpty ? String(localized: "Not set") : storePath)
                .font(.callout).foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
            Button("Change…") {
                if let path = onChangeStore() {
                    storePath = path
                    showSettings = false
                }
            }
        }
        .padding(14)
    }
}
