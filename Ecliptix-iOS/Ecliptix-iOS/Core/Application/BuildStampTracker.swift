// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum BuildStampTracker {

  private static let buildStampKey = "ecliptix_protocol_build_stamp"

  static func shouldInvalidatePersistedState() -> Bool {
    let stored = UserDefaults.standard.string(forKey: buildStampKey) ?? ""
    return stored != currentBuildStamp()
  }

  static func recordCurrentBuildStamp() {
    UserDefaults.standard.set(currentBuildStamp(), forKey: buildStampKey)
  }

  private static func currentBuildStamp() -> String {
    let bundleVersion =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    let buildDate = Bundle.main.executableURL
      .flatMap {
        try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date
      }
    let ts = buildDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
    return "\(bundleVersion)-\(ts)"
  }
}
