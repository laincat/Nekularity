import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NekularityWidgets: WidgetBundle {
    var body: some Widget {
        DownloadLiveActivity()
    }
}

/// A chapter being saved, on the Lock Screen and in the Dynamic Island.
///
/// The island is small and the rules for it are strict: the compact ends are a glance,
/// the minimal one is a glyph, and only the expanded view has room for a title. Getting
/// that wrong shows as text cut in half rather than as an error, so the layout here is
/// deliberately three different answers rather than one view squeezed three ways.
struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivity.self) { context in
            // Lock Screen and the banner.
            HStack(spacing: 14) {
                ring(context.state)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.comicTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(context.attributes.shortChapter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(context.state.compact)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(context.state.failure == nil ? .primary : .red)
            }
            .padding(14)
            .activityBackgroundTint(.clear)
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ring(context.state)
                        .frame(width: 30, height: 30)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.compact)
                        .font(.callout.monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.attributes.comicTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.attributes.shortChapter)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ProgressView(value: context.state.fraction)
                            .tint(context.state.failure == nil ? .accentColor : .red)
                        Text(context.state.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                // A ring, not a number: at this size digits are unreadable and the
                // ring answers the only question the compact form is asked.
                ring(context.state)
                    .frame(width: 18, height: 18)
                    .padding(.leading, 2)
            } compactTrailing: {
                Text(context.state.compact)
                    .font(.caption2.monospacedDigit())
                    .padding(.trailing, 2)
            } minimal: {
                ring(context.state)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(context.state.failure == nil ? .accentColor : .red)
        }
    }

    private func ring(_ state: DownloadActivity.ContentState) -> some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, state.fraction))
                .stroke(state.failure == nil ? Color.accentColor : Color.red,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if state.isFinished {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            }
        }
    }
}
