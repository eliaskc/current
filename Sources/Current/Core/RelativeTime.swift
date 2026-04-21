import Foundation

/// Stable "2 min ago" style string — doesn't tick/count up.
/// Call it when rendering; it only updates when the view is re-rendered.
enum RelativeTime {
    static func string(from date: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        switch elapsed {
        case ..<60:      return "just now"
        case ..<3600:    return "\(Int(elapsed / 60)) min ago"
        case ..<86400:
            let h = Int(elapsed / 3600)
            return h == 1 ? "1 hour ago" : "\(h) hours ago"
        default:
            let d = Int(elapsed / 86400)
            return d == 1 ? "1 day ago" : "\(d) days ago"
        }
    }
}
