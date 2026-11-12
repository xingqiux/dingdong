import Foundation
import SwiftUI

struct Message: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let source: String
    let level: String
    let url: String?
    let createdAt: Int64

    var date: Date { Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000) }
    var link: URL? { url.flatMap { $0.isEmpty ? nil : URL(string: $0) } }
}

struct StreamEvent: Decodable {
    let type: String
    let message: Message?
    let messages: [Message]?
    let id: String?
}

enum ConnStatus: Equatable {
    case unconfigured, connecting, online, offline, unauthorized

    var label: String {
        switch self {
        case .unconfigured: "待设置"
        case .connecting: "连接中"
        case .online: "在线"
        case .offline: "离线"
        case .unauthorized: "Token 不对"
        }
    }

    var color: Color {
        switch self {
        case .online: Theme.mint
        case .connecting: Theme.peach
        case .unconfigured: Theme.lavender
        case .offline, .unauthorized: Theme.rose
        }
    }
}

enum TimeText {
    static func of(_ d: Date, now: Date = .now) -> String {
        let s = now.timeIntervalSince(d)
        if s < 45 { return "刚刚" }
        if s < 3600 { return "\(max(1, Int(s / 60))) 分钟前" }
        let cal = Calendar.current
        let hm = d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if cal.isDateInToday(d) { return hm }
        if cal.isDateInYesterday(d) { return "昨天 \(hm)" }
        let md = d.formatted(.dateTime.month(.defaultDigits).day())
        return "\(md) \(hm)"
    }
}
