import EventKit
import Foundation

struct CalendarEventSummary: Identifiable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
}

/// Read-only, opt-in calendar access. The planner requests permission only when
/// the user asks to check their calendar; it never creates or edits events.
@MainActor
final class CalendarPlanner: ObservableObject {
    @Published private(set) var events: [CalendarEventSummary] = []
    @Published private(set) var statusMessage = "Calendar is optional"
    @Published private(set) var isAuthorized = false

    private let store = EKEventStore()

    func refresh(for day: Date = .now) async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                isAuthorized = false
                statusMessage = "Calendar access is off. Your plan still works without it."
                events = []
                return
            }

            isAuthorized = true
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: day)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            events = store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .map {
                    CalendarEventSummary(
                        id: $0.eventIdentifier ?? UUID().uuidString,
                        title: $0.title?.isEmpty == false ? ($0.title ?? "Calendar event") : "Calendar event",
                        startDate: $0.startDate,
                        endDate: $0.endDate
                    )
                }
            statusMessage = events.isEmpty ? "No calendar events today" : "\(events.count) calendar event\(events.count == 1 ? "" : "s") today"
        } catch {
            isAuthorized = false
            events = []
            statusMessage = "Calendar unavailable. You can continue without it."
        }
    }

    func conflict(for block: PlanBlock, habit: Habit) -> CalendarEventSummary? {
        let blockEnd = block.scheduledAt.addingTimeInterval(TimeInterval(habit.durationMinutes * 60))
        return events.first { event in
            block.scheduledAt < event.endDate && blockEnd > event.startDate
        }
    }

    func suggestedStart(after event: CalendarEventSummary, for habit: Habit, block: PlanBlock) -> Date? {
        let suggestion = event.endDate.addingTimeInterval(5 * 60)
        let latestAllowed = habit.preferredHourDate(on: block.scheduledAt)
            .addingTimeInterval(TimeInterval(habit.flexibilityMinutes * 60))
        guard suggestion >= habit.preferredHourDate(on: block.scheduledAt), suggestion <= latestAllowed else {
            return nil
        }
        return suggestion
    }
}

private extension Habit {
    func preferredHourDate(on day: Date) -> Date {
        Calendar.current.date(
            bySettingHour: preferredHour,
            minute: 0,
            second: 0,
            of: Calendar.current.startOfDay(for: day)
        ) ?? day
    }
}
