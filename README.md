# Ecliptix iOS

Secure messaging platform for iOS built with Swift 6 strict concurrency, SwiftUI, and hybrid post-quantum cryptography.

## Architecture

| Layer | Description |
|-------|-------------|
| **Core/Security** | Hybrid PQ-OPAQUE (Ristretto255 + ML-KEM-768) via Rust FFI, AES-GCM-SIV encryption, Shamir secret sharing |
| **Core/Network** | gRPC transport, protobuf serialization, secure unary pipeline, retry & metadata interceptors |
| **Core/Services** | Authentication (OPAQUE + PIN), logout proof, feed sync, identity, contacts |
| **Core/Storage** | Keychain, GRDB-backed feed cache, protocol state persistence |
| **Features** | Registration, Sign-in, Messaging, Feed, Settings, State Restore |

## Tech Stack

- **Swift 6** — strict concurrency, `Sendable` conformance throughout
- **SwiftUI** — coordinator pattern (`AppCoordinator`)
- **gRPC** — grpc-swift 2.x + swift-protobuf
- **Crypto** — Rust FFI xcframeworks (`EcliptixOPAQUE`, `EcliptixProtocol`)
- **Storage** — GRDB via `EcliptixStorage` local package
- **Target** — iOS 18+, iPhone & iPad

## Project Structure

```
Ecliptix-iOS/
├── App/                    # Entry point, coordinator, theme
├── Core/
│   ├── Application/        # Dependencies, state, initialization
│   ├── Network/
│   │   ├── Interceptors/   # Metadata, retry
│   │   ├── Protocol/       # AES-GCM, handshake
│   │   ├── Protos/         # Typealiases for generated types
│   │   ├── Rpc/            # Auth, messaging, feed, pin, profile RPC
│   │   ├── Services/       # Connectivity, backoff, keychain
│   │   ├── Sync/           # Message processor, outbox
│   │   └── Transport/      # Gateway routes, gRPC channel
│   ├── Security/           # OPAQUE native, EPP native, crypto engine
│   ├── Services/           # Auth, logout, feed, identity
│   ├── Storage/            # Keychain, DB records, crypto state
│   └── Utilities/          # Errors, validation, logging
├── Features/
│   ├── Feed/               # Post list, detail, creation
│   ├── Messaging/          # Conversations, chat, contacts, groups
│   ├── Registration/       # Phone, OTP, PIN, secure key
│   ├── Settings/           # Account, logout
│   ├── SignIn/             # PIN entry, sign-in flow
│   └── StateRestore/       # Session recovery
├── Protos/                 # .proto definitions
└── LocalPackages/
    └── EcliptixStorage/    # GRDB feed database
```

## SPM Dependencies

| Package | Source |
|---------|--------|
| `EcliptixOPAQUE` | [ecliptix-opaque-rs](https://github.com/oleksandrmelnychenko/ecliptix-opaque-rs) — Rust PQ-OPAQUE xcframework |
| `EcliptixProtocol` | [ecliptix-protected-protocol-rs](https://github.com/oleksandrmelnychenko/ecliptix-protected-protocol-rs) — Rust E2E protocol xcframework |
| `EcliptixStorage` | Local — GRDB wrapper for feed caching |
| `grpc-swift-protobuf` | gRPC + Protobuf code generation |
| `swift-protobuf` | Protocol Buffers runtime |
| `swift-collections` | Apple ordered collections |

## Build

```bash
xcodebuild -project Ecliptix-iOS/Ecliptix-iOS.xcodeproj \
  -scheme Ecliptix-iOS \
  -destination 'platform=iOS,name=iPhone' \
  build
```

## License

Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
Licensed under the MIT License. See [LICENSE](LICENSE) for details.
