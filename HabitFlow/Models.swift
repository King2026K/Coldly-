import Foundation
import SwiftData

/// A reusable daily routine. Dated instances live in `PlanBlock` so moving today's
/// routine never changes the habit's default time.
@Model
final class Habit {
    var id: UUID
    var title: String
    var durationMinutes: Int
    var preferredHour: Int
    var flexibilityMinutes: Int
    var reschedulePolicyRaw: String
    var createdAt: Date
    var isArchived: Bool

    init(
        title: String,
        durationMinutes: Int = 30,
        preferredHour: Int = 9,
        flexibilityMinutes: Int = 60,
        reschedulePolicy: ReschedulePolicy = .alwaysAsk
    ) {
        self.id = UUID()
        self.title = title
        self.durationMinutes = durationMinutes
        self.preferredHour = preferredHour
        self.flexibilityMinutes = flexibilityMinutes
        self.reschedulePolicyRaw = reschedulePolicy.rawValue
        self.createdAt = .now
        self.isArchived = false
    }

    var reschedulePolicy: ReschedulePolicy {
        get { ReschedulePolicy(rawValue: reschedulePolicyRaw) ?? .alwaysAsk }
        set { reschedulePolicyRaw = newValue.rawValue }
    }
}

enum ReschedulePolicy: String, CaseIterable, Identifiable {
    case alwaysAsk = "Always Ask"
    case autoMoveFlexible = "Auto-Move Flexible Blocks"
    case manualOnly = "Manual Only"

    var id: String { rawValue }
}

/// One scheduled instance of a habit on a particular date.
@Model
final class PlanBlock {
    var id: UUID
    var habitID: UUID
    var scheduledAt: Date
    var isCompleted: Bool
    var completedAt: Date?
    var wasMoved: Bool

    init(habitID: UUID, scheduledAt: Date) {
        self.id = UUID()
        self.habitID = habitID
        self.scheduledAt = scheduledAt
        self.isCompleted = false
        self.completedAt = nil
        self.wasMoved = false
    }
}

/// A single daily wellbeing check-in, updated in place if the user checks in again.
@Model
final class DailyCheckIn {
    var id: UUID
    var day: Date
    var energy: Int
    var mood: Int
    var note: String
    var updatedAt: Date

    init(day: Date, energy: Int, mood: Int, note: String = "") {
        self.id = UUID()
        self.day = Calendar.current.startOfDay(for: day)
        self.energy = energy
        self.mood = mood
        self.note = note
        self.updatedAt = .now
    }
}
