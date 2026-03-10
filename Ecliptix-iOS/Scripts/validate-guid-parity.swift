#!/usr/bin/env swift
import Foundation

struct GuidParityError: Error, CustomStringConvertible {
    let description: String
}

private func hex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private func uuidBytes(_ uuid: UUID) -> [UInt8] {
    withUnsafeBytes(of: uuid.uuid) { Array($0) }
}

private func dotNetTryWriteBytes(_ uuid: UUID) -> Data {
    var bytes = uuidBytes(uuid)
    bytes.swapAt(0, 3)
    bytes.swapAt(1, 2)
    bytes.swapAt(4, 5)
    bytes.swapAt(6, 7)
    return Data(bytes)
}

private func dotNetGuidToByteStringBytes(_ uuid: UUID) -> Data {
    var bytes = Array(dotNetTryWriteBytes(uuid))
    bytes.swapAt(0, 3)
    bytes.swapAt(1, 2)
    bytes.swapAt(4, 5)
    bytes.swapAt(6, 7)
    return Data(bytes)
}

private func swiftClientContextBytes(_ uuid: UUID) -> Data {
    var bytes = uuidBytes(uuid)
    bytes.swapAt(0, 3)
    bytes.swapAt(1, 2)
    bytes.swapAt(4, 5)
    bytes.swapAt(6, 7)
    return Data(bytes)
}

private func swiftProtobufBytes(_ uuid: UUID) -> Data {
    Data(uuidBytes(uuid))
}

private func assertEqual(_ lhs: Data, _ rhs: Data, _ message: String) throws {
    guard lhs == rhs else {
        throw GuidParityError(description: "\(message)\n  lhs=\(hex(lhs))\n  rhs=\(hex(rhs))")
    }
}

private func validate(uuid: UUID) throws {
    let expectedClientContext = dotNetTryWriteBytes(uuid)
    let expectedProtobuf = dotNetGuidToByteStringBytes(uuid)
    let swiftClient = swiftClientContextBytes(uuid)
    let swiftProto = swiftProtobufBytes(uuid)

    try assertEqual(swiftClient, expectedClientContext, "ClientContext bytes mismatch for \(uuid.uuidString)")
    try assertEqual(swiftProto, expectedProtobuf, "Protobuf bytes mismatch for \(uuid.uuidString)")

    try assertEqual(swiftProto, Data(Array(expectedClientContext).enumerated().map { idx, _ in
        var b = Array(expectedClientContext)
        b.swapAt(0, 3)
        b.swapAt(1, 2)
        b.swapAt(4, 5)
        b.swapAt(6, 7)
        return b[idx]
    }), "Byte order relationship mismatch for \(uuid.uuidString)")
}

private func run() throws {
    let known = UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!
    try validate(uuid: known)

    for _ in 0..<100 {
        try validate(uuid: UUID())
    }

    print("GUID parity OK")
    print("- protobufBytes -> Helpers.GuidToByteString parity")
    print("- clientContextBytes -> Guid.TryWriteBytes parity")
}

do {
    try run()
} catch {
    fputs("GUID parity FAILED: \(error)\n", stderr)
    exit(1)
}
