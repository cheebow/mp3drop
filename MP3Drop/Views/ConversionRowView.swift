import SwiftUI

struct ConversionRowView: View {
    static let rowHeight: CGFloat = 44

    let job: ConversionJob

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.fileName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                switch job.status {
                case .queued:
                    Text("Waiting...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .encoding(let progress):
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                case .done:
                    Text("Done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                case .cancelled:
                    Text("Cancelled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .skipped:
                    Text("Skipped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch job.status {
        case .queued: "clock"
        case .encoding: "waveform"
        case .done: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled, .skipped: "minus.circle"
        }
    }

    private var iconColor: Color {
        switch job.status {
        case .done: .green
        case .failed: .red
        default: .secondary
        }
    }
}
