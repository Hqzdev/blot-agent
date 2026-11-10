import Foundation

struct MacAgentNameGenerator {
    private var suggestedNames: Set<String> = []

    mutating func next(language: String, excluding names: [String]) -> String {
        let unavailable = suggestedNames.union(names.map(Self.normalized))
        let baseNames = Self.names.map { language == "ru" ? $0.russian : $0.english }
        var suffix = 1

        while true {
            let candidates = baseNames.map { suffix == 1 ? $0 : "\($0) \(suffix)" }
                .filter { !unavailable.contains(Self.normalized($0)) }
            if let name = candidates.randomElement() {
                suggestedNames.insert(Self.normalized(name))
                return name
            }
            suffix += 1
        }
    }

    private nonisolated static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let names: [(russian: String, english: String)] = [
        ("Астра", "Astra"), ("Атлас", "Atlas"), ("Аврора", "Aurora"), ("Блик", "Glimmer"),
        ("Бриз", "Breeze"), ("Вега", "Vega"), ("Вектор", "Vector"), ("Гелиос", "Helios"),
        ("Дзен", "Zen"), ("Зефир", "Zephyr"), ("Искра", "Spark"), ("Кедр", "Cedar"),
        ("Киви", "Kiwi"), ("Клевер", "Clover"), ("Космо", "Cosmo"), ("Лира", "Lyra"),
        ("Лотос", "Lotus"), ("Луна", "Luna"), ("Люмен", "Lumen"), ("Манго", "Mango"),
        ("Маяк", "Beacon"), ("Метеор", "Meteor"), ("Мира", "Mira"), ("Мох", "Moss"),
        ("Неон", "Neon"), ("Нимб", "Nimbus"), ("Нова", "Nova"), ("Оникс", "Onyx"),
        ("Орион", "Orion"), ("Орбита", "Orbit"), ("Пиксель", "Pixel"), ("Плутон", "Pluto"),
        ("Пульс", "Pulse"), ("Риф", "Reef"), ("Рубин", "Ruby"), ("Сириус", "Sirius"),
        ("Скаут", "Scout"), ("Сокол", "Falcon"), ("Туман", "Mist"), ("Феникс", "Phoenix"),
        ("Флинт", "Flint"), ("Хвоя", "Pine"), ("Цитрус", "Citrus"), ("Шафран", "Saffron"),
        ("Эхо", "Echo"), ("Юки", "Yuki"), ("Янтарь", "Amber"), ("Ясень", "Ash")
    ]
}
