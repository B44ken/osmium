// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Osmium",
  platforms: [ .macOS(.v13) ],
  products: [ .executable(name: "Osmium", targets: ["Osmium"]) ],
  dependencies: [
    .package(path: "../.deps/SwiftTerm")
  ],
  targets: [
    .target(
      name: "OsmiumPickerSupport",
      path: "PickerSupport"
    ),
    .executableTarget(
      name: "Osmium",
      dependencies: ["SwiftTerm", "OsmiumPickerSupport"],
      path: "./",
      exclude: ["Tests", "PickerSupport"]
    ),
    .executableTarget(
      name: "OsmiumPickerTests",
      dependencies: ["OsmiumPickerSupport"],
      path: "Tests/OsmiumPickerTests"
    )
  ]
)
