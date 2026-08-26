import SwiftUI

enum TaskDeadlinePreset: String, CaseIterable, Hashable, Codable, Sendable {
    case today
    case tomorrow
    case thisWeekend = "this_weekend"

    var title: String {
        switch self {
        case .today: L10n.text("今天", english: "Today")
        case .tomorrow: L10n.text("明天", english: "Tomorrow")
        case .thisWeekend: L10n.text("这周末", english: "This Weekend")
        }
    }
}

/// A deliberately small deadline selector. The task screen owns the calendar
/// calculation and turns the selected preset into 23:59 on the target day.
struct DeadlinePresetWheelPicker: View {
    @Environment(\.locale) private var locale
    @Binding var selection: TaskDeadlinePreset?
    @State private var scrollPosition: TaskDeadlinePreset?

    init(selection: Binding<TaskDeadlinePreset?>) {
        _selection = selection
        _scrollPosition = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        let _ = locale.identifier
        ZStack {
            PixelCornerShape(step: 3)
                .fill(PixelTheme.paperRaised)
                .frame(height: 44)
                .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.selection, lineWidth: 2) }
                .allowsHitTesting(false)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(TaskDeadlinePreset.allCases, id: \.self) { preset in
                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(PixelTheme.font(.caption, weight: .bold))
                                .opacity(0)
                            Text(preset.title)
                            Image(systemName: "checkmark")
                                .font(PixelTheme.font(.caption, weight: .bold))
                                .opacity(selection == preset ? 1 : 0)
                            Spacer()
                        }
                            .font(PixelTheme.font(.body, weight: selection == preset ? .semibold : .regular))
                            .foregroundStyle(selection == preset ? PixelTheme.ink : PixelTheme.inkMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                commitSelection(preset)
                            }
                            .id(preset)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: $scrollPosition, anchor: .center)
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
            .onChange(of: scrollPosition) { _, preset in
                guard let preset, preset != selection else { return }
                selection = preset
            }
            .onChange(of: selection) { _, preset in
                guard preset != scrollPosition else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    scrollPosition = preset
                }
            }
            .onAppear {
                scrollPosition = selection
            }
        }
        .frame(height: 144)
        .background(PixelTheme.paper.opacity(0.72), in: PixelCornerShape())
        .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("截止日期")
        .accessibilityValue(selection?.title ?? L10n.text("未选择", english: "Not Selected"))
    }

    private func commitSelection(_ preset: TaskDeadlinePreset) {
        selection = preset
        withAnimation(.snappy(duration: 0.2)) {
            scrollPosition = preset
        }
    }
}
