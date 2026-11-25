import CAMRCore
import Foundation

/// Personal identifiers masked in what CAMR hands to AI programs (D-126). It sits beside `Secrets`: secrets are keys,
/// tokens and passwords, taken out of kept sessions always; these are the people a lawyer's case file or a clinic's
/// visit note is about, masked only in a vault whose `privacy.mask` setting is on.
///
/// Each value becomes a placeholder numbered in order of first appearance in one response, the same value always the
/// same placeholder within it: `[PERSON-1]`, `[ID-1]`, `[PIN-1]`, `[PHONE-1]`, `[EMAIL-1]`. A model can still tell who
/// is who without seeing the real value. Placeholders never span a line, so every line number stays where it was, and
/// the paths a response cites are kept as they are, so a citation still points at the right file and line. The files
/// on disk are never changed.
public struct PrivacyMask: Sendable {
    /// Each person: the names they go by, longest first. From `people.txt` in the vault's store, one person a line,
    /// other names for the same person after a `|`: `Grace Akinyi Otieno | Grace Otieno | Mrs Otieno`.
    public let people: [[String]]

    public init(people: [[String]]) {
        self.people = people.map { names in names.sorted { $0.count > $1.count } }.filter { !$0.isEmpty }
    }

    /// The vault's people file: inside its store, so it is never indexed and never handed out itself.
    public static func peopleFile(_ vault: Vault) -> URL { vault.store.appendingPathComponent("people.txt") }

    /// The mask for a vault whose `privacy.mask` is on; nil when it is off, which it is unless set.
    public static func forVault(_ vault: Vault) -> PrivacyMask? {
        guard vault.config.privacyMask else { return nil }
        let text = (try? String(contentsOf: peopleFile(vault), encoding: .utf8)) ?? ""
        return PrivacyMask(people: people(in: text))
    }

    /// One person a line, names split on `|`; blank lines and lines starting `#` are skipped. A name needs two letters.
    public static func people(in text: String) -> [[String]] {
        text.components(separatedBy: .newlines).compactMap { line in
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty, !clean.hasPrefix("#") else { return nil }
            let names = clean.split(separator: "|").map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                .filter { $0.filter(\.isLetter).count >= 2 }
            return names.isEmpty ? nil : names
        }
    }

    private enum Kind: String { case person = "PERSON", id = "ID", pin = "PIN", phone = "PHONE", email = "EMAIL" }

    private static func rule(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

    /// An email address, before names, so a name inside one goes with the address.
    private static let email = rule(#"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}(?![A-Za-z0-9-])"#)
    /// A Kenyan national ID number: 7 or 8 digits right after "ID", "ID No.", "National ID number", "I.D." and the
    /// like. Only the digits are replaced; seven or eight digits with no such label are left alone (a fee, a count).
    private static let id = rule(#"(?i)(?<![A-Za-z])((?:national[ \t]+)?(?:id|i\.d\.)(?:[ \t]*(?:card[ \t]*)?(?:no\b\.?|number|num\b\.?|#))?[ \t:.*#=/-]{0,6})(\d{7,8})(?!\d)"#)
    /// A KRA PIN: A or P, nine digits, a letter.
    private static let pin = rule(#"(?<![A-Za-z0-9])[AP]\d{9}[A-Z](?![A-Za-z0-9])"#)
    /// A Kenyan mobile or landline-style mobile number: +254 / 254 / 0, then 7xx or 1xx and six more digits, written
    /// together or in groups split by a space or a dash. Never across a line. Not when it is joined to a letter, digit
    /// or dash on either side: SHA-0112-450981 is an insurance number, not a phone (found on the demo clinic vault).
    private static let phone = rule(#"(?<![\w+-])(?:\+254|254|0)[ -]?([17]\d{2})[ -]?(\d{3})[ -]?(\d{3})(?![\w]|-\d)"#)

    /// The text with every listed name, ID number, KRA PIN, phone number and email address replaced. Strings in
    /// `keeping` (the paths a response cites) are left exactly as they are, wherever they appear.
    public func masked(_ text: String, keeping: [String] = []) -> String {
        // The kept strings are swapped for markers no rule matches, then put back.
        let kept = Array(Set(keeping.filter { !$0.isEmpty })).sorted { $0.count > $1.count }
        var work = text
        var markers: [(String, String)] = []
        for value in kept {
            let escaped = value.replacingOccurrences(of: "/", with: "\\/")
            for form in Set([value, escaped]) where work.contains(form) {
                let marker = "\u{E000}\(markers.count)\u{E001}"
                markers.append((marker, form))
                work = work.replacingOccurrences(of: form, with: marker)
            }
        }
        var numbers: [Kind: [String: Int]] = [:]
        func placeholder(_ kind: Kind, _ key: String) -> String {
            var seen = numbers[kind, default: [:]]
            let number = seen[key] ?? (seen.count + 1)
            seen[key] = number
            numbers[kind] = seen
            return "[\(kind.rawValue)-\(number)]"
        }
        work = replace(Self.email, in: work) { match, text in placeholder(.email, text.substring(with: match.range).lowercased()) }
        if let names = namesRule() {
            work = replace(names.rule, in: work) { match, text in
                let found = text.substring(with: match.range).split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
                return placeholder(.person, String(names.person[found] ?? 0))
            }
        }
        work = replace(Self.id, in: work) { match, text in
            text.substring(with: match.range(at: 1)) + placeholder(.id, text.substring(with: match.range(at: 2)))
        }
        work = replace(Self.pin, in: work) { match, text in placeholder(.pin, text.substring(with: match.range)) }
        work = replace(Self.phone, in: work) { match, text in
            // 0722 418 905, 0722-418-905 and +254722418905 are one number, so one placeholder.
            placeholder(.phone, (1...3).map { text.substring(with: match.range(at: $0)) }.joined())
        }
        for (marker, form) in markers.reversed() { work = work.replacingOccurrences(of: marker, with: form) }
        return work
    }

    /// One rule for every listed name, longest first, whole words only, any case, any run of spaces between words.
    private func namesRule() -> (rule: NSRegularExpression, person: [String: Int])? {
        var person: [String: Int] = [:]
        var all: [String] = []
        for (index, names) in people.enumerated() {
            for name in names {
                let key = name.lowercased()
                // A name listed for two people stays with the first: it is masked either way.
                if person[key] == nil { person[key] = index; all.append(name) }
            }
        }
        guard !all.isEmpty else { return nil }
        let alternatives = all.sorted { $0.count > $1.count }.map { name in
            name.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"[ \t]+"#)
        }
        let pattern = #"(?i)(?<![\p{L}\p{N}])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}])"#
        guard let rule = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (rule, person)
    }

    private func replace(_ rule: NSRegularExpression, in text: String, with make: (NSTextCheckingResult, NSString) -> String) -> String {
        let source = text as NSString
        let matches = rule.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return text }
        let out = NSMutableString()
        var at = 0
        for match in matches {
            out.append(source.substring(with: NSRange(location: at, length: match.range.location - at)))
            out.append(make(match, source))
            at = match.range.location + match.range.length
        }
        out.append(source.substring(from: at))
        return out as String
    }
}

extension ToolResult {
    /// This result with its text masked, its cited paths kept as they are (D-126).
    func masked(by mask: PrivacyMask?) -> ToolResult {
        guard let mask else { return self }
        var copy = self
        copy.text = mask.masked(text, keeping: sources.map(\.path))
        copy.summary = mask.masked(summary, keeping: sources.map(\.path))
        return copy
    }
}
