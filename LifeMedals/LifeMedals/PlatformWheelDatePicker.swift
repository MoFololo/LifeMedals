import SwiftUI

enum TaskDeadlinePreset: String, CaseIterable, Hashable, Codable, Sendable {
    case today
    case tomorrow
    case thisWeekend = "this_weekend"

    var title: String {
        switch self {
        case .today: "今天"
        case .tomorrow: "明天"
        case .thisWeekend: "这周末"
        }
    }
}

/// A deliberately small deadline selector. The task screen owns the calendar
/// calculation and turns the selected preset into 23:59 on the target day.
struct DeadlinePresetWheelPicker: View {
    @Binding var selection: TaskDeadlinePreset?

    var body: some View {
        ZStack {
            PixelCornerShape(step: 3)
                .fill(PixelTheme.paperRaised)
                .frame(height: 44)
                .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.selection, lineWidth: 2) }
                .allowsHitTesting(false)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(TaskDeadlinePreset.allCases, id: \.self) { preset in
                        Text(preset.title)
                            .font(.body.weight(selection == preset ? .semibold : .regular))
                            .foregroundStyle(selection == preset ? PixelTheme.ink : PixelTheme.inkMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .id(preset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $selection, anchor: .center)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollIndicators(.hidden)
            .contentMargins(.vertical, 50, for: .scrollContent)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.24),
                        .init(color: .black, location: 0.76),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(height: 144)
        .background(PixelTheme.paper.opacity(0.72), in: PixelCornerShape())
        .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("截止日期")
        .accessibilityValue(selection?.title ?? "未选择")
    }
}
