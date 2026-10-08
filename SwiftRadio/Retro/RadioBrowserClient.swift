//
//  RadioBrowserClient.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  Client for the free, community-run Radio Browser directory (https://www.radio-browser.info).
//

import Foundation
import SwiftRadioCore

/// One search result from `/json/stations/search`.
struct RadioBrowserStation: Decodable, Sendable, Identifiable, Hashable {
    let stationuuid: String
    let name: String
    let url: String
    let urlResolved: String?
    let favicon: String?
    let homepage: String?
    let tags: String?
    let country: String?
    let countrycode: String?
    let language: String?
    let codec: String?
    let bitrate: Int?
    let lastcheckok: Int?
    let clickcount: Int?

    var id: String { stationuuid }

    private enum CodingKeys: String, CodingKey {
        case stationuuid, name, url, favicon, homepage, tags, country, countrycode, language, codec,
             bitrate, lastcheckok, clickcount
        case urlResolved = "url_resolved"
    }

    var displayName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Prefers the directory's resolved stream URL over the (often playlist) submitted URL.
    var streamURL: String {
        let resolved = (urlResolved ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return resolved.isEmpty ? url.trimmingCharacters(in: .whitespacesAndNewlines) : resolved
    }

    var isWorking: Bool { (lastcheckok ?? 1) == 1 }

    /// "台湾 · chinese · MP3 128k" style summary line.
    var summary: String {
        var parts: [String] = []
        if let code = countrycode, !code.isEmpty { parts.append(code) }
        if let language, !language.isEmpty { parts.append(language) }
        var format = (codec ?? "").uppercased()
        if let bitrate, bitrate > 0 { format += format.isEmpty ? "\(bitrate)k" : " \(bitrate)k" }
        if !format.isEmpty, format != "UNKNOWN" { parts.append(format) }
        return parts.joined(separator: " · ")
    }

    var radioStation: SwiftRadioCore.RadioStation {
        let icon = (favicon ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let usableIcon = icon.lowercased().hasPrefix("http") && !icon.lowercased().hasSuffix(".svg") ? icon : ""
        let site = (homepage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tagLine = (tags ?? "").split(separator: ",").prefix(3).joined(separator: ", ")
        return SwiftRadioCore.RadioStation(
            name: displayName,
            website: site.isEmpty ? nil : site,
            streamURL: streamURL,
            imageURL: usableIcon,
            desc: summary.isEmpty ? tagLine : summary,
            longDesc: tagLine
        )
    }
}

/// Search filters entered on the search screen.
struct RadioSearchQuery: Sendable, Equatable {
    var name = ""
    var countryCode = ""
    var tag = ""
    /// Chinese-language quick filter: language=chinese/mandarin/cantonese plus CN/TW/HK/MO.
    var chineseOnly = false
}

struct RadioBrowserClient: Sendable {
    /// Tried in order; `all.` resolves to any healthy mirror.
    static let hosts = ["de1.api.radio-browser.info", "de2.api.radio-browser.info", "all.api.radio-browser.info"]

    func search(_ query: RadioSearchQuery) async throws -> [RadioBrowserStation] {
        var base: [String: String] = [
            "limit": "50",
            "hidebroken": "true",
            "order": "clickcount",
            "reverse": "true"
        ]
        let name = query.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let tag = query.tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { base["name"] = name }
        if !tag.isEmpty { base["tag"] = tag }

        let requests: [[String: String]]
        if query.chineseOnly {
            var variants: [[String: String]] = []
            for language in ["chinese", "mandarin", "cantonese"] {
                var params = base
                params["language"] = language
                variants.append(params)
            }
            for country in ["CN", "TW", "HK", "MO"] {
                var params = base
                params["countrycode"] = country
                variants.append(params)
            }
            requests = variants
        } else {
            var params = base
            let country = query.countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
            if !country.isEmpty { params["countrycode"] = country }
            requests = [params]
        }

        // Run the variants concurrently; one failing mirror request must not sink the rest.
        let batches: [[RadioBrowserStation]?] = await withTaskGroup(of: [RadioBrowserStation]?.self) { group in
            for params in requests {
                group.addTask { try? await self.fetch(params) }
            }
            var collected: [[RadioBrowserStation]?] = []
            for await batch in group { collected.append(batch) }
            return collected
        }
        try Task.checkCancellation()
        let succeeded = batches.compactMap { $0 }
        if succeeded.isEmpty { throw URLError(.cannotConnectToHost) }

        var seenIDs = Set<String>()
        var seenStreams = Set<String>()
        var merged: [RadioBrowserStation] = []
        for station in succeeded.flatMap({ $0 }) where station.isWorking {
            let stream = station.streamURL.lowercased()
            guard !stream.isEmpty, !seenIDs.contains(station.id), !seenStreams.contains(stream) else { continue }
            seenIDs.insert(station.id)
            seenStreams.insert(stream)
            merged.append(station)
        }
        merged.sort { ($0.clickcount ?? 0) > ($1.clickcount ?? 0) }
        return Array(merged.prefix(100))
    }

    private func fetch(_ params: [String: String]) async throws -> [RadioBrowserStation] {
        var lastError: any Error = URLError(.cannotFindHost)
        for host in Self.hosts {
            var components = URLComponents()
            components.scheme = "https"
            components.host = host
            components.path = "/json/stations/search"
            components.queryItems = params.keys.sorted().map { URLQueryItem(name: $0, value: params[$0]) }
            guard let url = components.url else { throw URLError(.badURL) }
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue("RetroRadio/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                return try JSONDecoder().decode([RadioBrowserStation].self, from: data)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                lastError = error
            }
        }
        throw lastError
    }
}
