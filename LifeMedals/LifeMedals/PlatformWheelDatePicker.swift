import SwiftUI

/// Kept for decoding responses produced by older Worker deployments.
enum TaskDeadlinePreset: String, CaseIterable, Hashable, Codable, Sendable {
    case today
    case tomorrow
    case thisWeekend = "this_weekend"
}

enum DeadlineDateOptions {
    static func selectableDates(
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let firstDate = calendar.startOfDay(for: referenceDate)
        let lastDate = calendar.date(byAdding: .month, value: 1, to: firstDate) ?? firstDate
        let dayCount = calendar.dateComponents([.day], from: firstDate, to: lastDate).day ?? 0

        return (0...max(dayCount, 0)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDate)
        }
    }

    static func defaultSelection(
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        return deadline(on: tomorrow, calendar: calendar)
    }

    static func normalized(
        _ date: Date,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> Date {
        let dates = selectableDates(relativeTo: referenceDate, calendar: calendar)
        guard let firstDate = dates.first, let lastDate = dates.last else {
            return deadline(on: referenceDate, calendar: calendar)
        }

        let selectedDay = calendar.startOfDay(for: date)
        let clampedDay = min(max(selectedDay, firstDate), lastDate)
        return deadline(on: clampedDay, calendar: calendar)
    }

    static func deadline(on date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
    }

    static func relativeLabels(
        for date: Date,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [String] {
        let selectedDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: referenceDate)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let weekday = calendar.component(.weekday, from: today)
        let weekend = calendar.date(byAdding: .day, value: (8 - weekday) % 7, to: today) ?? today

        var labels: [String] = []
        if selectedDay == today {
            labels.append(L10n.text("今天", english: "Today"))
        }
        if selectedDay == tomorrow {
            labels.append(L10n.text("明天", english: "Tomorrow"))
        }
        if selectedDay == weekend {
            labels.append(L10n.text("这周末", english: "This Weekend"))
        }
        return labels
    }

    static func displayText(
        for date: Date,
        relativeTo referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let labels = relativeLabels(for: date, relativeTo: referenceDate, calendar: calendar)
        guard !labels.isEmpty else { return L10n.monthAndDay(date) }
        let joinedLabels = labels.joined(separator: " · ")
        return AppLanguage.current == .english
            ? "\(L10n.monthAndDay(date)) (\(joinedLabels))"
            : "\(L10n.monthAndDay(date))（\(joinedLabels)）"
    }
}

struct DeadlineWheelPicker: View {
    @Binding var selection: Date

    private let referenceDate: Date
    private let calendar: Calendar
    private let dates: [Date]

    @State private var scrollPosition: Date?

    init(
        selection: Binding<Date>,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) {
        _selection = selection
        self.referenceDate = referenceDate
        self.calendar = calendar
        dates = DeadlineDateOptions.selectableDates(relativeTo: referenceDate, calendar: calendar)
        _scrollPosition = State(
            initialValue: calendar.startOfDay(
                for: DeadlineDateOptions.normalized(
                    selection.wrappedValue,
                    relativeTo: referenceDate,
                    calendar: calendar
                )
            )
        )
    }

    var body: some View {
        ZStack {
            PixelCornerShape(step: 3)
                .fill(PixelTheme.paperRaised)
                .frame(height: 44)
                .overlay { PixelCornerShape(step: 3).stroke(PixelTheme.selection, lineWidth: 2) }
                .allowsHitTesting(false)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(dates, id: \.self) { date in
                        let isSelected = calendar.isDate(date, inSameDayAs: selection)

                        HStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "checkmark")
                                .font(PixelTheme.font(.caption, weight: .bold))
                                .opacity(0)
                            Text(
                                DeadlineDateOptions.displayText(
                                    for: date,
                                    relativeTo: referenceDate,
                                    calendar: calendar
                                )
                            )
                            Image(systemName: "checkmark")
                                .font(PixelTheme.font(.caption, weight: .bold))
                                .opacity(isSelected ? 1 : 0)
                            Spacer()
                        }
                        .font(PixelTheme.font(.body, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? PixelTheme.ink : PixelTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            commitSelection(date)
                        }
                        .id(date)
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
            .onChange(of: scrollPosition) { _, date in
                guard let date, !calendar.isDate(date, inSameDayAs: selection) else { return }
                selection = DeadlineDateOptions.deadline(on: date, calendar: calendar)
            }
            .onChange(of: selection) { _, date in
                let normalizedDay = calendar.startOfDay(
                    for: DeadlineDateOptions.normalized(
                        date,
                        relativeTo: referenceDate,
                        calendar: calendar
                    )
                )
                guard normalizedDay != scrollPosition else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    scrollPosition = normalizedDay
                }
            }
        }
        .frame(height: 144)
        .background(PixelTheme.paper.opacity(0.72), in: PixelCornerShape())
        .overlay { PixelCornerShape().stroke(PixelTheme.gold.opacity(0.62), lineWidth: 1) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("截止日期")
        .accessibilityValue(
            DeadlineDateOptions.displayText(
                for: selection,
                relativeTo: referenceDate,
                calendar: calendar
            )
        )
    }

