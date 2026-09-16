// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

// Swift Package Manager manifest for the iOS plugin. CocoaPods apps use
// ../myaza_kyc_sdk_flutter.podspec instead; both compile the same Sources/,
// so keep the two in step (platform, sources, resources).
//
// Deliberately no FlutterFramework dependency, matching Flutter's own
// first-party plugins: that package only exists from Flutter 3.44, and the
// pubspec supports 3.27+, so an app that switched Swift Package Manager on
// with an earlier Flutter could not resolve "../FlutterFramework". Add it once
// the pubspec floor reaches 3.44.

import PackageDescription

let package = Package(
  name: "myaza_kyc_sdk_flutter",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    // Flutter links the library by this hyphenated name (a bundle identifier
    // cannot contain underscores).
    .library(name: "myaza-kyc-sdk-flutter", targets: ["myaza_kyc_sdk_flutter"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "myaza_kyc_sdk_flutter",
      dependencies: []
    )
  ]
)
