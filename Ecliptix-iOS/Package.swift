// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ecliptix-iOS",
    platforms: [
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "EcliptixProtos",
            targets: ["EcliptixProtos"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.2.1"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.2.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.34.1")
    ],
    targets: [
        .target(
            name: "EcliptixProtos",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            path: "Ecliptix-iOS/Generated/Protos",
            swiftSettings: [
                .unsafeFlags(["-suppress-warnings"])
            ]
        )
    ]
)
