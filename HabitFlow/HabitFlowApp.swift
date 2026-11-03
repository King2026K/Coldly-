import SwiftData
import SwiftUI

@main
struct HabitFlowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Habit.self, PlanBlock.self, DailyCheckIn.self])
    }
}
