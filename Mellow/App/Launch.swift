import Foundation

/// Аргументы запуска — только для снимков экранов в CI.
/// -seedDemo — примеры в памяти; -screen <имя> — открыть экран; -anchor <id> — прокрутить к блоку;
/// -tod <morn|day|eve|night> — время суток фона; -step <after|done> — шаг практики.
enum Launch {
    static let args: [String] = ProcessInfo.processInfo.arguments

    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let seedDemo: Bool = args.contains("-seedDemo")
    static let screen: String? = value("-screen")
    static let anchor: String? = value("-anchor")
    static let step: String? = value("-step")
    static let tod: TimeOfDay? = value("-tod").flatMap { TimeOfDay(rawValue: $0) }
}
