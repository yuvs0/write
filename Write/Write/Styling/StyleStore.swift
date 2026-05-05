import Foundation

@Observable
final class StyleStore {
    private static let storageKey = "com.yuvrajsethia.write.styleConfiguration"
    private let defaults: UserDefaults

    var configuration: StyleConfiguration {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(StyleConfiguration.self, from: data) {
            self.configuration = stored
        } else {
            self.configuration = .default
        }
    }

    func resetToDefaults() {
        configuration = .default
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
