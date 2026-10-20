import Foundation

enum ScheduleMatcher {
    private static let skippedWords: Set<String> = ["по", "и", "на", "за", "в", "с", "от", "със"]

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func acronym(_ text: String) -> String {
        normalize(text.replacingOccurrences(of: "-", with: " "))
            .split(separator: " ")
            .filter { !skippedWords.contains(String($0)) }
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }

    static func similar(_ lhs: String?, _ rhs: String) -> Bool {
        guard let lhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        let a = normalize(lhs)
        let b = normalize(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b || a.contains(b) || b.contains(a) { return true }
        let acronymA = acronym(lhs)
        let acronymB = acronym(rhs)
        return acronymA.count > 1 && (acronymA == rhs.uppercased() || acronymB == lhs.uppercased() || acronymA == acronymB)
    }

    static func streamKey(_ text: String?) -> String? {
        guard let text else { return nil }
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? normalize(text) : String(Int(digits) ?? 0)
    }

    static func bestMatch(for student: Student, in items: [ScheduleItem]) -> ScheduleItem? {
        let candidates = items.filter { item in
            similar(student.faculty, item.faculty)
                && similar(student.specialty, item.major)
                && (student.course == nil || item.year == nil || item.year == student.course)
        }
        guard !candidates.isEmpty else { return nil }
        if let key = streamKey(student.stream), let exact = candidates.first(where: { streamKey($0.stream) == key }) {
            return exact
        }
        if let course = student.course {
            let sameYear = candidates.filter { $0.year == course }
            if sameYear.count == 1 { return sameYear[0] }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
