//
//  InputRules.swift
//  MeasureGo
//
//  Input filtering/validation shared by the new-project form and the
//  details screen. Zip: digits only. Phone: digits with an optional
//  leading "+". Email: standard pattern check.
//

import Foundation

/// Pure validation helpers — used from binding setters that are not
/// main-actor isolated, so opt out of the project's default isolation.
nonisolated enum InputRules {

    static let zipMaxLength = 10
    static let phoneMaxDigits = 15 // E.164

    /// Keeps only digits, capped at `zipMaxLength`.
    static func filterZip(_ input: String) -> String {
        String(input.filter(\.isWholeNumber).prefix(zipMaxLength))
    }

    /// Keeps digits and a "+" only in the leading position, e.g. "+15551234567".
    static func filterPhone(_ input: String) -> String {
        let hasPlus = input.hasPrefix("+")
        let digits = String(input.filter(\.isWholeNumber).prefix(phoneMaxDigits))
        return (hasPlus ? "+" : "") + digits
    }

    static func isValidEmail(_ input: String) -> Bool {
        let pattern = /^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        return input.wholeMatch(of: pattern) != nil
    }
}
