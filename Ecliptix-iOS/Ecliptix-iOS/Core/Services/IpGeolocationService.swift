// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

protocol IpGeolocating: AnyObject {

  func getIpCountry() async -> Result<IpCountry, String>
}

struct IpCountry {

  let ipAddress: String
  let country: String
}

final class IpGeolocationService {

  static let shared = IpGeolocationService()
  private static let baseURL = URL(string: "https://api.country.is")!
  private static let decoder = JSONDecoder()

  private init() {}

  private struct GeoResponse: Decodable {

    let ip: String?
    let ipAddress: String?
    let country: String?
    let country_name: String?
    let countryCode: String?
    let country_code: String?

    var resolvedIp: String { ip ?? ipAddress ?? "unknown" }
    var resolvedCountry: String? {
      [country, country_name, countryCode, country_code]
        .compactMap { $0 }
        .first { !$0.isEmpty }
    }
  }

  func getIpCountry() async -> Result<IpCountry, String> {
    var request = URLRequest(url: Self.baseURL)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = AppConstants.IpGeolocation.timeoutSeconds
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse else {
        return .err("Geo API returned non-HTTP response")
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        let body =
          String(data: data.prefix(AppConstants.IpGeolocation.responsePrefixBytes), encoding: .utf8)
          ?? ""
        return .err("Geo API failed with \(httpResponse.statusCode): \(body)")
      }

      let geo = try Self.decoder.decode(GeoResponse.self, from: data)
      guard let country = geo.resolvedCountry else {
        return .err("Geo API returned no country")
      }
      return .ok(IpCountry(ipAddress: geo.resolvedIp, country: country))
    } catch is CancellationError {
      return .err("Geo API request cancelled")
    } catch let error as URLError where error.code == .timedOut {
      return .err("Geo API request timed out")
    } catch is DecodingError {
      return .err("Invalid JSON from Geo API")
    } catch {
      return .err("Network error calling Geo API: \(error.localizedDescription)")
    }
  }
}

extension IpGeolocationService: IpGeolocating {}
