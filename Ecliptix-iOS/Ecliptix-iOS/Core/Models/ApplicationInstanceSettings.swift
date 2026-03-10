// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum RegistrationCheckpoint: String, Codable {
  case otpVerified
  case secureKeySet
  case pinSet
  case profileCompleted
}

struct ApplicationInstanceSettings: Codable {

  let deviceId: UUID
  let appInstanceId: UUID
  var culture: String
  var membership: Membership?
  var currentAccountId: UUID?
  var registrationCheckpoint: RegistrationCheckpoint?

  init(
    deviceId: UUID = UUID(),
    appInstanceId: UUID = UUID(),
    culture: String,
    membership: Membership? = nil,
    currentAccountId: UUID? = nil,
    registrationCheckpoint: RegistrationCheckpoint? = nil
  ) {
    self.deviceId = deviceId
    self.appInstanceId = appInstanceId
    self.culture = culture
    self.membership = membership
    self.currentAccountId = currentAccountId
    self.registrationCheckpoint = registrationCheckpoint
  }
}

struct Membership: Codable {

  let membershipId: UUID
  let mobileNumber: String
  let createdAt: Date

  init(membershipId: UUID, mobileNumber: String, createdAt: Date = Date()) {
    self.membershipId = membershipId
    self.mobileNumber = mobileNumber
    self.createdAt = createdAt
  }
}
typealias InstanceSettingsResult = (settings: ApplicationInstanceSettings, isNewInstance: Bool)
