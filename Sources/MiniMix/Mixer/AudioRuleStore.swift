import Foundation

protocol AudioRuleStoring {
    func loadRules() -> [String: AudioAppRule]
    func saveRule(_ rule: AudioAppRule)
    func removeRule(for bundleIdentifier: String)
}

final class UserDefaultsAudioRuleStore: AudioRuleStoring {
    private let defaults: UserDefaults
    private let key = "MiniMix.audioRules.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadRules() -> [String: AudioAppRule] {
        guard let data = defaults.data(forKey: key) else {
            return [:]
        }

        do {
            let rules = try JSONDecoder().decode([AudioAppRule].self, from: data)
            return Dictionary(uniqueKeysWithValues: rules.map { ($0.bundleIdentifier, $0) })
        } catch {
            return [:]
        }
    }

    func saveRule(_ rule: AudioAppRule) {
        var rules = loadRules()
        rules[rule.bundleIdentifier] = rule
        save(Array(rules.values))
    }

    func removeRule(for bundleIdentifier: String) {
        var rules = loadRules()
        rules.removeValue(forKey: bundleIdentifier)
        save(Array(rules.values))
    }

    private func save(_ rules: [AudioAppRule]) {
        guard let data = try? JSONEncoder().encode(rules.sorted(by: { $0.bundleIdentifier < $1.bundleIdentifier })) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
