//
//  UDPSender.swift
//  ESP Wi-Fi Aware Demo
//

import Foundation
import Network
import WiFiAware

actor UDPSender {

    private let log: MessageLog
    private var task: Task<Void, Never>?

    init(log: MessageLog) {
        self.log = log
    }

    /// HH:mm:ss.SSS wall clock, matching the `wifip2pd` unified-log timestamps
    /// so app-side state can be lined up against the daemon's datapath decisions.
    nonisolated static func ts() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    /// Network framework surfaces Wi-Fi Aware failures as opaque
    /// `NWError -11994`-style codes. The WiFiAware framework can decode an
    /// `NWError` into a named `WAError` case (subscriberTimeout, noPairedDevices,
    /// connectionFailed, …) via `NWError.wifiAware`, which is far more
    /// actionable. Prefer that case when available, otherwise fall back to the
    /// raw description.
    nonisolated static func describe(_ error: Error) -> String {
        if let nwError = error as? NWError, let waError = nwError.wifiAware {
            return "\(waError) — \(waError.localizedDescription) [\(error.localizedDescription)]"
        }
        return error.localizedDescription
    }

    func start() {
        // Serialize against any in-flight run: cancel the previous task and
        // AWAIT its full teardown before browsing again. `cancel()` alone
        // returns immediately while the old `NetworkBrowser`'s NAN subscribe is
        // still alive, so a back-to-back restart (e.g. `.accessoryAdded`
        // auto-start followed by a manual "Connect") would race and the second
        // subscribe is rejected with `serviceAlreadySubscribing` (WAError 5).
        let previous = task
        task = Task { [weak self] in
            previous?.cancel()
            _ = await previous?.value
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        guard WACapabilities.supportedFeatures.contains(.wifiAware) else {
            await log.append("Wi-Fi Aware not supported on this device")
            return
        }

        guard let service = WASubscribableService.allServices["_ESP-Demo._udp"] else {
            await log.append("Service '_ESP-Demo._udp' not declared in Info.plist")
            return
        }

        var browseTask: Task<Void, Never>?
        defer { browseTask?.cancel() }

        do {
            await log.append("Browsing for Wi-Fi Aware endpoint…")
            // Keep the NAN subscribe ALIVE for the whole connection lifetime.
            // Returning `.finish` the instant we find the peer issues a "Stop
            // browse request" (wifip2pd: Subscriber Running -> Aborted, then
            // APPLE80211_IOC_NAN_CANCEL_SUBSCRIBE, "User Requested"). With no
            // live discovery session iOS never forms a NANDatapathInitiator
            // (datapathInitiatorCount stays 0), so the NDP Request is never
            // transmitted and the connection hangs in `.preparing`. Instead we
            // browse in a concurrent task that always returns `.continue`,
            // holding discovery up while the datapath negotiates — matching the
            // pattern in Apple's Wi-Fi Aware sample.
            // The subscribe for this service can be momentarily held by another
            // client (our own just-cancelled browser, or `deviceaccessd`/ASK
            // during pairing verification), surfacing as `serviceAlreadySubscribing`
            // (WAError 5). That's transient: once the holder releases, a fresh
            // subscribe succeeds. Retry the browse a few times with a short
            // backoff before giving up. A *new* `NetworkBrowser` is built per
            // attempt because a failed browser can't be reused.
            var endpoint: WAEndpoint?
            let maxAttempts = 5
            for attempt in 1...maxAttempts {
                let browser = NetworkBrowser(
                    for: .wifiAware(.connecting(to: .allPairedDevices, from: service))
                )

                let gate = EndpointGate()
                do {
                    endpoint = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<WAEndpoint, Error>) in
                        browseTask = Task {
                            do {
                                // The Void-returning `run` overload browses until
                                // the task is cancelled, so discovery stays alive
                                // for the connection's whole lifetime. We grab the
                                // first endpoint (once, via the gate) without ever
                                // ending the browse.
                                try await browser.run { endpoints in
                                    if let first = endpoints.first, gate.claim() {
                                        cont.resume(returning: first)
                                    }
                                }
                            } catch {
                                if gate.claim() { cont.resume(throwing: error) }
                            }
                        }
                    }
                    break
                } catch {
                    browseTask?.cancel()
                    browseTask = nil
                    var isSubscribeBusy = false
                    if let waError = (error as? NWError)?.wifiAware,
                       case .serviceAlreadySubscribing = waError {
                        isSubscribeBusy = true
                    }
                    guard isSubscribeBusy, attempt < maxAttempts, !Task.isCancelled else { throw error }
                    try? await Task.sleep(for: .seconds(1))
                }
            }

            guard let endpoint else { return }

            await log.append("\(Self.ts()) Opening UDP connection…")
            let connection = NetworkConnection(
                to: endpoint,
                using: .parameters { UDP() }
                    .wifiAware { $0.performanceMode = .bulk }
                    .serviceClass(.interactiveVideo)
            )

            // A `NetworkConnection` starts lazily: it's the first
            // send()/receive() that drives it past `setup` and emits the NAN
            // Data Path Request. send()/receive() implicitly await readiness, so
            // there's no need to gate the loop on `.ready`. The connection (and
            // its NAN data path) is released when `run()` returns and it leaves
            // scope, so exiting the loop on Disconnect tears it down.
            while !Task.isCancelled {
                let message = "Message from iPhone"
                do {
                    try await connection.send(Data(message.utf8))
                    await log.append("\(Self.ts()) → \(message)")

                    let received = try await connection.receive()
                    let echo = String(decoding: received.content, as: UTF8.self)
                    await log.append("\(Self.ts()) ← \(echo)")
                } catch {
                    // Disconnect/backgrounding cancels the task and tears the
                    // connection down mid-flight; the resulting send/receive
                    // failure (e.g. NWError 22) is expected, not a real error.
                    if Task.isCancelled { break }
                    await log.append("\(Self.ts()) error: \(Self.describe(error))")
                }
                try? await Task.sleep(for: .seconds(1))
            }
        } catch {
            // A cancelled browse/connection surfaces as a thrown error too —
            // only report genuine failures, not an intentional teardown.
            if !Task.isCancelled {
                await log.append("Wi-Fi Aware UDP error: \(Self.describe(error))")
            }
        }

        if Task.isCancelled {
            await log.append("Disconnected")
        }
    }
}

/// One-shot, thread-safe latch so the first discovered endpoint resolves the
/// continuation exactly once while the browse keeps running (`.continue`).
private nonisolated final class EndpointGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    /// Returns `true` only on the first call; `false` thereafter.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}