    private func commitSelection(_ date: Date) {
        selection = DeadlineDateOptions.deadline(on: date, calendar: calendar)
        withAnimation(.snappy(duration: 0.2)) {
            scrollPosition = calendar.startOfDay(for: date)
        }
    }
}

struct DeadlinePickerField: View {
    @Binding private var selection: Date

    private let title: String?
    private let referenceDate: Date
    private let onCommit: ((Date) -> Void)?

    @State private var isExpanded = false
    @State private var draftSelection: Date

    init(
        title: String? = nil,
        selection: Binding<Date>,
        referenceDate: Date = .now,
        onCommit: ((Date) -> Void)? = nil
    ) {
        self.title = title
        _selection = selection
        self.referenceDate = referenceDate
        self.onCommit = onCommit
        _draftSelection = State(
            initialValue: DeadlineDateOptions.normalized(
                selection.wrappedValue,
                relativeTo: referenceDate
            )
        )
    }

    private var visibleSelection: Date {
        isExpanded && onCommit != nil ? draftSelection : selection
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                if !isExpanded {
                    draftSelection = DeadlineDateOptions.normalized(
                        selection,
                        relativeTo: referenceDate
                    )
                }
                withAnimation(.snappy(duration: 0.24)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 14) {
                    PixelSymbolTile(systemImage: "calendar.badge.clock", tint: PixelTheme.selection)

                    VStack(alignment: .leading, spacing: 4) {
                        if let title {
                            Text(LocalizedStringKey(title))
                                .font(PixelTheme.font(.caption, weight: .semibold))
                                .foregroundStyle(PixelTheme.inkMuted)
                        }
                        Text(
                            DeadlineDateOptions.displayText(
                                for: visibleSelection,
                                relativeTo: referenceDate
                            )
                        )
                        .font(PixelTheme.font(.subheadline, weight: .semibold))
                        .foregroundStyle(PixelTheme.ink)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(PixelTheme.font(.caption, weight: .bold))
                        .foregroundStyle(PixelTheme.inkMuted)
                }
                .padding(17)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pixelSurface(fill: PixelTheme.paper, border: PixelTheme.gold, step: 4, hasShadow: true)

            if isExpanded {
                DeadlineWheelPicker(
                    selection: onCommit == nil ? $selection : $draftSelection,
                    referenceDate: referenceDate
                )
                .transition(.opacity.combined(with: .move(edge: .top)))

                if let onCommit {
                    HStack(spacing: 10) {
                        Button("取消") {
                            draftSelection = selection
                            withAnimation(.snappy(duration: 0.2)) {
                                isExpanded = false
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(PixelTheme.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .pixelSurface(fill: PixelTheme.paperRaised, border: PixelTheme.gold, step: 2)

                        Button("保存") {
                            let normalized = DeadlineDateOptions.normalized(
                                draftSelection,
                                relativeTo: referenceDate
                            )
                            onCommit(normalized)
                            withAnimation(.snappy(duration: 0.2)) {
                                isExpanded = false
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .pixelSurface(fill: PixelTheme.selection, border: PixelTheme.gold, step: 2)
                    }
                }
            }
        }
        .onChange(of: selection) { _, date in
            guard !isExpanded else { return }
            draftSelection = DeadlineDateOptions.normalized(date, relativeTo: referenceDate)
        }
    }
}
