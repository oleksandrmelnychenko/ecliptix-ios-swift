// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import os.log

actor GrpcChannelProvider {

  private var client: GRPCClient<HTTP2ClientTransport.TransportServices>?
  private var runTask: Task<Void, Error>?
  private let configuration: NetworkConfiguration

  private static let logger = Logger(
    subsystem: "com.ecliptix.app",
    category: "GrpcChannel"
  )

  init(configuration: NetworkConfiguration = .default) {
    self.configuration = configuration
    Self.logger.info(
      "GrpcChannelProvider init: host=\(configuration.baseURL, privacy: .public), port=\(configuration.port, privacy: .public), tls=\(configuration.useTLS, privacy: .public)"
    )
  }

  func getClient() async throws -> GRPCClient<HTTP2ClientTransport.TransportServices> {
    if let existing = client {
      Self.logger.debug("getClient: returning existing client")
      return existing
    }
    Self.logger.info("getClient: building new client...")
    let newClient = try buildClient()
    self.client = newClient
    Self.logger.info("getClient: client built, starting runConnections task")
    self.runTask = Task { [weak self] in
      do {
        try await newClient.runConnections()
        Self.logger.info("runConnections: completed normally")
      } catch {
        Self.logger.error(
          "runConnections: FAILED — \(error.localizedDescription, privacy: .public)")
        Self.logger.error(
          "runConnections: error type = \(String(reflecting: type(of: error)), privacy: .public)")
        await self?.clearDeadClient()
      }
    }
    return newClient
  }

  private func buildClient() throws -> GRPCClient<HTTP2ClientTransport.TransportServices> {
    let transportSecurity: HTTP2ClientTransport.TransportServices.TransportSecurity

    if configuration.useTLS {
      #if DEBUG
        #if targetEnvironment(simulator)
          Self.logger.warning("buildClient: TLS .noVerification (SIMULATOR DEBUG)")
          transportSecurity = .tls { config in
            config.serverCertificateVerification = .noVerification
          }
        #else
          Self.logger.info("buildClient: TLS with system trust (DEVICE DEBUG)")
          transportSecurity = .tls
        #endif
      #else
        Self.logger.info("buildClient: TLS with system trust (RELEASE)")
        transportSecurity = .tls
      #endif
    } else {
      Self.logger.info("buildClient: plaintext (no TLS)")
      transportSecurity = .plaintext
    }

    Self.logger.info(
      "buildClient: creating HTTP2 TransportServices to \(self.configuration.baseURL, privacy: .public):\(self.configuration.port, privacy: .public)"
    )
    let transport = try HTTP2ClientTransport.TransportServices(
      target: .dns(host: configuration.baseURL, port: configuration.port),
      transportSecurity: transportSecurity
    )
    Self.logger.info("buildClient: HTTP2 TransportServices created OK")
    return GRPCClient(transport: transport)
  }

  private func clearDeadClient() {
    Self.logger.warning("clearDeadClient: removing failed client reference")
    client = nil
    runTask = nil
  }

  func shutdown() async {
    client?.beginGracefulShutdown()
    _ = await runTask?.result
    runTask = nil
    client = nil
  }
}
