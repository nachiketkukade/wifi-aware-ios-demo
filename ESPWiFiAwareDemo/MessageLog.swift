//
//  MessageLog.swift
//  ESP Wi-Fi Aware Demo
//

import Foundation
import Observation

@MainActor
@Observable
final class MessageLog {

    private(set) var lines: [String] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func append(_ line: String) {
        let stamp = formatter.string(from: Date())
        lines.append("[\(stamp)] \(line)")
        if lines.count > 200 {
            lines.removeFirst(lines.count - 200)
        }
    }

    func clear() {
        lines.removeAll()
    }
}
