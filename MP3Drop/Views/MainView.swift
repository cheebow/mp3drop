import SwiftUI

struct MainView: View {
    @Environment(ConversionViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        VStack(alignment: .leading, spacing: 16) {
            DropZoneView()

            if !viewModel.jobs.isEmpty {
                jobList
            }

            statusArea

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Picker("Quality", selection: $viewModel.preset) {
                    ForEach(EncodingPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.radioGroup)
                .help(viewModel.preset.detail)

                Picker("Output", selection: outputModeBinding) {
                    Text("Same Folder").tag(OutputMode.sameFolder)
                    Text(customFolderLabel).tag(OutputMode.customFolder)
                }
                .pickerStyle(.radioGroup)

                Toggle("Show in Finder when finished", isOn: $viewModel.revealInFinder)
            }
        }
        .padding(20)
        .frame(width: 420)
        .frame(minHeight: 420)
    }

    // Shows the whole current batch without scrolling, up to 8 rows.
    private var jobList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(viewModel.jobs) { job in
                    ConversionRowView(job: job)
                }
            }
        }
        .frame(height: min(CGFloat(viewModel.jobs.count), 8) * ConversionRowView.rowHeight)
    }

    @ViewBuilder
    private var statusArea: some View {
        if viewModel.isConverting {
            HStack {
                if let summary = viewModel.progressSummary {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    viewModel.cancel()
                }
            }
        } else if let result = viewModel.lastBatchResult {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conversion Complete")
                        .font(.headline)
                    Text("\(result.convertedCount) files converted")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !result.outputURLs.isEmpty {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(result.outputURLs)
                    }
                }
                Button("Clear") {
                    viewModel.clearFinished()
                }
            }
        } else {
            HStack {
                Spacer()
                Button("Open Files...") {
                    viewModel.presentOpenPanel()
                }
            }
        }
    }

    private var customFolderLabel: String {
        if let url = viewModel.outputFolderURL {
            String(localized: "Folder: \(url.lastPathComponent)")
        } else {
            String(localized: "Choose Folder...")
        }
    }

    private var outputModeBinding: Binding<OutputMode> {
        Binding {
            viewModel.outputMode
        } set: { newValue in
            if newValue == .customFolder {
                viewModel.chooseOutputFolder()
            } else {
                viewModel.outputMode = .sameFolder
            }
        }
    }
}

#Preview {
    MainView()
        .environment(ConversionViewModel())
}
