// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation

struct GatewayRoute: Sendable {

  let context: EventContext
  let eventType: TransportEventType
  let deliveryKind: DeliveryKind

  init(
    _ context: EventContext,
    _ eventType: TransportEventType,
    _ deliveryKind: DeliveryKind
  ) {
    self.context = context
    self.eventType = eventType
    self.deliveryKind = deliveryKind
  }
}
