// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PivchikCore",
    defaultLocalization: "ru",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PivchikDomain", targets: ["PivchikDomain"]),
        .library(name: "PivchikStore", targets: ["PivchikStore"]),
    ],
    targets: [
        // Чистая логика без Apple-фреймворков: собирается и тестируется и на Linux.
        .target(name: "PivchikDomain"),
        // Хранилище SwiftData + CloudKit: только платформы Apple.
        .target(name: "PivchikStore", dependencies: ["PivchikDomain"]),
        .testTarget(name: "PivchikDomainTests", dependencies: ["PivchikDomain"]),
    ],
    swiftLanguageModes: [.v5]
)
