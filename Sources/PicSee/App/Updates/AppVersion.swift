import Foundation

struct AppVersion: Comparable, Equatable {
    let displayString: String
    private let components: [Int]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let parsedComponents = normalized.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !parsedComponents.isEmpty else { return nil }

        var numericComponents: [Int] = []
        for component in parsedComponents {
            guard !component.isEmpty, let number = Int(component), number >= 0 else {
                return nil
            }
            numericComponents.append(number)
        }

        self.displayString = normalized
        self.components = AppVersion.trimTrailingZeroes(from: numericComponents)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let componentCount = max(lhs.components.count, rhs.components.count)
        for index in 0..<componentCount {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components == rhs.components
    }

    private static func trimTrailingZeroes(from components: [Int]) -> [Int] {
        var trimmed = components
        while trimmed.last == 0, trimmed.count > 1 {
            trimmed.removeLast()
        }
        return trimmed
    }
}
