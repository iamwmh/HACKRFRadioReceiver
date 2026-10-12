import Foundation

enum L10n {
    static func s(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: s(key), locale: .autoupdatingCurrent, arguments: args)
    }
}
