import SwiftUI

struct SettingsView: View {
    @Environment(ConversionViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel

        Form {
            Section("General") {
                Picker("Default Quality", selection: $viewModel.preset) {
                    ForEach(EncodingPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }

                Picker("Output", selection: outputModeBinding) {
                    Text("Same Folder").tag(OutputMode.sameFolder)
                    Text(customFolderLabel).tag(OutputMode.customFolder)
                }
            }

            Section("After Conversion") {
                Toggle("Show in Finder", isOn: $viewModel.revealInFinder)
                Toggle("Play notification sound", isOn: $viewModel.playSound)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
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
