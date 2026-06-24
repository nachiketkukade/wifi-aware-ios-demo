//
//  AccessoryManager.swift
//  ESP Wi-Fi Aware Demo
//

import AccessorySetupKit
import Observation
import UIKit

@MainActor
@Observable
final class AccessoryManager {

    private var _session: ASAccessorySession?
    private var session: ASAccessorySession {
        guard let session = _session else {
            fatalError("AccessoryManager accessed before initialization")
        }
        return session
    }

    private let udpSender: UDPSender

    /// Already-paired accessories surfaced for the "Paired devices" UI, so a
    /// connection can be triggered without going through the pairing picker.
    /// Populated on demand from `session.accessories`.
    private(set) var pairedAccessories: [ASAccessory] = []

    init(log: MessageLog) {
        self.udpSender = UDPSender(log: log)
    }

    func initialize() {
        guard _session == nil else { return }
        _session = ASAccessorySession()
    }

    func activate() {
        initialize()

        // `.accessoryAdded` fires for fresh pairings as well as for
        // already-paired accessories after activation.
        session.activate(on: DispatchQueue.main) { [udpSender] event in
            switch event.eventType {
            case .accessoryAdded:
                guard event.accessory != nil else { return }
                Task { await udpSender.start() }
            case .accessoryRemoved:
                Task { await udpSender.stop() }
            default:
                break
            }
        }
    }

    func showPicker() {
        // Present Picker UI
        session.showPicker(for: [pickerDisplayItem]) { _ in
            // Handle error
        }
    }

    /// Refresh the list of already-paired accessories from the active session.
    /// Call this before presenting the paired-devices UI. `session.accessories`
    /// is only valid after the session has activated; `activate()` is invoked
    /// from `onAppear`, so by the time the user opens the list it's populated.
    func refreshPairedAccessories() {
        guard _session != nil else { return }
        pairedAccessories = session.accessories
    }

    /// Connect to an already-paired accessory WITHOUT presenting the pairing
    /// picker. ASK has already authorized the device, so this just brings up the
    /// Wi-Fi Aware datapath. The browse targets `.allPairedDevices`; with a
    /// single ESP32 in this demo that resolves to `accessory`. (To scope the
    /// browse to one specific device, UDPSender would need to take a
    /// `WAPairedDevice` and use `.connecting(to: .selected([...]))`.)
    func connect(to accessory: ASAccessory) {
        Task { await udpSender.start() }
    }

    /// Tear down the Wi-Fi Aware data path: cancels the browse/send loop and
    /// releases the NAN subscribe. Safe to call when nothing is connected.
    /// Invoked from the Disconnect button and when the app leaves the
    /// foreground (backgrounded or terminated).
    func disconnect() {
        Task { await udpSender.stop() }
    }

    private var pickerDisplayItem: ASPickerDisplayItem {
        // Configure ASDiscoveryDescriptor (Subscriber)
        let descriptor = ASDiscoveryDescriptor()
        descriptor.wifiAwareServiceName = "_ESP-Demo._udp"
        return ASPickerDisplayItem(name: "ESP32",
                                       productImage: UIImage(systemName: "cpu")!,
                                       descriptor: descriptor)
    }
}
