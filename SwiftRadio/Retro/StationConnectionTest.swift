//
//  StationConnectionTest.swift
//  Retro Radio
//
//  SPDX-License-Identifier: MIT
//
//  Connection + silence test for the "add station" flow.
//  Inspired by Radio Anywhere's "Connection Verified" badge, plus a silence
//  check on top: a reachable stream can still be digital silence (VOA taught us
//  that the hard way — reachable does not mean audible).
//

import AVFoundation
import Foundation

/// Outcome of testing a station's stream URL.
enum ConnectionTestResult: Equatable {
    case idle
    case testing
    /// Reachable, and the sampled audio carries real signal.
    case verified
    /// Reachable, but the sampled audio is (near-)digital silence.
    case silent
    /// Reachable, but the audio content could not be decoded/checked.
    case reachableUnverified
    /// Not reachable, or the URL is unusable. Carries a human-readable reason.
    case failed(String)
}

private enum TestError: Error {
    case badURL
    case network(String)
    case badPlaylist
    case noSegment

    var message: String {
        switch self {
        case .badURL: return "地址不是有效的 http(s) 链接"
        case .network(let detail): return detail
        case .badPlaylist: return "播放列表解析失败"
        case .noSegment: return "播放列表里没有可用的音频分片"
        }
    }
}

private enum AudioEnergy {
    case hasAudio
    case silent
    case undecodable
}

/// Tests whether a stream URL is reachable and whether it actually carries audio.
/// Never throws; all failures are mapped to `ConnectionTestResult`.
enum StationConnectionTester {
    /// Peak amplitude below this (-40 dBFS) counts as silence.
    private static let silencePeakThreshold: Float = 0.01
    /// How much audio to decode for the silence check.
    private static let sampleSeconds: Double = 5
    /// Cap for direct (non-HLS) stream sampling.
    private static let directSampleBytes = 1_048_576

    static func test(streamURL: String) async -> ConnectionTestResult {
        let trimmed = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return .failed(TestError.badURL.message)
        }
        do {
            let isPlaylist = url.pathExtension.lowercased() == "m3u8"
                || url.absoluteString.lowercased().contains("m3u8")
            let audioURL = try await resolveSampleURL(from: url, isPlaylist: isPlaylist)
            // HLS segments are small: download whole. Direct streams can be
            // infinite: only sample the head via a Range request.
            let sampleFile = try await downloadSample(from: audioURL, fullDownload: isPlaylist)
            defer { try? FileManager.default.removeItem(at: sampleFile) }
            switch audioEnergy(of: sampleFile) {
            case .hasAudio: return .verified
            case .silent: return .silent
            case .undecodable: return .reachableUnverified
            }
        } catch let error as TestError {
            return .failed(error.message)
        } catch {
            return .failed((error as NSError).localizedDescription)
        }
    }

    // MARK: - URL resolution

    /// For HLS playlists, resolves down to one media segment URL.
    /// Direct audio URLs are returned as-is.
    private static func resolveSampleURL(from url: URL, isPlaylist: Bool) async throws -> URL {
        guard isPlaylist else { return url }

        let text = try await downloadText(from: url)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Variant playlist: follow the first variant.
        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
            guard let variant = lines.first(where: { !$0.hasPrefix("#") }),
                  let resolved = URL(string: variant, relativeTo: url)?.absoluteURL
            else { throw TestError.badPlaylist }
            return try await resolveSampleURL(from: resolved, isPlaylist: true)
        }

        // Media playlist: take the latest segment (last one listed).
        guard let segment = lines.last(where: { !$0.hasPrefix("#") }),
              let resolved = URL(string: segment, relativeTo: url)?.absoluteURL
        else { throw TestError.noSegment }
        return resolved
    }

    // MARK: - Download

    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 25
        return URLSession(configuration: config)
    }

    private static func downloadText(from url: URL) async throws -> String {
        do {
            let (data, response) = try await session().data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw TestError.network("服务器返回异常")
            }
            guard let text = String(data: data, encoding: .utf8) else { throw TestError.badPlaylist }
            return text
        } catch let error as TestError {
            throw error
        } catch {
            throw TestError.network(friendlyNetworkError(error))
        }
    }

    /// Downloads one HLS segment whole (they are small), or the first
    /// `directSampleBytes` of a direct stream via a Range request.
    private static func downloadSample(from url: URL, fullDownload: Bool) async throws -> URL {
        let ext = url.pathExtension.isEmpty ? "aac" : url.pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            // Direct streams can be infinite; only sample the head.
            if !fullDownload {
                request.setValue("bytes=0-\(directSampleBytes - 1)", forHTTPHeaderField: "Range")
            }
            let (data, response) = try await session().data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) || http.statusCode == 206
            else { throw TestError.network("服务器返回异常") }
            guard !data.isEmpty else { throw TestError.network("没有收到数据") }
            try data.write(to: destination)
            return destination
        } catch let error as TestError {
            throw error
        } catch {
            throw TestError.network(friendlyNetworkError(error))
        }
    }

    private static func friendlyNetworkError(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorTimedOut: return "连接超时"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "找不到服务器"
        case NSURLErrorNotConnectedToInternet: return "没有网络连接"
        case NSURLErrorCancelled: return "已取消"
        default: return "网络错误"
        }
    }

    // MARK: - Silence check

    private static func audioEnergy(of file: URL) -> AudioEnergy {
        do {
            let audioFile = try AVAudioFile(forReading: file)
            let format = audioFile.processingFormat
            guard format.sampleRate > 0, format.channelCount > 0 else { return .undecodable }
            let framesToRead = AVAudioFrameCount(
                min(Double(audioFile.length), format.sampleRate * sampleSeconds))
            guard framesToRead > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToRead)
            else { return .undecodable }
            try audioFile.read(into: buffer)
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return .undecodable }

            var peak: Float = 0
            let channels = Int(buffer.format.channelCount)
            if let floatData = buffer.floatChannelData {
                for ch in 0..<channels {
                    let data = floatData[ch]
                    for i in 0..<frames {
                        let v = abs(data[i])
                        if v > peak { peak = v }
                    }
                }
            } else if let int16Data = buffer.int16ChannelData {
                for ch in 0..<channels {
                    let data = int16Data[ch]
                    for i in 0..<frames {
                        let v = abs(Float(data[i])) / Float(Int16.max)
                        if v > peak { peak = v }
                    }
                }
            } else {
                return .undecodable
            }
            return peak >= silencePeakThreshold ? .hasAudio : .silent
        } catch {
            return .undecodable
        }
    }
}
