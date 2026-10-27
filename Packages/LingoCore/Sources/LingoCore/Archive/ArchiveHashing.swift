import CryptoKit
import Foundation

enum ArchiveHashing {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { b in
            let h = String(b, radix: 16)
            return h.count == 1 ? "0" + h : h
        }.joined()
    }
}
