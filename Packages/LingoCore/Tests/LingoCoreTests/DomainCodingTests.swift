import Foundation
import Testing
@testable import LingoCore

struct DomainCodingTests {
    @Test func recordIDMakeAndParse() throws {
        let sid = "3fa85f64-5717-4562-b3fc-2c963f66afa6"
        let text = RecordID.make(sessionID: sid, analyte: .glucose, lifeCount: 63)
        #expect(text == "3fa85f64-5717-4562-b3fc-2c963f66afa6:glucose:63")
        let parsed = try #require(RecordID(parsing: text))
        #expect(parsed.sessionID == sid && parsed.analyte == .glucose && parsed.lifeCount == 63)
        #expect(parsed.rawValue == text)
        #expect(RecordID(parsing: sid + ":glucose:0")?.lifeCount == 0)
        #expect(RecordID(parsing: sid + ":glucose:065535")?.lifeCount == nil)  // cero a la izquierda
        #expect(RecordID(parsing: sid + ":glucose:063") == nil)
        #expect(RecordID(parsing: sid + ":glucose:65536") == nil)
        #expect(RecordID(parsing: sid + ":sodium:1") == nil)
        #expect(RecordID(parsing: sid.uppercased() + ":glucose:1") == nil)
        #expect(RecordID(parsing: sid + ":glucose") == nil)
        #expect(RecordID(parsing: sid + ":glucose:-1") == nil)
    }

    @Test func measuredAtIsActivationPlusSixtyTimesLifeCount() {
        let t = MeasuredAt.compute(activationEpoch: 1_793_102_400, lifeCount: 63)
        #expect(t.epochSeconds == 1_793_102_400 + 3780)
        #expect(t.rfc3339 == "2026-10-27T13:03:00Z")
    }

    @Test func utcInstantRFC3339() {
        #expect(UTCInstant(epochSeconds: 0).rfc3339 == "1970-01-01T00:00:00Z")
        #expect(UTCInstant(rfc3339: "2026-10-27T15:04:05Z")?.epochSeconds == 1_793_113_445)
        #expect(UTCInstant(rfc3339: "2024-02-29T23:59:59Z")?.rfc3339 == "2024-02-29T23:59:59Z")
        #expect(UTCInstant(rfc3339: "2026-02-31T00:00:00Z") == nil)
        #expect(UTCInstant(rfc3339: "2026-10-27T15:04:05+00:00") == nil)
        #expect(UTCInstant(rfc3339: "2026-10-27T15:04:05.123Z") == nil)
    }

    @Test func readingJSONWritesExplicitNullsAndRoundTrips() throws {
        let session = TestSupport.session()
        let r = TestSupport.reading(session, lc: 2, raw: TestSupport.raw(qualityFlag: true), origin: .live)
        let data = try JSONEncoder().encode(r)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["record_id", "source_record_id", "session_id", "life_count", "analyte", "unit", "measured_at_utc",
                    "received_at_utc", "tz_at_capture", "origin", "value", "raw", "eligibility", "decoder", "revision",
                    "deleted", "imported_from", "synthetic"] {
            #expect(object.keys.contains(key), "falta \(key)")
        }
        #expect(object["value"] is NSNull)
        #expect(object["source_record_id"] is NSNull)
        let raw = try #require(object["raw"] as? [String: Any])
        #expect(raw["capped"] is NSNull && raw["quality_flag"] as? Bool == true)
        let eligibility = try #require(object["eligibility"] as? [String: Any])
        #expect(eligibility["status"] as? String == "excluded")
        #expect(eligibility["reason"] as? String == "quality_flag")
        #expect(eligibility["policy_id"] as? String == "lingoscan-v1")
        let back = try JSONDecoder().decode(GlucoseReading.self, from: data)
        #expect(back == r)
    }

    @Test func eligibilityDecodingEnforcesReasonInvariant() {
        let bad = #"{"status":"eligible","reason":"warm_up","policy_id":"x","policy_version":"1"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Eligibility.self, from: Data(bad.utf8)) }
        let bad2 = #"{"status":"excluded","reason":null,"policy_id":"x","policy_version":"1"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Eligibility.self, from: Data(bad2.utf8)) }
    }

    @Test func sessionJSONHasContractKeysAndNoSecrets() throws {
        var s = TestSupport.session()
        s.aliases = [SessionAlias(sessionID: TestSupport.newID(), appID: "com.otalvaro.lingoscan.astra",
                                  archiveID: TestSupport.newID(), recordedAt: UTCInstant(epochSeconds: 1_793_113_445))]
        let data = try JSONEncoder().encode(s)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["session_id", "sensor_family", "product_type", "security_version", "sensor_serial_hash", "aliases",
                    "synthetic", "warmup_minutes", "wear_minutes", "activation_time_epoch_s", "activation_time_source",
                    "activated_at_utc", "activated_by_app_id", "activation_source", "receiver_id_present",
                    "ended_at_utc", "end_reason", "last_life_count", "revision", "imported_from", "activation_state"] {
            #expect(object.keys.contains(key), "falta \(key)")
        }
        for forbidden in ["sensor_serial", "receiver_id", "pin_hex", "k_auth_hex", "ble", "auth",
                          "sensor_certificate_hex", "patch_info_hex", "mac"] {
            #expect(!object.keys.contains(forbidden))
        }
        #expect(object["activated_at_utc"] as? String == "2026-10-27T12:00:00Z")
        #expect(try JSONDecoder().decode(SensorSessionRecord.self, from: data) == s)
    }

    @Test func eventLedgerConflictCoding() throws {
        let e = DiaryEvent(eventID: TestSupport.newID(), kind: .meal, at: UTCInstant(epochSeconds: 1_793_102_400),
                           tz: TestSupport.tz, carbsG: 45, text: "Arroz", createdAt: UTCInstant(epochSeconds: 1_793_102_400),
                           updatedAt: UTCInstant(epochSeconds: 1_793_102_400), editID: TestSupport.newID(),
                           editedByAppID: TestSupport.appID, synthetic: true)
        let eo = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any])
        #expect(eo["parent_edit_id"] is NSNull && eo["duration_min"] is NSNull && eo["edited_by_app_id"] != nil)
        #expect(try JSONDecoder().decode(DiaryEvent.self, from: JSONEncoder().encode(e)) == e)

        let l = HealthLedgerEntry(attemptID: TestSupport.newID(), subjectID: "x", subjectKind: .glucose,
                                  writerAppID: TestSupport.appID, syncIdentifier: "x", syncVersion: 1,
                                  exportedAt: UTCInstant(epochSeconds: 1), result: .failed)
        #expect(try JSONDecoder().decode(HealthLedgerEntry.self, from: JSONEncoder().encode(l)) == l)

        #expect(ConflictResolution.allCases.map(\.rawValue).sorted() ==
                ["aliased", "divergent", "kept_local", "lineage_unknown", "merged", "policy_divergence", "took_remote"])
        let c = ConflictRecord(at: UTCInstant(epochSeconds: 5), kind: .reading, id: "r", resolution: .merged,
                               local: try JSONValue.encoding(l), remote: .object(["a": .int(1), "b": .null]))
        #expect(try JSONDecoder().decode(ConflictRecord.self, from: JSONEncoder().encode(c)) == c)
        #expect(ReadingOrigin.allCases.sorted { $0.precedence > $1.precedence }.map(\.rawValue) ==
                ["live", "backfill_fast", "backfill_history", "embedded_history", "import"])
    }
}
