import SwiftUI

struct TimeEntryListView: View {
    @EnvironmentObject private var authService: AuthService

    @State private var entries: [TimeEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLogTime = false

    @State private var viewMode: ViewMode = .week
    @State private var currentWeekStart: Date = Self.mondayOfWeek(containing: Date())
    @State private var currentMonth: Date = Self.firstOfMonth(containing: Date())

    // Month mode: entries for the entire displayed month
    @State private var monthEntries: [TimeEntry] = []
    @State private var isLoadingMonth = false

    private let navy = Color("NavyBlue")
    private let gold = Color("BrandGold")
    private let goldDark = Color("GoldDark")

    private enum ViewMode: String, CaseIterable {
        case week = "Week"
        case month = "Month"
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // View mode toggle
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Group {
                switch viewMode {
                case .week:
                    weekView
                case .month:
                    monthView
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Time Entries")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(navy, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingLogTime = true
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .sheet(isPresented: $showingLogTime) {
            NavigationStack {
                LogTimeView {
                    Task {
                        if viewMode == .week {
                            await fetchWeekEntries()
                        } else {
                            await fetchMonthEntries()
                        }
                    }
                }
            }
        }
        .task(id: currentWeekStart) {
            if viewMode == .week {
                await fetchWeekEntries()
            }
        }
        .onChange(of: viewMode) {
            if viewMode == .month {
                Task { await fetchMonthEntries() }
            }
        }
    }

    // MARK: - Week View

    private var weekView: some View {
        VStack(spacing: 0) {
            weekNavigationBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            if isLoading && entries.isEmpty {
                loadingView
            } else if let errorMessage, entries.isEmpty {
                errorView(errorMessage) { await fetchWeekEntries() }
            } else {
                weekContent
            }
        }
    }

    private var weekNavigationBar: some View {
        HStack {
            Button {
                withAnimation {
                    currentWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(gold)
            }

            Spacer()

            Text(weekLabel)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                withAnimation {
                    currentWeekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart)!
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(gold)
            }
            .disabled(isCurrentWeek)
        }
        .padding(.horizontal, 8)
    }

    private var weekContent: some View {
        List {
            // Summary card
            weekSummaryCard
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            if entries.isEmpty {
                ContentUnavailableView {
                    Label("No Time Entries", systemImage: "clock")
                } description: {
                    Text("No time has been logged this week.")
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(groupedByDate, id: \.date) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            TimeEntryRow(entry: entry)
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(Color("CardBackground"))
                                        .padding(.vertical, 4)
                                )
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                    } header: {
                        Text(group.displayDate)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await fetchWeekEntries() }
    }

    private var weekSummaryCard: some View {
        let totalUnits = entries.reduce(0) { $0 + $1.units }
        let totalMinutes = totalUnits * 15
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Week Total")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Text("\(totalUnits) units (\(hrs) hrs \(mins) min)")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
            }

            Spacer()

            Image(systemName: "clock.fill")
                .font(.title2)
                .foregroundColor(gold)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Month View

    private var monthView: some View {
        VStack(spacing: 0) {
            monthNavigationBar
                .padding(.horizontal)
                .padding(.vertical, 8)

            if isLoadingMonth && monthEntries.isEmpty {
                loadingView
            } else {
                monthContent
            }
        }
    }

    private var monthNavigationBar: some View {
        HStack {
            Button {
                withAnimation {
                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth)!
                }
                Task { await fetchMonthEntries() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundColor(gold)
            }

            Spacer()

            Text(monthLabel)
                .font(.subheadline.weight(.semibold))

            Spacer()

            Button {
                withAnimation {
                    currentMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth)!
                }
                Task { await fetchMonthEntries() }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundColor(gold)
            }
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 8)
    }

    private var monthContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Monthly total
                monthSummaryCard
                    .padding(.horizontal)

                // Calendar grid
                calendarGrid
                    .padding(.horizontal)
            }
            .padding(.vertical, 8)
        }
        .refreshable { await fetchMonthEntries() }
    }

    private var monthSummaryCard: some View {
        let totalUnits = monthEntries.reduce(0) { $0 + $1.units }
        let totalMinutes = totalUnits * 15
        let hrs = totalMinutes / 60
        let mins = totalMinutes % 60

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Month Total")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)

                Text("\(totalUnits) units (\(hrs) hrs \(mins) min)")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
            }

            Spacer()

