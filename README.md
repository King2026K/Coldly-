# HabitFlow

HabitFlow is a calm, local-first iOS planner and habit tracker for busy professionals and students. The MVP focuses on daily habits, energy and mood check-ins, and read-only calendar-aware planning.

## Build

Open `HabitFlow.xcodeproj` in Xcode 15 or later, select the HabitFlow scheme, and run on an iOS 17+ simulator or device. Calendar access is optional; the app remains usable if permission is denied.

## MVP behavior

- Create daily habits with a preferred start time, flexibility window, duration, and per-habit rescheduling policy.
- Complete or reopen today's plan blocks.
- Record one energy/mood check-in per day.
- Optionally read today's calendar events to identify conflicts. Calendar events are never created or modified.
- `Always Ask` presents a move suggestion, `Auto-Move Flexible Blocks` moves a block only within its flexibility window, and `Manual Only` leaves it untouched.
- Data is stored locally with SwiftData. Persistence is kept separate from UI so CloudKit sync can be considered later.

Location, weather, Screen Time, widgets, and Live Activities are intentionally not required by this MVP. They can be added as optional modules after validating the core planning experience.

## Privacy

HabitFlow does not require calendar access. If granted, calendar access is used to read events for today's conflict detection. No calendar data is written by the app. Habit and check-in data is stored locally on the device.
