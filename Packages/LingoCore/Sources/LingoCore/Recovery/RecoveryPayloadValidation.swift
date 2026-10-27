import Foundation

extension RecoveryPayload {
    /// Patrones y cardinalidades de `schemas/recovery_payload.schema.json` que el tipado no cubre.
    public func validate() throws {
        guard payloadVersion == Self.currentVersion else { throw RecoveryPayloadError.unsupportedVersion(payloadVersion) }
        try RecoveryFormat.check(RecoveryFormat.isDateTimeUTC(exportedAtUTC), "exported_at_utc", "fecha UTC con Z y segundos")
        try RecoveryFormat.check(!exportedByAppID.isEmpty, "exported_by_app_id", "vacío")

        let identity = appIdentity
        try RecoveryFormat.check(!identity.label.isEmpty, "app_identity.label", "vacío")
        try RecoveryFormat.check(!identity.productTypes.isEmpty, "app_identity.product_types", "lista vacía")
        try RecoveryFormat.check(!identity.securityVersions.isEmpty, "app_identity.security_versions", "lista vacía")
        try RecoveryFormat.optional(identity.certificateSHA256, "app_identity.certificate_sha256", RecoveryFormat.isSHA256)
        try RecoveryFormat.optional(identity.patchSigningKeySHA256, "app_identity.patch_signing_key_sha256", RecoveryFormat.isSHA256)
        if identity.includeMaterial {
            guard let m = identity.material else {
                throw RecoveryPayloadError.invalid(path: "app_identity.material", reason: "include_material true exige material")
            }
            try RecoveryFormat.check(RecoveryFormat.isHex(m.privateKeyHex), "app_identity.material.private_key_hex", "hex")
            try RecoveryFormat.check(RecoveryFormat.isHex(m.certificateHex), "app_identity.material.certificate_hex", "hex")
            try RecoveryFormat.check(RecoveryFormat.isHex(m.patchSigningPublicKeyHex), "app_identity.material.patch_signing_public_key_hex", "hex")
        } else {
            try RecoveryFormat.check(identity.material == nil, "app_identity.material", "debe ser null sin include_material")
        }

        try RecoveryFormat.check(!sessions.isEmpty, "sessions", "al menos una sesión")
        for (index, session) in sessions.enumerated() {
            try session.validate(path: "sessions.\(index)")
        }
    }
}

extension RecoveryPayload.Session {
    func validate(path p: String) throws {
        try RecoveryFormat.check(RecoveryFormat.isUUIDv4(sessionID), "\(p).session_id", "UUID v4 en minúsculas")
        try RecoveryFormat.optional(sensorSerial, "\(p).sensor_serial") { s in
            s.utf8.count == 9 && s.utf8.allSatisfy { (0x21...0x7e).contains($0) }
        }
        try RecoveryFormat.check(RecoveryFormat.isSHA256(sensorSerialHash), "\(p).sensor_serial_hash", "SHA-256 hex")
        if let productType { try RecoveryFormat.check((0...255).contains(productType), "\(p).product_type", "0...255") }
        if let securityVersion { try RecoveryFormat.check((0...65535).contains(securityVersion), "\(p).security_version", "0...65535") }
        try RecoveryFormat.optional(firmwareHex, "\(p).firmware_hex") { RecoveryFormat.isHex($0, bytes: 4) }
        try RecoveryFormat.optional(patchInfoHex, "\(p).patch_info_hex") { RecoveryFormat.isHex($0) }
        try RecoveryFormat.check(RecoveryFormat.isUUIDv4(attemptID), "\(p).attempt_id", "UUID v4 en minúsculas")
        try RecoveryFormat.check(sequence >= 1, "\(p).sequence", "≥ 1")
        try RecoveryFormat.check(RecoveryFormat.isDateTimeUTC(updatedAtUTC), "\(p).updated_at_utc", "fecha UTC")

        try RecoveryFormat.optional(activation.attemptedAtUTC, "\(p).activation.attempted_at_utc", RecoveryFormat.isDateTimeUTC)
        if let t = activation.activationTimeEpochS { try RecoveryFormat.check(t >= 0, "\(p).activation.activation_time_epoch_s", "≥ 0") }
        try RecoveryFormat.optional(activation.commandHex, "\(p).activation.command_hex") { RecoveryFormat.isHex($0) }
        try RecoveryFormat.optional(activation.responseHex, "\(p).activation.response_hex") { RecoveryFormat.isHex($0, bytes: 19) }

        try RecoveryFormat.optional(ble.address, "\(p).ble.address", RecoveryFormat.isMACAddress)
        try RecoveryFormat.optional(ble.pinHex, "\(p).ble.pin_hex") { RecoveryFormat.isHex($0, bytes: 4) }

        try RecoveryFormat.optional(auth.kAuthHex, "\(p).auth.k_auth_hex") { RecoveryFormat.isHex($0, bytes: 16) }
        try RecoveryFormat.optional(auth.kAuthCapturedAtUTC, "\(p).auth.k_auth_captured_at_utc", RecoveryFormat.isDateTimeUTC)
        try RecoveryFormat.optional(auth.lastSuccessfulHandshakeUTC, "\(p).auth.last_successful_handshake_utc", RecoveryFormat.isDateTimeUTC)
        if let lc = auth.lastLifeCount { try RecoveryFormat.check((0...65535).contains(lc), "\(p).auth.last_life_count", "0...65535") }
        try RecoveryFormat.optional(sensorCertificateHex, "\(p).sensor_certificate_hex") { RecoveryFormat.isHex($0) }
    }
}
