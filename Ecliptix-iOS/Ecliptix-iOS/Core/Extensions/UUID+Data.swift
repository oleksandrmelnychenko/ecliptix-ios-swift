// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension UUID {

  static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
  var isZero: Bool { self == .zero }
  init?(data: Data) {
    guard data.count == AppConstants.Crypto.guidBytesCount else { return nil }
    let bytes = Array(data)
    self.init(
      uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
      ))
  }

  var protobufBytes: Data {
    withUnsafeBytes(of: uuid) { Data($0) }
  }
}
