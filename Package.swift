// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "App", platforms: [.macOS(.v26)], 
  dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0")],
  targets: [.executableTarget(name: "App", dependencies: ["SwiftTerm"], path: ".", exclude: ["osm", "App", "entry.ts"])],
)