// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct DeviceRecord: Codable, Sendable {
  var deviceId: Data
  var userId: Data
  var displayName: String?
  var deviceType: Int
  var registeredAt: Int64
  var isCurrent: Bool
}

extension DeviceRecord: FetchableRecord, PersistableRecord, TableRecord {
  static let databaseTableName = "device"
}

extension DeviceRecord {
  enum DeviceType: Int, Sendable {
    case phone = 0
    case tablet = 1
    case desktop = 2
  }
}