            Image(systemName: "calendar")
                .font(.title2)
                .foregroundColor(gold)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    private var calendarGrid: some View {
        let calendar = Calendar.current
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)!
        // Monday = 2 in Calendar; adjust so Monday = 0
        let firstWeekday = (calendar.component(.weekday, from: currentMonth) + 5) % 7
        let totalCells = firstWeekday + daysInMonth.count

        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        let dayHeaders = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        return VStack(spacing: 4) {
            // Day headers
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(dayHeaders, id: \.self) { day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day cells
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<totalCells, id: \.self) { index in
                    if index < firstWeekday {
                        Color.clear
                            .frame(height: 52)
                    } else {
                        let day = index - firstWeekday + 1
                        let dateString = dayDateString(day: day)
                        let dayUnits = unitsForDate(dateString)

                        Button {
                            // Drill down: switch to week mode for this day's week
                            let dayDate = calendar.date(bySetting: .day, value: day, of: currentMonth)!
                            currentWeekStart = Self.mondayOfWeek(containing: dayDate)
                            withAnimation {
                                viewMode = .week
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text("\(day)")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)

                                if dayUnits > 0 {
                                    Text("\(dayUnits)u")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(goldDark)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(dayUnits > 0 ? gold.opacity(0.12) : Color("CardBackground"))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(dayUnits > 0 ? gold.opacity(0.3) : .clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color("CardBackground"))
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        )
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
                .tint(gold)
            Text("Loading time entries...")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorView(_ message: String, retry: @escaping () async -> Void) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer().frame(height: 100)

                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundColor(goldDark.opacity(0.6))

                Text("Connection Error")
                    .font(.title3.bold())

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    Task { await retry() }
                } label: {
                    Text("Try Again")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(gold)
                        .clipShape(Capsule())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .refreshable { await retry() }
    }

    // MARK: - Data

    private func fetchWeekEntries() async {
        isLoading = true
        errorMessage = nil

        do {
            let dateString = Self.dateFormatter.string(from: currentWeekStart)
            let fetched: [TimeEntry] = try await authService.authenticatedRequest(
                path: "/api/time/entries?weekStart=\(dateString)"
            )
            entries = fetched
        } catch APIError.unauthorized {
            // Already handled
        } catch {
            if entries.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    private func fetchMonthEntries() async {
        isLoadingMonth = true

        let calendar = Calendar.current
        let monthStart = currentMonth
        guard let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return }

        // Calculate the Monday of the week containing the 1st
        let firstMonday = Self.mondayOfWeek(containing: monthStart)

        // Calculate all week starts needed to cover the month
        var weekStarts: [Date] = []
        var cursor = firstMonday
        while cursor < monthEnd {
            weekStarts.append(cursor)
            cursor = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor)!
        }

        // Pre-format dates before entering the task group (avoids main actor isolation warning)
        let weekDateStrings = weekStarts.map { Self.dateFormatter.string(from: $0) }

        // Fetch all weeks in parallel
        var allEntries: [TimeEntry] = []
        await withTaskGroup(of: [TimeEntry].self) { group in
            for dateString in weekDateStrings {
                group.addTask {
                    do {
                        let fetched: [TimeEntry] = try await authService.authenticatedRequest(
                            path: "/api/time/entries?weekStart=\(dateString)"
                        )
                        return fetched
                    } catch {
                        return []
                    }
                }
            }
            for await weekEntries in group {
                allEntries.append(contentsOf: weekEntries)
            }
        }

        // Deduplicate by id and filter to only entries within the displayed month
        var seen = Set<String>()
        let yearMonth = Self.yearMonthFormatter.string(from: currentMonth)
        monthEntries = allEntries.filter { entry in
            guard entry.date.hasPrefix(yearMonth), seen.insert(entry.id).inserted else { return false }
            return true
        }

        isLoadingMonth = false
    }

    // MARK: - Helpers

    private var groupedByDate: [(date: String, displayDate: String, entries: [TimeEntry])] {
        let grouped = Dictionary(grouping: entries) { $0.date }
        return grouped.keys.sorted(by: >).map { date in
            let display = Self.displayDateFormatter.string(
                from: Self.dateFormatter.date(from: date) ?? Date()
            )
            return (date: date, displayDate: display, entries: grouped[date]!)
        }
    }

    private var weekLabel: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: currentWeekStart)!
        let startStr = Self.weekLabelFormatter.string(from: currentWeekStart)
        let endStr = Self.weekLabelFormatter.string(from: end)
        let year = Calendar.current.component(.year, from: currentWeekStart)
        return "\(startStr) – \(endStr) \(year)"
    }

    private var monthLabel: String {
        Self.monthLabelFormatter.string(from: currentMonth)
    }

    private var isCurrentWeek: Bool {
        currentWeekStart >= Self.mondayOfWeek(containing: Date())
    }

    private var isCurrentMonth: Bool {
        currentMonth >= Self.firstOfMonth(containing: Date())
    }

    private func dayDateString(day: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySetting: .day, value: day, of: currentMonth)!
        return Self.dateFormatter.string(from: date)
    }

    private func unitsForDate(_ dateString: String) -> Int {
        monthEntries.filter { $0.date == dateString }.reduce(0) { $0 + $1.units }
    }

    // MARK: - Date Utilities

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private static let yearMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    private static let weekLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.locale = Locale(identifier: "en_GB")
        return f
    }()

    /// Returns the Monday of the week containing the given date
    static func mondayOfWeek(containing date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components)!
    }

    /// Returns the 1st of the month containing the given date
    static func firstOfMonth(containing date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)!
    }
}

// MARK: - Time Entry Row

private struct TimeEntryRow: View {
    let entry: TimeEntry

    private let gold = Color("BrandGold")
    private let goldDark = Color("GoldDark")

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(entry.isClientWork ? gold.opacity(0.12) : Color.blue.opacity(0.1))
                    .frame(width: 38, height: 38)

                Image(systemName: entry.isClientWork ? "person.fill" : "briefcase.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(entry.isClientWork ? goldDark : .blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.workLabel)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(entry.durationText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !entry.serviceCode.isEmpty {
                        Text(entry.serviceCode)
                            .font(.caption2)
                            .foregroundColor(goldDark)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(goldDark.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                if !entry.notes.isEmpty {
                    Text(entry.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
