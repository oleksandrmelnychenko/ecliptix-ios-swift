// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum Result<T, E> {
  case ok(T)
  case err(E)
  var isOk: Bool {
    switch self {
    case .ok:
      return true
    case .err:
      return false
    }
  }

  var isErr: Bool {
    !isOk
  }

  func ok() -> T? {
    switch self {
    case .ok(let value):
      return value
    case .err:
      return nil
    }
  }

  func err() -> E? {
    switch self {
    case .ok:
      return nil
    case .err(let error):
      return error
    }
  }

  func unwrapErr() -> E {
    switch self {
    case .ok:
      preconditionFailure("Cannot unwrapErr an Ok result — guard with isErr first")
    case .err(let error):
      return error
    }
  }

  func propagateErr<U>() -> Result<U, E> {
    switch self {
    case .ok:
      preconditionFailure("propagateErr() called on .ok Result — guard logic error")
    case .err(let error):
      return .err(error)
    }
  }

  func map<U>(_ transform: (T) -> U) -> Result<U, E> {
    switch self {
    case .ok(let value):
      return .ok(transform(value))
    case .err(let error):
      return .err(error)
    }
  }

  func mapError<F>(_ transform: (E) -> F) -> Result<T, F> {
    switch self {
    case .ok(let value):
      return .ok(value)
    case .err(let error):
      return .err(transform(error))
    }
  }

  func flatMap<U>(_ transform: (T) -> Result<U, E>) -> Result<U, E> {
    switch self {
    case .ok(let value):
      return transform(value)
    case .err(let error):
      return .err(error)
    }
  }
}

extension Result: Equatable where T: Equatable, E: Equatable {

  static func == (lhs: Result<T, E>, rhs: Result<T, E>) -> Bool {
    switch (lhs, rhs) {
    case (.ok(let lValue), .ok(let rValue)):
      return lValue == rValue
    case (.err(let lError), .err(let rError)):
      return lError == rError
    default:
      return false
    }
  }
}

extension Result: Hashable where T: Hashable, E: Hashable {

  func hash(into hasher: inout Hasher) {
    switch self {
    case .ok(let value):
      hasher.combine(0)
      hasher.combine(value)
    case .err(let error):
      hasher.combine(1)
      hasher.combine(error)
    }
  }
}

extension Result: CustomStringConvertible {

  var description: String {
    switch self {
    case .ok:
      return "Ok"
    case .err:
      return "Err"
    }
  }
}
