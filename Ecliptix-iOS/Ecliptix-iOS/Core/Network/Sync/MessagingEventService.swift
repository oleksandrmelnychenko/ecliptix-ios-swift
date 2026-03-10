// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os.log

extension Notification.Name {
  static let messagingIncomingMessage = Notification.Name("ecliptix.messaging.incomingMessage")
  static let messagingTypingEvent = Notification.Name("ecliptix.messaging.typingEvent")
}

enum MessagingNotificationKey {
  static let conversationId = "conversationId"
  static let envelope = "envelope"
  static let membershipId = "membershipId"
  static let displayName = "displayName"
  static let isTyping = "isTyping"
}

actor MessagingEventService {

  enum State: Sendable {
    case idle
    case connecting
    case streaming
    case disconnected(retryAt: Date)
    case failed(String)
  }

  private let streamRequestExecutor: any SecureStreamingRequestExecuting
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private let reconnectPolicy: StreamReconnectPolicy

  private(set) var state: State = .idle
  private var streamTask: Task<Void, Never>?
  private var typingStreamTask: Task<Void, Never>?
  private var retryCount: Int = 0
  private var typingRetryCount: Int = 0

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app",
    category: "MessagingEventService"
  )

  init(
    streamRequestExecutor: any SecureStreamingRequestExecuting,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    reconnectPolicy: StreamReconnectPolicy = .default
  ) {
    self.streamRequestExecutor = streamRequestExecutor
    self.connectIdProvider = connectIdProvider
    self.reconnectPolicy = reconnectPolicy
  }

  func start() async {
    guard case .idle = state else {
      Self.log.warning(
        "MessagingEventService.start() called in non-idle state: \(String(describing: self.state), privacy: .public)"
      )
      return
    }
    Self.log.info("MessagingEventService: starting")
    state = .connecting
    startMessageStream()
    startTypingStream()
  }

  func stop() {
    Self.log.info("MessagingEventService: stopping")
    streamTask?.cancel()
    streamTask = nil
    typingStreamTask?.cancel()
    typingStreamTask = nil
    state = .idle
    retryCount = 0
    typingRetryCount = 0
  }

  private func startMessageStream() {
    streamTask?.cancel()
    streamTask = Task { [weak self] in
      guard let self else { return }
      await self.runStream()
    }
  }

  private func startTypingStream() {
    typingStreamTask?.cancel()
    typingStreamTask = Task { [weak self] in
      guard let self else { return }
      await self.runTypingStream()
    }
  }

  private func runStream() async {
    state = .streaming
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    Self.log.info(
      "MessagingEventService: delivery stream connecting connectId=\(connectId, privacy: .public)"
    )
    let result = await streamRequestExecutor.executeReceiveStreamRequest(
      connectId: connectId,
      serviceType: .subscribeNewMessages,
      plainBuffer: Data(),
      onStreamItem: { [weak self] decryptedBytes in
        guard let self else { return .ok(.value) }
        await self.handleIncomingBytes(decryptedBytes)
        return .ok(.value)
      },
      allowDuplicates: true,
      cancellationToken: .none,
      exchangeType: .dataCenterEphemeralConnect
    )
    switch result {
    case .ok:
      Self.log.info("MessagingEventService: delivery stream ended cleanly")
    case .err(let failure):
      Self.log.warning(
        "MessagingEventService: delivery stream error: \(failure.message, privacy: .public)"
      )
    }
    guard !Task.isCancelled else { return }
    await scheduleMessageReconnect()
  }

  private func handleIncomingBytes(_ bytes: Data) async {
    guard !bytes.isEmpty else { return }
    do {
      let envelope = try ProtoMessageEnvelope(serializedBytes: bytes)
      let conversationId = envelope.conversationID
      Self.log.debug(
        "MessagingEventService: incoming message conversation=\(conversationId.hexString, privacy: .public)"
      )
      await MainActor.run {
        NotificationCenter.default.post(
          name: .messagingIncomingMessage,
          object: nil,
          userInfo: [
            MessagingNotificationKey.conversationId: conversationId,
            MessagingNotificationKey.envelope: envelope,
          ]
        )
      }
    } catch {
      Self.log.warning(
        "MessagingEventService: failed to parse MessageEnvelope: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func runTypingStream() async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    Self.log.info(
      "MessagingEventService: typing stream connecting connectId=\(connectId, privacy: .public)"
    )
    let result = await streamRequestExecutor.executeReceiveStreamRequest(
      connectId: connectId,
      serviceType: .subscribeTypingIndicators,
      plainBuffer: Data(),
      onStreamItem: { [weak self] decryptedBytes in
        guard let self else { return .ok(.value) }
        await self.handleTypingBytes(decryptedBytes)
        return .ok(.value)
      },
      allowDuplicates: true,
      cancellationToken: .none,
      exchangeType: .dataCenterEphemeralConnect
    )
    switch result {
    case .ok:
      Self.log.info("MessagingEventService: typing stream ended cleanly")
    case .err(let failure):
      Self.log.warning(
        "MessagingEventService: typing stream error: \(failure.message, privacy: .public)"
      )
    }
    guard !Task.isCancelled else { return }
    await scheduleTypingReconnect()
  }

  private func handleTypingBytes(_ bytes: Data) async {
    guard !bytes.isEmpty else { return }
    do {
      let indicator = try ProtoTypingIndicator(serializedBytes: bytes)
      await MainActor.run {
        NotificationCenter.default.post(
          name: .messagingTypingEvent,
          object: nil,
          userInfo: [
            MessagingNotificationKey.conversationId: indicator.conversationID,
            MessagingNotificationKey.membershipId: indicator.membershipID,
            MessagingNotificationKey.displayName: indicator.displayName,
            MessagingNotificationKey.isTyping: indicator.isTyping,
          ]
        )
      }
    } catch {
      Self.log.warning(
        "MessagingEventService: failed to parse TypingIndicator: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func scheduleMessageReconnect() async {
    guard retryCount < reconnectPolicy.maxRetryCount else {
      state = .failed("Max retry count exceeded")
      Self.log.error("MessagingEventService: max retry count exceeded, giving up")
      return
    }
    retryCount += 1
    let totalDelay = reconnectPolicy.delay(forAttempt: retryCount)
    let retryDate = Date().addingTimeInterval(totalDelay)
    state = .disconnected(retryAt: retryDate)
    Self.log.info(
      "MessagingEventService: reconnecting in \(totalDelay, format: .fixed(precision: 1))s (attempt \(self.retryCount))"
    )
    try? await Task.sleep(for: .seconds(totalDelay))
    guard !Task.isCancelled else { return }
    startMessageStream()
  }

  private func scheduleTypingReconnect() async {
    guard typingRetryCount < reconnectPolicy.maxRetryCount else {
      Self.log.error("MessagingEventService: typing stream max retry count exceeded")
      return
    }
    typingRetryCount += 1
    let totalDelay = reconnectPolicy.delay(forAttempt: typingRetryCount)
    Self.log.info(
      "MessagingEventService: typing reconnect in \(totalDelay, format: .fixed(precision: 1))s (attempt \(self.typingRetryCount))"
    )
    try? await Task.sleep(for: .seconds(totalDelay))
    guard !Task.isCancelled else { return }
    startTypingStream()
  }
}
