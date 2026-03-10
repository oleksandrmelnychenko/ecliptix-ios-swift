// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum SecureStorageConstants {

  enum Encryption {

    static let nonceSize = 12
    static let tagSize = 16
    static let keySize = 32
    static let hmacSha512Size = 64
  }

  enum Header {

    static let magicHeader = "ECLIPTIX_SECURE_V1"
    static let currentVersion: UInt32 = 3
  }

  enum Identity {

    static let revocationProofPrefix = "revocation_proof_"
    static let revocationProofHashPrefixLength = 32
    static let accountHashPrefixLength = 16
  }

  enum Settings {

    static let encryptedFileExtension = "enc"
    static let versionByte: UInt8 = 0x02
  }

  enum SessionState {

    static let version: UInt8 = 0x02
  }
}
