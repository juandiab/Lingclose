import Foundation
import Testing
@testable import LingoCore

/// `RecoveryMerge` (§5 paso 4, draft.4) contra `examples/recovery/merge/expected.json` y la tabla.
@Suite("RecoveryMerge: fusión draft.4")
struct RecoveryMergeTests {
    struct Expected: Decodable {
        struct Body: Decodable {
            let attempt_id: String
            let session_id: String
            let sequence: Int
            let from_file: Int
            let activation_state: String
            let secrets: [String: RecoveryJSONValue]
            let secret_conflicts: Int
            let historical_attempts: Int
        }
        let files: [String: String]
        let orders: [[Int]]
        let expected: Body
    }

    static let dir = RecoveryCryptoTests.sharedRecovery.appendingPathComponent("merge")

    static func load() throws -> (Expected, [Int: RecoveryPayload]) {
        let exp = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: dir.appendingPathComponent("expected.json")))
        var payloads: [Int: RecoveryPayload] = [:]
        for (k, v) in exp.files {
            payloads[Int(k)!] = try RecoveryPayload.decode(Data(contentsOf: dir.appendingPathComponent(v)))
        }
        return (exp, payloads)
    }

    static func run(_ order: [Int], _ payloads: [Int: RecoveryPayload]) -> RecoveryMergeState {
        order.reduce(RecoveryMergeState()) { RecoveryMerge.apply(payloads[$1]!, to: $0).state }
    }

    /// Todas las permutaciones de subconjuntos no vacíos de {1,2,3} que contienen la 3: 1 + 4 + 6 = 11.
    static func ordersWithThree() -> [[Int]] {
        func perms(_ items: [Int]) -> [[Int]] {
            items.count <= 1 ? [items] : items.indices.flatMap { i -> [[Int]] in
                var rest = items; let head = rest.remove(at: i)
                return perms(rest).map { [head] + $0 }
            }
        }
        let subsets: [[Int]] = [[3], [1, 3], [2, 3], [1, 2, 3]]
        return subsets.flatMap(perms)
    }

    static func secret(_ s: RecoveryPayload.Session, _ path: String) -> RecoveryJSONValue {
        switch path {
        case "activation.receiver_id_used": s.activation.receiverIDUsed.map { .integer(Int64($0)) } ?? .null
        case "activation.response_hex": s.activation.responseHex.map(RecoveryJSONValue.string) ?? .null
        case "ble.address": s.ble.address.map(RecoveryJSONValue.string) ?? .null
        case "ble.pin_hex": s.ble.pinHex.map(RecoveryJSONValue.string) ?? .null
        case "auth.k_auth_hex": s.auth.kAuthHex.map(RecoveryJSONValue.string) ?? .null
        default: .null
        }
    }

    @Test("expected.json en los 11 órdenes que incluyen la copia 3")
    func expectedOrders() throws {
        let (exp, payloads) = try Self.load()
        let orders = Self.ordersWithThree()
        #expect(orders.count == 11)
        for listed in exp.orders { #expect(orders.contains(listed), "orden \(listed) del fixture cubierto") }
        let e = exp.expected
        for order in orders {
            let st = Self.run(order, payloads)
            let s = try #require(st.sessions[e.session_id], "\(order)")
            #expect(s.activation.state.rawValue == e.activation_state, "\(order)")
            #expect(s.sequence == e.sequence, "\(order)")
            #expect(s.attemptID == e.attempt_id, "\(order)")
            #expect(s == payloads[e.from_file]!.sessions[0], "\(order): copia entera de la sequence \(e.from_file)")
            for (path, want) in e.secrets { #expect(Self.secret(s, path) == want, "\(order) \(path)") }
            #expect(st.conflicts.count == e.secret_conflicts, "\(order)")
            #expect(st.historical.count == e.historical_attempts, "\(order)")
        }
    }

    @Test("1→2 sin la 3 termina en response_saved")
    func withoutThree() throws {
        let (_, payloads) = try Self.load()
        let st = Self.run([1, 2], payloads)
        let s = try #require(st.sessions.values.first)
        #expect(s.activation.state == .responseSaved)
        #expect(s.sequence == 2)
        #expect(st.conflicts.isEmpty && st.historical.isEmpty)
    }

    @Test("secretos contradictorios con sequence remota mayor: conflicto y local intacta")
    func contradictorySecretsHigherSequence() throws {
        let (_, payloads) = try Self.load()
        let local = Self.run([3], payloads)
        var remote = payloads[3]!
        remote.sessions[0].sequence = 9
        remote.sessions[0].ble.pinHex = "ffffffff"
        remote.sessions[0].auth.kAuthHex = String(repeating: "ee", count: 16)
        let (after, decisions) = RecoveryMerge.apply(remote, to: local)
        #expect(decisions == [.secretConflict(sessionID: remote.sessions[0].sessionID, fields: ["ble.pin_hex", "auth.k_auth_hex"])])
        #expect(after.sessions == local.sessions, "la local no cambia")
        #expect(after.conflicts.count == 1)
        #expect(after.conflicts[0].local == payloads[3]!.sessions[0])
        #expect(after.conflicts[0].remote == remote.sessions[0], "la remota se conserva íntegra")
        // Idempotente: repetir la misma copia conflictiva no añade otra.
        let (again, d2) = RecoveryMerge.apply(remote, to: after)
        #expect(again.conflicts.count == 1)
        #expect(d2 == [.duplicateIgnored(sessionID: remote.sessions[0].sessionID)])
        // Sequence menor con secreto distinto: también conflicto (en cualquier sequence).
        var older = payloads[2]!
        older.sessions[0].activation.responseHex = String(repeating: "01", count: 19)
        let (_, d3) = RecoveryMerge.apply(older, to: local)
        #expect(d3 == [.secretConflict(sessionID: older.sessions[0].sessionID, fields: ["activation.response_hex"])])
    }

    @Test("null frente a valor no es conflicto: la copia posterior se toma entera")
    func nullVersusValue() throws {
        let (_, payloads) = try Self.load()
        let local = Self.run([1], payloads)
        let (after, decisions) = RecoveryMerge.apply(payloads[3]!, to: local)
        #expect(decisions == [.replacedByRemote(sessionID: payloads[3]!.sessions[0].sessionID, fromSequence: 1, toSequence: 3)])
        #expect(after.conflicts.isEmpty)
        // Y al revés: la copia anterior con null no retrocede ni es conflicto.
        let (back, d2) = RecoveryMerge.apply(payloads[1]!, to: after)
        #expect(d2 == [.keptLocal(sessionID: payloads[3]!.sessions[0].sessionID)])
        #expect(back == after)
    }

    @Test("attempt_id distinto → intento histórico; la activa no cambia")
    func otherAttempt() throws {
        let (_, payloads) = try Self.load()
        let local = Self.run([3], payloads)
        var other = payloads[1]!
        other.sessions[0].attemptID = "11111111-2222-4333-8444-555555555555"
        other.sessions[0].sequence = 99
        let (after, decisions) = RecoveryMerge.apply(other, to: local)
        #expect(decisions == [.historicalAttempt(sessionID: other.sessions[0].sessionID, attemptID: "11111111-2222-4333-8444-555555555555")])
        #expect(after.sessions == local.sessions)
        #expect(after.historical.count == 1)
        let (again, _) = RecoveryMerge.apply(other, to: after)
        #expect(again.historical.count == 1, "idempotente")
    }

    @Test("misma sequence, otro exportador: desempata updated_at_utc si no hay conflicto")
    func tieBreak() throws {
        let (_, payloads) = try Self.load()
        let local = Self.run([3], payloads)
        var other = payloads[3]!
        other.exportedByAppID = "com.otalvaro.lingoscan.astra"
        other.sessions[0].updatedAtUTC = "2026-10-27T12:05:00Z"
        other.sessions[0].auth.lastLifeCount = 5
        let (after, _) = RecoveryMerge.apply(other, to: local)
        #expect(after.sessions.values.first?.auth.lastLifeCount == 5)
        // Mismo exportador y misma sequence: se conserva la local.
        var same = payloads[3]!
        same.sessions[0].updatedAtUTC = "2026-10-27T12:05:00Z"
        same.sessions[0].auth.lastLifeCount = 7
        let (kept, d) = RecoveryMerge.apply(same, to: local)
        #expect(d == [.keptLocal(sessionID: same.sessions[0].sessionID)])
        #expect(kept.sessions.values.first?.auth.lastLifeCount == 1)
    }

    @Test("equivalencia por sensor_serial_hash + activación ±120 s")
    func equivalence() throws {
        let (_, payloads) = try Self.load()
        let local = Self.run([3], payloads)
        let canonical = payloads[3]!.sessions[0].sessionID
        var alias = payloads[3]!
        alias.sessions[0].sessionID = "99999999-8888-4777-8666-555555555555"
        alias.sessions[0].activation.activationTimeEpochS! += 120
        alias.sessions[0].sequence = 4
        let (after, d) = RecoveryMerge.apply(alias, to: local)
        #expect(d == [.replacedByRemote(sessionID: canonical, fromSequence: 3, toSequence: 4)])
        #expect(after.aliases["99999999-8888-4777-8666-555555555555"] == canonical)
        #expect(after.sessions.count == 1)

        var far = alias
        far.sessions[0].activation.activationTimeEpochS! += 1
        let (separate, d2) = RecoveryMerge.apply(far, to: local)
        #expect(d2 == [.importedNew(sessionID: "99999999-8888-4777-8666-555555555555")])
        #expect(separate.sessions.count == 2)

        // Sin tiempo de activación conocido no se infiere equivalencia por hash.
        let prepared = Self.run([1], payloads)
        var noTime = payloads[1]!
        noTime.sessions[0].sessionID = "99999999-8888-4777-8666-555555555555"
        let (_, d3) = RecoveryMerge.apply(noTime, to: prepared)
        #expect(d3 == [.importedNew(sessionID: "99999999-8888-4777-8666-555555555555")])
    }
}
