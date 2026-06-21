// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Osmium", platforms: [.macOS(.v26)], 
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
  ],
  targets: [.executableTarget(name: "Osmium", dependencies: ["SwiftTerm", "Yams"], path: ".")],
)