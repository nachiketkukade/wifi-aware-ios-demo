# ESP Wi-Fi Aware Demo

> **Disclaimer:** This app is provided for demonstration purposes only. It may
> or may not be updated or maintained.

## What this project is

An iOS 26+ SwiftUI template that pairs with an ESP32 over AccessorySetupKit and
opens a Wi-Fi Aware (NAN) data path to it. It browses for a paired device,
establishes a UDP connection, and runs a send/echo loop shown in an on-screen
console.

- Uses Apple's `WiFiAware` and `Network` frameworks against the `_ESP-Demo._udp`
  service
- Works with ESP32 devices running Espressif's
  [`wifi_aware`](https://components.espressif.com/components/espressif/wifi_aware/versions/0.0.1/readme)
  component (e.g. the `udp_server` example)

## How to use

1. Build and flash the
   [`udp_server`](https://components.espressif.com/components/espressif/wifi_aware/versions/0.0.1/examples/udp_server?language=en)
   example from the
   [`wifi_aware`](https://components.espressif.com/components/espressif/wifi_aware/versions/0.0.1/readme)
   component (it advertises `_ESP-Demo._udp`).
2. Build and run this app on an iOS / iPadOS device (Running iOS 26+, must be iPhone 12+ or iPad 10+)
   (See full list of eligible devices on [`Apple Wi-Fi Aware Documentation`](https://developer.apple.com/documentation/WiFiAware))
3. Tap **Pair New Device**, select the ESP32 in the AccessorySetupKit sheet, and
   enter the pairing PIN shown on the ESP32 console.
4. After pairing, the app browses, opens a UDP data path, and starts the
   send/echo loop. Pairing credentials are retained across app and device
   resets; reopen the data path any time via **Paired Devices** in the app
   without re-pairing. Paired accessories also appear under
   **Settings → Privacy & Security → Accessories** (and the related Paired
   Devices list).
5. Tap **Disconnect** (or background the app) to tear the data path down.
6. To pair again from scratch: remove the accessory in
   **Settings → Privacy & Security → Accessories**, clear its **WLAN
   Identifier**, and long-press **BOOT** on the ESP32 to reset its pairing
   store. Then use **Pair New Device** in the app.
