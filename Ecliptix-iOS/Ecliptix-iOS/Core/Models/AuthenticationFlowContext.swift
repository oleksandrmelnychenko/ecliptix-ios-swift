// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum AuthenticationFlowContext: Hashable {
  case registration
  case signIn
  case secureKeyRecovery
}
