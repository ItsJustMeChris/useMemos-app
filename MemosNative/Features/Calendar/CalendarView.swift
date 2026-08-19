import Observation
import SwiftUI

struct CalendarView: View {
    let store: MemoStore
    @State private var model: CalendarMemoModel
    @Environment(\.dismiss) private var dismiss

    init(store: MemoStore) {
        self.store = store
        _model = State(initialValue: CalendarMemoModel(store: store))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.warmBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        calendarCard
                        selectedDaySection
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .refreshable { await model.loadMonth() }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await model.loadMonth() }
            .alert("Calendar unavailable", isPresented: errorBinding) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "Please try again.")
            }
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 16) {
            HStack {
                Button {
                    Task { await model.moveMonth(by: -1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Previous month")

                Spacer()
                Text(model.monthTitle)
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()

                Button {
                    Task { await model.moveMonth(by: 1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Next month")
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(model.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(model.gridDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        CalendarDayButton(
                            date: date,
                            count: model.memoCount(on: date),
                            isSelected: model.isSelected(date),
                            isToday: Calendar.autoupdatingCurrent.isDateInToday(date)
                        ) {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                model.select(date)
                            }
                        }
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }

            HStack(spacing: 7) {
                Circle().fill(AppTheme.tint.opacity(0.18)).frame(width: 8, height: 8)
                Text("A filled day has one or more memos")
                Spacer()
                if model.isLoading { ProgressView().controlSize(.small) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .roundedCard()
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.title3.bold())
                    Text(model.selectedDate.formatted(date: .long, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.selectedMemos.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if model.isLoading && model.monthMemos.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 34)
            } else if model.selectedMemos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No memos on this day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .roundedCard()
            } else {
                ForEach(model.selectedMemos) { memo in
                    MemoCard(memo: memo, store: store)
                }
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

private struct CalendarDayButton: View {
    let date: Date
    let count: Int
    let isSelected: Bool
    let isToday: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                if isToday && !isSelected {
                    Circle()
                        .stroke(AppTheme.tint, lineWidth: 1.5)
                }
                Text(date.formatted(.dateTime.day()))
                    .font(.subheadline.weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : count > 0 ? AppTheme.tint : .primary)
            }
            .frame(width: 38, height: 38)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected { return AppTheme.tint }
        if count > 0 { return AppTheme.tint.opacity(min(0.12 + Double(count) * 0.06, 0.32)) }
        return .clear
    }

    private var accessibilityText: String {
        let dateText = date.formatted(date: .long, time: .omitted)
        if count == 0 { return dateText }
        return "\(dateText), \(count) memo\(count == 1 ? "" : "s")"
    }
}

@MainActor
@Observable
private final class CalendarMemoModel {
    private let store: MemoStore
    private let calendar = Calendar.autoupdatingCurrent

    var displayedMonth: Date
    var selectedDate: Date
    var monthMemos: [Memo] = []
    private var memoBuckets: [Date: [Memo]] = [:]
    var isLoading = false
    var errorMessage: String?
    private var loadGeneration = 0

    init(store: MemoStore) {
        self.store = store
        let now = Date.now
        self.displayedMonth = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: now)?.start ?? now
        self.selectedDate = Calendar.autoupdatingCurrent.startOfDay(for: now)
    }

    var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    var selectedMemos: [Memo] {
        memoBuckets[calendar.startOfDay(for: selectedDate)] ?? []
    }

    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = max(0, min(symbols.count - 1, calendar.firstWeekday - 1))
        return Array(symbols[start...] + symbols[..<start])
    }

    var gridDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let dayRange = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var days = Array<Date?>(repeating: nil, count: leading)
        for offset in 0..<dayRange.count {
            days.append(calendar.date(byAdding: .day, value: offset, to: interval.start))
        }
        while !days.count.isMultiple(of: 7) { days.append(nil) }
        return days
    }

    func memoCount(on date: Date) -> Int {
        memoBuckets[calendar.startOfDay(for: date)]?.count ?? 0
    }

    func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }

    func moveMonth(by offset: Int) async {
        guard let next = calendar.date(byAdding: .month, value: offset, to: displayedMonth),
              let interval = calendar.dateInterval(of: .month, for: next) else { return }
        displayedMonth = interval.start
        selectedDate = calendar.isDate(Date.now, equalTo: interval.start, toGranularity: .month)
            ? calendar.startOfDay(for: .now)
            : interval.start
        await loadMonth()
    }

    func loadMonth() async {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return }
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            if generation == loadGeneration { isLoading = false }
        }
        do {
            let memos = try await store.memos(from: interval.start, to: interval.end)
            guard generation == loadGeneration else { return }
            monthMemos = memos
            memoBuckets = Dictionary(grouping: memos) { calendar.startOfDay(for: $0.createTime) }
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            if Task.isCancelled || (error as? APIError)?.isCancellation == true { return }
            errorMessage = error.localizedDescription
        }
    }
}
