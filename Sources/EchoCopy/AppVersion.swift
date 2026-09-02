import Foundation

struct AppVersion: Comparable, Equatable {
    private let components: [Int]

    init?(_ rawValue: String) {
        var normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }

        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        var parsed = parts.compactMap { Int($0) }
        guard parsed.count == parts.count else { return nil }

        while parsed.count > 1 && parsed.last == 0 {
            parsed.removeLast()
        }
        components = parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum UpdateVersionPolicy {
    static func updateAvailable(latest: String, current: String) -> Bool {
        guard let latestVersion = AppVersion(latest),
              let currentVersion = AppVersion(current) else {
            return false
        }
        return latestVersion > currentVersion
    }
}
