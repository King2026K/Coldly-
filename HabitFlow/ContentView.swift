import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            HabitsView()
                .tabItem { Label("Habits", systemImage: "leaf") }
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
        }
        .tint(Color.accentColor)
    }
}

private enum HabitFlowStyle {
    static let background = LinearGradient(
        colors: [Color(uiColor: .systemGroupedBackground), Color.accentColor.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

private struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlanBlock.scheduledAt) private var allBlocks: [PlanBlock]
    @Query private var habits: [Habit]
    @Query private var checkIns: [DailyCheckIn]
    @StateObject private var calendarPlanner = CalendarPlanner()
    @State private var showingCheckIn = false

    private var todayBlocks: [PlanBlock] {
        allBlocks.filter { Calendar.current.isDateInToday($0.scheduledAt) }
    }
    private var todaysCheckIn: DailyCheckIn? {
        checkIns.first { Calendar.current.isDateInToday($0.day) }
    }
    private var habitByID: [UUID: Habit] { Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) }) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    greeting
                    checkInCard
                    calendarCard
                    planSection
                }
                .padding()
            }
            .background(HabitFlowStyle.background.ignoresSafeArea())
            .navigationTitle("Today")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { showingCheckIn = true } label: { Image(systemName: "face.smiling") }
                    .accessibilityLabel("Daily check-in")
            }}
            .sheet(isPresented: $showingCheckIn) { CheckInView() }
            .task {
                createTodaysBlocksIfNeeded()
                await calendarPlanner.refresh()
                applyAutomaticMoves()
            }
            .refreshable {
                await calendarPlanner.refresh()
                applyAutomaticMoves()
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Make room for what matters.")
                .font(.title2.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private var checkInCard: some View {
        Button { showingCheckIn = true } label: {
            HStack(spacing: 14) {
                Image(systemName: todaysCheckIn == nil ? "sparkles" : "checkmark.circle.fill")
                    .font(.title2).foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44).background(Color.accentColor.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(todaysCheckIn == nil ? "How are you feeling?" : "Check-in saved")
                        .font(.headline).foregroundStyle(.primary)
                    Text(todaysCheckIn.map { "Energy \($0.energy)/5 · Mood \($0.mood)/5 · Tap to update" } ?? "Take a moment to check in with yourself.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(16).background(HabitFlowStyle.card, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var calendarCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar").font(.title3).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(calendarPlanner.isAuthorized ? "Your calendar" : "Plan around your day")
                    .font(.headline)
                Text(calendarPlanner.statusMessage).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(calendarPlanner.isAuthorized ? "Refresh" : "Connect") {
                Task {
                    await calendarPlanner.refresh()
                    applyAutomaticMoves()
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(14).background(HabitFlowStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's plan").font(.title3.weight(.semibold))
                Spacer()
                Text("\(todayBlocks.filter(\.isCompleted).count)/\(todayBlocks.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            if todayBlocks.isEmpty {
                ContentUnavailableView("A fresh start", systemImage: "leaf", description: Text("Add a habit to begin shaping your day."))
                    .frame(minHeight: 180)
            } else {
                ForEach(todayBlocks) { block in
                    if let habit = habitByID[block.habitID], !habit.isArchived {
                        PlanBlockCard(
                            block: block,
                            habit: habit,
                            conflict: calendarPlanner.conflict(for: block, habit: habit),
                            suggestion: calendarPlanner.conflict(for: block, habit: habit).flatMap {
                                calendarPlanner.suggestedStart(after: $0, for: habit, block: block)
                            },
                            onMove: { date in
                                block.scheduledAt = date
                                block.wasMoved = true
                            }
                        )
                    }
                }
            }
        }
    }

    private func createTodaysBlocksIfNeeded() {
        let today = Calendar.current.startOfDay(for: .now)
        for habit in habits where !habit.isArchived {
            let exists = allBlocks.contains { $0.habitID == habit.id && Calendar.current.isDate($0.scheduledAt, inSameDayAs: today) }
            guard !exists else { continue }
            var components = Calendar.current.dateComponents([.year, .month, .day], from: today)
            components.hour = habit.preferredHour
            components.minute = 0
            if let date = Calendar.current.date(from: components) {
                modelContext.insert(PlanBlock(habitID: habit.id, scheduledAt: date))
            }
        }
    }

    private func applyAutomaticMoves() {
        for block in todayBlocks {
            guard let habit = habitByID[block.habitID],
                  habit.reschedulePolicy == .autoMoveFlexible,
                  let event = calendarPlanner.conflict(for: block, habit: habit),
                  let suggestion = calendarPlanner.suggestedStart(after: event, for: habit, block: block) else { continue }
            block.scheduledAt = suggestion
            block.wasMoved = true
        }
    }
}

private struct PlanBlockCard: View {
    @Bindable var block: PlanBlock
    let habit: Habit
    let conflict: CalendarEventSummary?
    let suggestion: Date?
    let onMove: (Date) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                block.isCompleted.toggle()
                block.completedAt = block.isCompleted ? .now : nil
            } label: {
                Image(systemName: block.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(block.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(block.isCompleted ? "Mark \(habit.title) incomplete" : "Complete \(habit.title)")
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(habit.title).font(.headline).strikethrough(block.isCompleted)
                    Spacer(minLength: 4)
                    Text(block.scheduledAt.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text("\(habit.durationMinutes) min · \(habit.reschedulePolicy.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
                if block.wasMoved {
                    Label("Adjusted around your schedule", systemImage: "arrow.right.circle")
                        .font(.caption).foregroundStyle(Color.accentColor)
                }
                if let conflict {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Overlaps \(conflict.title)", systemImage: "exclamationmark.circle")
                            .font(.caption.weight(.medium)).foregroundStyle(.orange)
                        if habit.reschedulePolicy == .alwaysAsk, let suggestion {
                            Button("Move to \(suggestion.formatted(date: .omitted, time: .shortened))") { onMove(suggestion) }
                                .font(.caption.weight(.semibold)).buttonStyle(.bordered).controlSize(.mini)
                        } else if habit.reschedulePolicy == .manualOnly {
                            Text("Manual Only: no changes made.").font(.caption).foregroundStyle(.secondary)
                        } else if suggestion == nil {
                            Text("No available time within this habit's flexibility window.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(15).background(HabitFlowStyle.card, in: RoundedRectangle(cornerRadius: 18))
        .opacity(block.isCompleted ? 0.72 : 1)
    }
}

private struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @State private var showingAddHabit = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(habits.filter { !$0.isArchived }) { habit in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(habit.title).font(.headline)
                        Text("\(habit.durationMinutes) min · around \(hourText(habit.preferredHour)) · \(habit.reschedulePolicy.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .swipeActions {
                        Button("Archive", systemImage: "archivebox") { habit.isArchived = true }
                            .tint(.orange)
                    }
                }
                if habits.allSatisfy(\.isArchived) {
                    ContentUnavailableView("No habits yet", systemImage: "leaf", description: Text("Add a routine that matters to you."))
                }
            }
            .scrollContentBackground(.hidden)
            .background(HabitFlowStyle.background)
            .navigationTitle("Habits")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddHabit = true } label: { Label("Add", systemImage: "plus") }
            }}
            .sheet(isPresented: $showingAddHabit) { HabitFormView() }
        }
    }

    private func hourText(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00"
    }
}

private struct HabitFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var title = ""
    @State private var duration = 30
    @State private var preferredHour = 9
    @State private var flexibility = 60
    @State private var policy: ReschedulePolicy = .alwaysAsk

    var body: some View {
        NavigationStack {
            Form {
                Section("Routine") {
                    TextField("Habit name", text: $title)
                    Stepper("Duration: \(duration) minutes", value: $duration, in: 5...180, step: 5)
                    Picker("Preferred time", selection: $preferredHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00").tag(hour)
                        }
                    }
                }
                Section {
                    Stepper("Flexibility: \(flexibility) minutes", value: $flexibility, in: 0...240, step: 15)
                    Picker("When plans conflict", selection: $policy) {
                        ForEach(ReschedulePolicy.allCases) { Text($0.rawValue).tag($0) }
                    }
                } header: { Text("Scheduling") }
                Section(footer: Text("HabitFlow only reads calendar events when you choose to connect your calendar. It never edits your calendar.")) {
                    Label("Your routine stays yours", systemImage: "hand.raised")
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        modelContext.insert(Habit(title: title.trimmingCharacters(in: .whitespacesAndNewlines), durationMinutes: duration, preferredHour: preferredHour, flexibilityMinutes: flexibility, reschedulePolicy: policy))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct CheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var checkIns: [DailyCheckIn]
    @State private var energy = 3.0
    @State private var mood = 3.0
    @State private var note = ""

    private var existing: DailyCheckIn? { checkIns.first { Calendar.current.isDateInToday($0.day) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("A quick check-in") {
                    ratingRow(title: "Energy", value: $energy, low: "Low", high: "High", symbol: "bolt.fill")
                    ratingRow(title: "Mood", value: $mood, low: "Rough", high: "Good", symbol: "face.smiling")
                }
                Section("Anything to note?") {
                    TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Text("A small check-in can help you notice which routines support your wellbeing over time.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Daily Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let existing {
                            existing.energy = Int(energy.rounded())
                            existing.mood = Int(mood.rounded())
                            existing.note = note
                            existing.updatedAt = .now
                        } else {
                            modelContext.insert(DailyCheckIn(day: .now, energy: Int(energy.rounded()), mood: Int(mood.rounded()), note: note))
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let existing {
                    energy = Double(existing.energy)
                    mood = Double(existing.mood)
                    note = existing.note
                }
            }
        }
    }

    private func ratingRow(title: String, value: Binding<Double>, low: String, high: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(title) · \(Int(value.wrappedValue))/5", systemImage: symbol).font(.headline)
            Slider(value: value, in: 1...5, step: 1)
            HStack { Text(low); Spacer(); Text(high) }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct InsightsView: View {
    @Query private var blocks: [PlanBlock]
    @Query(sort: \DailyCheckIn.day, order: .reverse) private var checkIns: [DailyCheckIn]

    private var recentChecks: [DailyCheckIn] { Array(checkIns.filter { $0.day >= Calendar.current.date(byAdding: .day, value: -6, to: .now)! }.prefix(7)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Small steps add up.").font(.title2.weight(.semibold))
                    metricCard(title: "Habits completed", value: "\(blocks.filter(\.isCompleted).count)", detail: "All-time completed plan blocks", icon: "checkmark.circle")
                    metricCard(title: "Check-ins", value: "\(recentChecks.count)", detail: "In the last 7 days", icon: "sparkles")
                    if !recentChecks.isEmpty {
                        metricCard(title: "Average energy", value: String(format: "%.1f / 5", Double(recentChecks.map(\.energy).reduce(0, +)) / Double(recentChecks.count)), detail: "Across your recent check-ins", icon: "bolt")
                        metricCard(title: "Average mood", value: String(format: "%.1f / 5", Double(recentChecks.map(\.mood).reduce(0, +)) / Double(recentChecks.count)), detail: "Across your recent check-ins", icon: "face.smiling")
                    } else {
                        ContentUnavailableView("Your insights start here", systemImage: "chart.bar.xaxis", description: Text("Complete a check-in to begin spotting patterns."))
                    }
                }
                .padding()
            }
            .background(HabitFlowStyle.background.ignoresSafeArea())
            .navigationTitle("Insights")
        }
    }

    private func metricCard(title: String, value: String, detail: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 42, height: 42).background(Color.accentColor.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value).font(.title2.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(HabitFlowStyle.card, in: RoundedRectangle(cornerRadius: 18))
    }
}
