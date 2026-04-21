import Foundation

enum RowStatus: Equatable {
    case idle
    case queued
    case running
    case success
    case failure(String)
}
