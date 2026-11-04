import Foundation

struct MacDemoScheduler {
    var calendar = Calendar.current
    private let dayNames = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

    func isDue(_ routine: MacDemoRoutine, at date: Date) -> Bool {
        guard routine.enabled, allowedDay(routine, date: date), let time = timeParts(routine.time) else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard parts.minute == time.minute,
            routine.frequency == "Каждый час" || parts.hour == time.hour
        else { return false }
        if let last = routine.lastRun, calendar.isDate(last, equalTo: date, toGranularity: .minute) { return false }
        return true
    }

    func nextRun(_ routine: MacDemoRoutine, after date: Date) -> Date? {
        guard routine.enabled, let time = timeParts(routine.time) else { return nil }
        if routine.frequency == "Каждый час" {
            return calendar.nextDate(
                after: date, matching: DateComponents(minute: time.minute, second: 0), matchingPolicy: .nextTime)
        }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date), allowedDay(routine, date: day),
                let candidate = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                candidate > date
            else { continue }
            return candidate
        }
        return nil
    }

    func validTime(_ value: String) -> Bool { timeParts(value) != nil }

    private func timeParts(_ value: String) -> (hour: Int, minute: Int)? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (hour, minute)
    }

    private func allowedDay(_ routine: MacDemoRoutine, date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        switch routine.frequency {
        case "Каждый день", "Каждый час": return true
        case "По пятницам": return weekday == 6
        default: return routine.weekdays.contains(dayNames[weekday - 1])
        }
    }
}
