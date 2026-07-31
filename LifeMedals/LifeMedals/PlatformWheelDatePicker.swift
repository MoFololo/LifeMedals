import SwiftUI

/// Uses Apple's wheel date picker where it exists and an equivalent scrolling
/// wheel on macOS, where `WheelDatePickerStyle` is explicitly unavailable.
struct PlatformWheelDatePicker: View {
    @Binding var selection: Date

    var body: some View {
#if os(iOS)
        DatePicker("Select Date", selection: $selection)
            .datePickerStyle(.wheel)
#else
        MacWheelDatePicker(selection: $selection)
#endif
    }
}

#if os(macOS)
private struct MacWheelDatePicker: View {
    @Binding var selection: Date

    private let calendar = Calendar.current
    private let dayOffsets = Array(-365...730)
    private let hours = Array(0..<24)
    private let minutes = Array(0..<60)

    @State private var anchorDay: Date
    @State private var selectedDayOffset: Int?
    @State private var selectedHour: Int?
    @State private var selectedMinute: Int?

    init(selection: Binding<Date>) {
        _selection = selection

        let calendar = Calendar.current
        let value = selection.wrappedValue
        _anchorDay = State(initialValue: calendar.startOfDay(for: value))
        _selectedDayOffset = State(initialValue: 0)
        _selectedHour = State(initialValue: calendar.component(.hour, from: value))
        _selectedMinute = State(initialValue: calendar.component(.minute, from: value))
    }

    var body: some View {
        HStack(spacing: 8) {
            wheelColumn(values: dayOffsets, selection: $selectedDayOffset) { offset in
                Text(date(for: offset).formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(minWidth: 150)

            wheelColumn(values: hours, selection: $selectedHour) { hour in
                Text(String(format: "%02d", hour))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 58)

            Text(":")
                .font(.headline)
                .foregroundStyle(.secondary)

            wheelColumn(values: minutes, selection: $selectedMinute) { minute in
                Text(String(format: "%02d", minute))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .frame(width: 58)
        }
        .padding(.horizontal, 10)
        .onChange(of: selectedDayOffset) { _, _ in updateSelection() }
        .onChange(of: selectedHour) { _, _ in updateSelection() }
        .onChange(of: selectedMinute) { _, _ in updateSelection() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("截止时间")
        .accessibilityValue(selection.formatted(date: .long, time: .shortened))
    }

    private func wheelColumn<Value: Hashable, Row: View>(
        values: [Value],
        selection: Binding<Value?>,
        @ViewBuilder row: @escaping (Value) -> Row
    ) -> some View {
        ZStack {
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        row(value)
                            .font(.body.weight(selection.wrappedValue == value ? .semibold : .regular))
                            .foregroundStyle(selection.wrappedValue == value ? .primary : .secondary)
                            .frame(height: 36)
                            .id(value)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollPosition(id: selection, anchor: .center)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollIndicators(.hidden)
            .contentMargins(.vertical, 54, for: .scrollContent)
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

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.48))
                .frame(height: 36)
                .allowsHitTesting(false)
        }
        .frame(height: 144)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func date(for offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: anchorDay) ?? anchorDay
    }

    private func updateSelection() {
        guard
            let selectedDayOffset,
            let selectedHour,
            let selectedMinute,
            let updated = calendar.date(
                bySettingHour: selectedHour,
                minute: selectedMinute,
                second: 0,
                of: date(for: selectedDayOffset)
            )
        else { return }

        selection = updated
    }
}
#endif
