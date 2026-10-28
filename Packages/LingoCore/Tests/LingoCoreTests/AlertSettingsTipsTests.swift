import Foundation
import Testing
@testable import LingoCore

/// `includeTips` (T-25): activado por defecto y tolerante a JSON anteriores sin el campo.
struct AlertSettingsTipsTests {
    @Test func includeTipsDefaultsOnAndDecodesFromOldJSON() throws {
        #expect(AlertSettings.default.includeTips)
        let old = Data(#"{"isEnabled":true,"rateThreshold":2.0}"#.utf8)
        let decoded = try JSONDecoder().decode(AlertSettings.self, from: old)
        #expect(decoded.includeTips)
        var off = decoded
        off.includeTips = false
        let roundTrip = try JSONDecoder().decode(AlertSettings.self, from: JSONEncoder().encode(off))
        #expect(!roundTrip.includeTips)
    }
}
