import Foundation
import Testing
@testable import LingoCore

struct RedactorTests {
    @Test func hexKeepsTwoFirstAndTwoLastBytesOfLongBlobs() {
        let frame = Data((1...51).map { UInt8($0) })
        #expect(Redactor.hex(frame) == "0102…3233 (51 B)")
        let nine = Data((0..<9).map { UInt8($0) })
        #expect(Redactor.hex(nine) == "0001…0708 (9 B)")
        let eight = Data([0xA1, 0, 0, 0, 0, 0, 0, 0xFF])
        #expect(Redactor.hex(eight) == "a1000000000000ff")
        #expect(Redactor.hex(Data()) == "")
    }

    @Test func serialAndSecrets() {
        #expect(Redactor.serial("0D12345678") == "0D1…")
        #expect(Redactor.serial("AB") == "…")
        let kAuth = Data(repeating: 0x5A, count: 16)
        #expect(Redactor.secret(kAuth) == "‹secreto 16 B›")
    }

    @Test func logMessageOnlyAcceptsRedactedInterpolations() async throws {
        let frame = Data((0..<51).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let kAuth = Data(repeating: 0xC3, count: 16)
        let serial = "3MH00ABCDE"
        let message: LogMessage = "trama \(hex: frame) sensor \(serial: serial) kAuth \(secret: kAuth) lc \(63) fase \(public: "challenge")"
        let fullHex = frame.map { String(format: "%02x", $0) }.joined()
        #expect(!message.text.contains(fullHex))
        #expect(!message.text.contains(serial))
        #expect(!message.text.contains("c3c3"))
        #expect(message.text == "trama 0007…575e (51 B) sensor 3MH… kAuth ‹secreto 16 B› lc 63 fase challenge")

        let store = try TestSupport.makeStore()
        try await store.logEvent(.info, category: "ble", message)
        let stored = try #require(try await store.recentLogEvents(limit: 1).first)
        #expect(stored.message == message.text && stored.category == "ble" && stored.level == .info)
        #expect(stored.at.rfc3339 == "2026-10-28T15:06:40Z")
    }
}
