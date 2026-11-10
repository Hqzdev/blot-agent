import Foundation

/// One bilingual catalog serves native SwiftUI labels and runtime UI messages.
enum WorkspaceCopy {
    static func text(_ source: String, language: String) -> String {
        catalogs[language]?.text(source) ?? source
    }

    private static let catalogs: [String: Catalog] = {
        Dictionary(uniqueKeysWithValues: ["en", "ru"].compactMap { language in
            guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Localizable.strings")),
                  let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else { return nil }
            return (language, Catalog(values: values))
        })
    }()

    private struct Catalog {
        let values: [String: String]
        let templates: [WorkspaceCopyTemplate]

        init(values: [String: String]) {
            self.values = values
            self.templates = values.sorted { $0.key.count > $1.key.count }.compactMap { source, target in
                source == target ? nil : WorkspaceCopyTemplate(source: source, translation: target)
            }
        }

        func text(_ source: String) -> String {
            if let translated = values[source] { return translated }
            return templates.lazy.compactMap { $0.translate(source) }.first ?? source
        }
    }
}
