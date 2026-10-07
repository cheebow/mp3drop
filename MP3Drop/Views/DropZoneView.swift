import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    @Environment(ConversionViewModel.self) private var viewModel
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Drop WAV / AIFF files or folders here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)
        }
        .frame(height: 140)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .accessibilityElement()
        .accessibilityLabel("Drop zone. Drop WAV or AIFF files, or folders containing them, to convert them to MP3.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            viewModel.presentOpenPanel()
        }
        .onTapGesture {
            viewModel.presentOpenPanel()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let urlProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !urlProviders.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in urlProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                viewModel.addFiles(urls)
            }
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }
}
