import XCTest
@testable import RoundWhiteDiscKit

/// T-03: Lingo data plane (docs/PROTOCOLO_LINGO.md §2.3, §3, §4, §6, §7, §8).
/// Realtime vectors come from `Fixtures/lingo_realtime_vectors.json`, loaded by
/// `#filePath` (no `resources` in the test target, see CCMVectorTests).
final class LingoDataPlaneTests: XCTestCase {

    // MARK: - Fixture

    private struct Expected: Decodable {
        let channel0_type: UInt8
        let channel1_type: UInt8
        let glucose_channel: Int?
        let life_count: UInt16
        let historic_life_count: UInt16
        let glucose_valid: Bool
        let capped_mgdl: UInt16?
        let uncapped_mgdl: UInt16?
        let historic_capped_mgdl: UInt16?
        let historic_uncapped_mgdl: UInt16?
        let rate: Int16
        let trend: UInt8
        let range_bits: UInt8
        let temperature_valid: Bool
        let temperature_centi: UInt16?
    }

    private struct Vector: Decodable {
        let id: String
        let group: String
        let source: String
        let plaintext_hex: String
        let expected: Expected
    }

    private struct File: Decodable {
        let format: Int
        let vectors: [Vector]
    }

    private func loadVectors() throws -> [Vector] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/lingo_realtime_vectors.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.format, 1)
        return file.vectors
    }

    private func vector(_ id: String) throws -> Data {
        let v = try XCTUnwrap(try loadVectors().first { $0.id == id })
        return hexData(v.plaintext_hex)
    }

    private func hexData(_ hex: String) -> Data {
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    private func syntheticCrypto() throws -> DataPlaneCrypto {
        // Synthetic session material, not from any sensor.
        try DataPlaneCrypto(
            kEnc: Data((0..<16).map { UInt8($0) }),
            ivEnc: Data([0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7])
        )
    }

    // MARK: - Realtime 51 B: the 12 real vectors (§8.1-§8.3)

    func testTwelveRealtimeVectorsMatchExpectedFields() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.count, 12)
        XCTAssertEqual(vectors.filter { $0.group == "warmup" }.count, 4)
        XCTAssertEqual(vectors.filter { $0.group == "warm" }.count, 2)
        XCTAssertEqual(vectors.filter { $0.group == "trend" }.count, 6)

        for v in vectors {
            let data = hexData(v.plaintext_hex)
            let r = try LingoRealtimeReading.parse(data)
            let e = v.expected
            let ctx = "\(v.id) (\(v.source))"
            XCTAssertEqual(r.raw, data, ctx)
            XCTAssertEqual(r.lifeCount, e.life_count, ctx)
            XCTAssertEqual(r.historicLifeCount, e.historic_life_count, ctx)
            XCTAssertEqual(r.analyteTypes.map(\.code), [e.channel0_type, e.channel1_type], ctx)
            XCTAssertEqual(r.channel, e.glucose_channel, ctx)
            XCTAssertEqual(r.isGlucoseValid, e.glucose_valid, ctx)
            XCTAssertEqual(r.qualityFlag, !e.glucose_valid, ctx)
            XCTAssertEqual(r.cappedMgDL, e.capped_mgdl, ctx)
            XCTAssertEqual(r.uncappedMgDL, e.uncapped_mgdl, ctx)
            XCTAssertEqual(r.historicCappedMgDL, e.historic_capped_mgdl, ctx)
            XCTAssertEqual(r.historicUncappedMgDL, e.historic_uncapped_mgdl, ctx)
            XCTAssertEqual(r.rateCentiRaw, e.rate, ctx)
            XCTAssertEqual(r.rateCenti, e.rate == Int16.min ? nil : e.rate, ctx)
            XCTAssertEqual(r.trend, e.trend, ctx)
            XCTAssertEqual(r.rangeBits, e.range_bits, ctx)
            XCTAssertEqual(r.isTemperatureValid, e.temperature_valid, ctx)
            XCTAssertEqual(r.temperatureCentiCelsius, e.temperature_centi, ctx)
            XCTAssertEqual(r.reserved, data.subdata(in: 35..<51), ctx)
            XCTAssertEqual(r.reserved.count, 16, ctx)
            XCTAssertEqual(r.blocks.count, 2, ctx)
            XCTAssertEqual(r.glucose, r.blocks[1], ctx)
            XCTAssertEqual(r.cappedRaw, LingoBytes.u16(data, 19), ctx)
        }
    }

    func testWarmupVectorsNeverYieldANumber() throws {
        for v in try loadVectors() where v.group == "warmup" {
            let r = try LingoRealtimeReading(plaintext: hexData(v.plaintext_hex))
            let block = try XCTUnwrap(r.glucose)
            XCTAssertTrue(block.capped.qualityFlag)
            XCTAssertNil(block.capped.mgDL)
            XCTAssertNil(block.uncapped.mgDL)
            XCTAssertNil(block.historicCapped.mgDL)
            XCTAssertNil(block.historicUncapped.mgDL)
            XCTAssertNil(block.rateCenti)
            XCTAssertEqual(block.trend, 0)
            XCTAssertTrue(block.actionable) // trend byte 0x08
        }
        // lc 1-3 carry payload 0x20 under the flag; lc 4 is 0x8000.
        XCTAssertEqual(try LingoRealtimeReading(plaintext: vector("warmup_prior1")).cappedRaw, 0x8020)
        XCTAssertEqual(try LingoRealtimeReading(plaintext: vector("warmup_live2")).cappedRaw, 0x8000)
    }

    func testWarmFrameExposesRawWordsAndUnusedFields() throws {
        let r = try LingoRealtimeReading(plaintext: vector("warm_lc63"))
        let block = try XCTUnwrap(r.glucose)
        XCTAssertEqual(block.cappedRaw, 0x40C9)
        XCTAssertEqual(block.capped.rangeBits, 2)
        XCTAssertFalse(block.capped.bit12)
        XCTAssertEqual(block.uncappedRaw, 0x00D0)
        XCTAssertEqual(block.historicCappedRaw, 0x8000)
        XCTAssertEqual(block.extendedCode, 0)
        XCTAssertEqual(block.projected, 0xFFFF)
        XCTAssertEqual(block.trendByte, 0x08)
        XCTAssertEqual(block.raw.count, 15)
        // Inactive channel 0 is still exposed raw.
        XCTAssertEqual(r.blocks[0].cappedRaw, 0x8000)
        XCTAssertEqual(r.analyteTypes, [.inactive, .glucose])
    }

    // MARK: - Channel selection (§8.3, §8.4)

    func testSwappingAnalyteBlocksGivesSameResult() throws {
        for v in try loadVectors() where v.group == "trend" {
            let original = hexData(v.plaintext_hex)
            var swapped = original
            swapped.replaceSubrange(4..<19, with: original.subdata(in: 19..<34))
            swapped.replaceSubrange(19..<34, with: original.subdata(in: 4..<19))
            swapped[34] = 0x01
            // Contaminate the now inactive channel 1 (T:183-185).
            swapped[21] = 0x7b
            swapped[22] = 0x00
            swapped[29] = 0x0c

            let a = try LingoRealtimeReading(plaintext: original)
            let b = try LingoRealtimeReading(plaintext: swapped)
            XCTAssertEqual(b.channel, 0, v.id)
            XCTAssertEqual(b.analyteTypes, [.glucose, .inactive], v.id)
            XCTAssertEqual(b.rateCentiRaw, a.rateCentiRaw, v.id)
            XCTAssertEqual(b.trend, a.trend, v.id)
            XCTAssertEqual(b.cappedMgDL, a.cappedMgDL, v.id)
            XCTAssertEqual(b.uncappedMgDL, a.uncappedMgDL, v.id)
            XCTAssertEqual(b.historicCappedMgDL, a.historicCappedMgDL, v.id)
            XCTAssertEqual(b.rangeBits, a.rangeBits, v.id)
            XCTAssertEqual(b.qualityFlag, a.qualityFlag, v.id)
            XCTAssertEqual(b.glucose, a.glucose, v.id)
        }
    }

    func testGlucoseOnChannelZero() throws {
        var buf = try vector("warm_lc58")
        buf[4] = buf[19]
        buf[5] = buf[20]
        buf[19] = 0x00
        buf[20] = 0x80
        buf[34] = 0x01
        let r = try LingoRealtimeReading(plaintext: buf)
        XCTAssertEqual(r.channel, 0)
        XCTAssertEqual(r.analyteTypes, [.glucose, .inactive])
        XCTAssertEqual(r.cappedMgDL, 201)
        XCTAssertEqual(r.qualityFlag, false)
        XCTAssertEqual(r.rangeBits, 2)
    }

    func testFirstGlucoseChannelWinsWhenBothAreGlucose() throws {
        var buf = try vector("trend_167")
        buf.replaceSubrange(4..<19, with: try vector("trend_169").subdata(in: 19..<34))
        buf[34] = 0x11
        let r = try LingoRealtimeReading(plaintext: buf)
        XCTAssertEqual(r.channel, 0)
        XCTAssertEqual(r.cappedMgDL, 158)
        XCTAssertEqual(r.rateCentiRaw, 256)
    }

    func testRateAndTrendSyntheticCases() throws {
        var buf = try vector("trend_166")
        buf[21] = 150
        buf[22] = 0
        buf[29] = 0xfc
        var r = try LingoRealtimeReading(plaintext: buf)
        XCTAssertEqual(r.rateCentiRaw, 150)
        XCTAssertEqual(r.trend, 4)
        XCTAssertTrue(r.actionable)
        buf[29] = 6
        r = try LingoRealtimeReading(plaintext: buf)
        XCTAssertEqual(r.trend, 0)
        XCTAssertFalse(r.actionable)
        buf[29] = 7
        r = try LingoRealtimeReading(plaintext: buf)
        XCTAssertEqual(r.trend, 0)
    }

    func testKetoneLactateTypeMapHasNoGlucose() throws {
        var buf = try vector("trend_166")
        _ = try LingoRealtimeReading(plaintext: buf) // previous parse must not leak
        buf[34] = 0x32
        let r = try LingoRealtimeReading(plaintext: buf)
        XCTAssertEqual(r.analyteTypes, [.ketone, .lactate])
        XCTAssertNil(r.channel)
        XCTAssertNil(r.glucose)
        XCTAssertFalse(r.hasGlucoseChannel)
        XCTAssertFalse(r.isGlucoseValid)
        XCTAssertNil(r.qualityFlag)
        XCTAssertNil(r.rangeBits)
        XCTAssertNil(r.cappedMgDL)
        XCTAssertNil(r.uncappedMgDL)
        XCTAssertEqual(r.rateCentiRaw, -32768)
        XCTAssertNil(r.rateCenti)
        XCTAssertEqual(r.trend, 0)
        XCTAssertEqual(LingoAnalyteType(code: 7), .unknown(7))
    }

    func testTemperatureValues() throws {
        for raw: UInt16 in [0, 3054, 32767, 0x8000, 32769, 65535] {
            var buf = Data(count: 51)
            buf[37] = UInt8(raw & 0xff)
            buf[38] = UInt8(raw >> 8)
            let r = try LingoRealtimeReading(plaintext: buf)
            XCTAssertEqual(r.isTemperatureValid, raw != 0x8000)
            XCTAssertEqual(r.temperatureCentiCelsius, raw == 0x8000 ? nil : raw)
            XCTAssertEqual(r.temperatureRaw, raw)
        }
    }

    func testRealtimeRejectsWrongSizes() throws {
        let data = try vector("warm_lc58")
        for size in [50, 52, 29, 0] {
            let input = size <= 51 ? data.prefix(size) : data + Data([0x00])
            XCTAssertThrowsError(try LingoRealtimeReading(plaintext: Data(input))) { error in
                XCTAssertEqual(error as? LingoRealtimeReadingError, .wrongPlaintextSize(size))
            }
        }
    }

    func testRealtimeParsesFromSlicedData() throws {
        let data = try vector("warm_lc63")
        let padded = Data([0xEE, 0xEE]) + data
        let slice = padded[2...]
        let r = try LingoRealtimeReading(plaintext: slice)
        XCTAssertEqual(r.lifeCount, 63)
        XCTAssertEqual(r.uncappedMgDL, 208)
    }

    // MARK: - Assembler (§2.3)

    private func lingoFrame(sequence: UInt16 = 1) throws -> Data {
        try syntheticCrypto().encrypt(plaintext: vector("warm_lc58"), sequence: sequence, kind: .kind3).raw
    }

    func testAssemblerTargetLengthsPerFamily() {
        XCTAssertEqual(DataPlaneNotificationAssembler(family: .lingo).targetLength, 57)
        XCTAssertEqual(DataPlaneNotificationAssembler(family: .libre3).targetLength, 35)
        XCTAssertEqual(DataPlaneNotificationAssembler().targetLength, 35)
    }

    func testAssemblerAcceptsAnyCutPoint() throws {
        let frame = try lingoFrame()
        XCTAssertEqual(frame.count, 57)
        for cut in [1, 15, 20, 28, 56] {
            let assembler = DataPlaneNotificationAssembler(family: .lingo)
            XCTAssertEqual(
                assembler.ingest(fragment: frame.prefix(cut), channel: .glucoseData),
                .pending(accumulated: cut)
            )
            XCTAssertEqual(assembler.pendingByteCount, cut)
            XCTAssertEqual(
                assembler.ingest(fragment: frame.suffix(from: cut), channel: .glucoseData),
                .complete(frame),
                "cut \(cut)"
            )
            XCTAssertEqual(assembler.pendingByteCount, 0)
            XCTAssertEqual(assembler.discardedFrameCount, 0)
        }
    }

    func testAssemblerAcceptsThreeAndManyFragments() throws {
        let frame = try lingoFrame()
        let assembler = DataPlaneNotificationAssembler(family: .lingo)
        XCTAssertNil(assembler.feed(fragment: frame.subdata(in: 0..<20), channel: .glucoseData))
        XCTAssertNil(assembler.feed(fragment: frame.subdata(in: 20..<40), channel: .glucoseData))
        XCTAssertEqual(assembler.feed(fragment: frame.subdata(in: 40..<57), channel: .glucoseData), frame)

        for i in 0..<56 {
            XCTAssertNil(assembler.feed(fragment: frame.subdata(in: i..<(i + 1)), channel: .glucoseData))
        }
        XCTAssertEqual(assembler.feed(fragment: frame.subdata(in: 56..<57), channel: .glucoseData), frame)
    }

    func testAssemblerDuplicateFragmentOverflowsThenRecovers() throws {
        let frame = try lingoFrame()
        let assembler = DataPlaneNotificationAssembler(family: .lingo)
        let first = frame.subdata(in: 0..<20)
        XCTAssertEqual(assembler.ingest(fragment: first, channel: .glucoseData), .pending(accumulated: 20))
        XCTAssertEqual(assembler.ingest(fragment: first, channel: .glucoseData), .pending(accumulated: 40))
        XCTAssertEqual(
            assembler.ingest(fragment: frame.subdata(in: 20..<40), channel: .glucoseData),
            .overflow(accumulated: 40, fragmentLength: 20)
        )
        XCTAssertEqual(assembler.discardedFrameCount, 1)
        XCTAssertEqual(assembler.lastDiscard, .overflow(accumulated: 40, fragmentLength: 20))
        XCTAssertEqual(assembler.pendingByteCount, 0)
        // Next frame assembles cleanly after the reset.
        XCTAssertNil(assembler.feed(fragment: frame.subdata(in: 0..<28), channel: .glucoseData))
        XCTAssertEqual(assembler.feed(fragment: frame.subdata(in: 28..<57), channel: .glucoseData), frame)
    }

    func testAssemblerExcessAndEmptyFragments() throws {
        let frame = try lingoFrame()
        let assembler = DataPlaneNotificationAssembler(family: .lingo)
        XCTAssertEqual(
            assembler.ingest(fragment: frame + Data([0x00]), channel: .glucoseData),
            .overflow(accumulated: 0, fragmentLength: 58)
        )
        XCTAssertEqual(assembler.ingest(fragment: frame.prefix(10), channel: .glucoseData), .pending(accumulated: 10))
        XCTAssertEqual(assembler.ingest(fragment: Data(), channel: .glucoseData), .emptyFragment(accumulated: 10))
        XCTAssertEqual(assembler.pendingByteCount, 0)
        XCTAssertEqual(assembler.discardedFrameCount, 2)
        XCTAssertEqual(assembler.feed(fragment: frame, channel: .glucoseData), frame)
    }

    func testAssemblerLibre3PathAndPassthrough() throws {
        let assembler = DataPlaneNotificationAssembler(family: .libre3)
        let prefix = Data(repeating: 0x11, count: 15)
        let suffix = Data(repeating: 0x22, count: 20)
        XCTAssertNil(assembler.feed(fragment: prefix, channel: .glucoseData))
        XCTAssertEqual(assembler.feed(fragment: suffix, channel: .glucoseData), prefix + suffix)
        XCTAssertEqual(assembler.feed(fragment: prefix + suffix, channel: .glucoseData), prefix + suffix)
        let status = Data(repeating: 0x33, count: 20)
        XCTAssertEqual(assembler.ingest(fragment: status, channel: .patchStatus), .complete(status))
        XCTAssertEqual(assembler.ingest(fragment: Data(), channel: .patchControl), .complete(Data()))
    }

    // MARK: - Decoder dispatch (§2.3, risk 3)

    func testLingoDecoderDecryptsAssembledRealtime() throws {
        let crypto = try syntheticCrypto()
        let decoder = DataPlaneDecoder(crypto: crypto, family: .lingo)
        let assembler = DataPlaneNotificationAssembler(family: .lingo)
        let frame = try lingoFrame(sequence: 7)
        XCTAssertNil(assembler.feed(fragment: frame.prefix(20), channel: .glucoseData))
        XCTAssertNil(assembler.feed(fragment: frame.subdata(in: 20..<40), channel: .glucoseData))
        let assembled = try XCTUnwrap(assembler.feed(fragment: frame.suffix(from: 40), channel: .glucoseData))
        let packet = try decoder.decrypt(frame: DataFrame.parse(assembled), channel: .glucoseData)
        XCTAssertEqual(packet.kind, .kind3)
        XCTAssertEqual(packet.frame.sequenceNumber, 7)
        guard case .lingoRealtime(let reading) = packet.payload else {
            return XCTFail("expected lingoRealtime, got \(packet.payload)")
        }
        XCTAssertEqual(reading.lifeCount, 58)
        XCTAssertEqual(reading.cappedMgDL, 201)
        XCTAssertEqual(decoder.unexpectedRawCount, 0)
        XCTAssertNil(decoder.lastDecodeError)
    }

    func testDecoderCountsUnexpectedRawInsteadOfSwallowing() throws {
        let crypto = try syntheticCrypto()
        let libre3 = DataPlaneDecoder(crypto: crypto)
        XCTAssertEqual(libre3.family, .libre3)
        let packet = try libre3.decrypt(frame: DataFrame.parse(lingoFrame()), channel: .glucoseData)
        XCTAssertEqual(packet.payload, .raw(try vector("warm_lc58")))
        XCTAssertEqual(libre3.unexpectedRawCount, 1)
        let failure = try XCTUnwrap(libre3.lastDecodeError)
        XCTAssertEqual(failure.channel, .glucoseData)
        XCTAssertEqual(failure.family, .libre3)
        XCTAssertEqual(failure.plaintextLength, 51)
        XCTAssertTrue(failure.reason.contains("wrongPlaintextSize"))

        let lingo = DataPlaneDecoder(crypto: crypto, family: .lingo)
        XCTAssertEqual(lingo.decodePayload(channel: .glucoseData, plaintext: Data(count: 50)), .raw(Data(count: 50)))
        XCTAssertEqual(lingo.decodePayload(channel: .historicData, plaintext: Data([0x05, 0x00, 0x64, 0x00])), .raw(Data([0x05, 0x00, 0x64, 0x00])))
        XCTAssertEqual(lingo.unexpectedRawCount, 2)
        XCTAssertEqual(lingo.lastDecodeError?.channel, .historicData)
        // Channels without a parser are expected raw and not counted.
        _ = lingo.decodePayload(channel: .patchControl, plaintext: Data([0x01]))
        _ = lingo.decodePayload(channel: .eventLog, plaintext: Data([0x01]))
        XCTAssertEqual(lingo.unexpectedRawCount, 2)
    }

    func testDecoderDispatchesLingoChannels() throws {
        let decoder = DataPlaneDecoder(crypto: try syntheticCrypto(), family: .lingo)
        let status14 = hexData("3a0000000000000420000000" + "abcd")
        guard case .patchStatus(let status) = decoder.decodePayload(channel: .patchStatus, plaintext: status14) else {
            return XCTFail("expected patch status")
        }
        XCTAssertEqual(status.analyteBytes, Data([0xab, 0xcd]))
        XCTAssertEqual(status.currentLifeCount, 0x20)

        let history = hexData("0580" + "6400" + "6e00")
        XCTAssertEqual(
            decoder.decodePayload(channel: .historicData, plaintext: history),
            .lingoHistoricalPage(try LingoHistoricalPage(plaintext: history))
        )
        let fast = hexData("1680" + "0102030405060708" + "7800" + "0080")
        XCTAssertEqual(
            decoder.decodePayload(channel: .clinicalData, plaintext: fast),
            .lingoFastData(try LingoFastData(plaintext: fast))
        )
        XCTAssertEqual(decoder.unexpectedRawCount, 0)

        let unknown = DataPlaneDecoder(crypto: try syntheticCrypto(), family: .unknown)
        if case .lingoRealtime = unknown.decodePayload(channel: .glucoseData, plaintext: try vector("warm_lc58")) {
        } else {
            XCTFail("unknown family should dispatch a 51 B realtime by length")
        }
    }

    func testEncryptedLingoPatchStatusDecrypts() throws {
        let crypto = try syntheticCrypto()
        let plaintext = hexData("3a0000000000000420000000" + "0102")
        let frame = try crypto.encrypt(plaintext: plaintext, sequence: 3, kind: .kind2)
        XCTAssertEqual(frame.raw.count, 20)
        let packet = try DataPlaneDecoder(crypto: crypto, family: .lingo).decrypt(frame: frame, channel: .patchStatus)
        XCTAssertEqual(packet.payload, .patchStatus(try PatchStatus(plaintext: plaintext, family: .lingo)))
    }

    // MARK: - PatchStatus (§4)

    func testPatchStatusSizesPerFamily() throws {
        let twelve = hexData("0c000000000000040c000000")
        let fourteen = twelve + Data([0x5a, 0xa5])

        let lingo14 = try PatchStatus(plaintext: fourteen, family: .lingo)
        XCTAssertEqual(lingo14.analyteBytes, Data([0x5a, 0xa5]))
        XCTAssertEqual(lingo14.currentLifeCount, 12)
        XCTAssertEqual(lingo14.patchState, 4)

        let lingo12 = try PatchStatus(plaintext: twelve, family: .lingo)
        XCTAssertNil(lingo12.analyteBytes)
        XCTAssertEqual(try PatchStatus(plaintext: twelve), try PatchStatus(plaintext: twelve, family: .libre3))
        XCTAssertNil(try PatchStatus(plaintext: twelve).analyteBytes)

        XCTAssertThrowsError(try PatchStatus(plaintext: fourteen)) { error in
            XCTAssertEqual(error as? PatchStatusError, .wrongPlaintextSize(14))
        }
        XCTAssertThrowsError(try PatchStatus(plaintext: fourteen, family: .unknown))
        XCTAssertThrowsError(try PatchStatus(plaintext: twelve + Data([0x00]), family: .lingo))
        XCTAssertThrowsError(try PatchStatus(plaintext: fourteen + Data([0x00]), family: .lingo))
    }

    // MARK: - Historical page (§6.2)

    func testHistoricalPageWithOneToSixValues() throws {
        for n in 1...6 {
            var bytes = Data([0x2c, 0x81]) // 0x812C → lifeCount 300 with bit 15
            for i in 0..<n {
                let value = UInt16(100 + i)
                bytes.append(UInt8(value & 0xff))
                bytes.append(UInt8(value >> 8))
            }
            let page = try LingoHistoricalPage(plaintext: bytes)
            XCTAssertEqual(page.lifeCount, 300)
            XCTAssertEqual(page.startWord, 0x812C)
            XCTAssertEqual(page.values.count, n)
            XCTAssertEqual(page.samples.map(\.lifeCount), (0..<n).map { UInt16(300 + 5 * $0) })
            XCTAssertEqual(page.samples.map(\.word.mgDL), (0..<n).map { UInt16(100 + $0) })
            XCTAssertEqual(page.lastLifeCount, UInt16(300 + 5 * (n - 1)))
        }
    }

    func testHistoricalPageRejectsMissingFlagAndBadSizes() {
        XCTAssertThrowsError(try LingoHistoricalPage(plaintext: hexData("2c016400"))) { error in
            XCTAssertEqual(error as? LingoHistoricalPageError, .missingChannelFlag(startWord: 0x012C))
        }
        for size in [0, 2, 3, 5, 15, 16] {
            XCTAssertThrowsError(try LingoHistoricalPage(plaintext: Data([0x00, 0x80]) + Data(repeating: 0x01, count: max(0, size - 2)).prefix(max(0, size - 2)))) { error in
                XCTAssertEqual(error as? LingoHistoricalPageError, .wrongPlaintextSize(size == 0 ? 2 : size))
            }
        }
    }

    func testHistoricalPageZeroTerminatesAndFlagsInvalid() throws {
        // values: 0x10C8 (bit 12 set, mask → 200), 0x8064 (invalid), 0, 0x0078 (ignored after 0)
        let page = try LingoHistoricalPage(plaintext: hexData("0a80" + "c810" + "6480" + "0000" + "7800"))
        XCTAssertEqual(page.lifeCount, 10)
        XCTAssertEqual(page.values.count, 2)
        XCTAssertEqual(page.samples[0].word.mgDL, 200)
        XCTAssertTrue(page.samples[0].word.bit12)
        XCTAssertNil(page.samples[1].word.mgDL)
        XCTAssertTrue(page.samples[1].word.qualityFlag)
        XCTAssertEqual(page.samples[1].lifeCount, 15)

        let empty = try LingoHistoricalPage(plaintext: hexData("0a800000"))
        XCTAssertTrue(empty.values.isEmpty)
        XCTAssertNil(empty.lastLifeCount)
    }

    // MARK: - Fast data (§6.3)

    func testFastDataHistoricLifeCount() throws {
        let lc21 = try LingoFastData(plaintext: hexData("1580" + "0001020304050607" + "9600" + "0080"))
        XCTAssertEqual(lc21.lifeCount, 21)
        XCTAssertEqual(lc21.historicLifeCount, 0)
        XCTAssertEqual(lc21.current.mgDL, 150)
        XCTAssertNil(lc21.historic.mgDL)
        XCTAssertEqual(lc21.rawData, hexData("0001020304050607"))

        let lc22 = try LingoFastData(plaintext: hexData("1680" + "0000000000000000" + "0080" + "8c00"))
        XCTAssertEqual(lc22.lifeCount, 22)
        XCTAssertEqual(lc22.historicLifeCount, 5)
        XCTAssertNil(lc22.current.mgDL)
        XCTAssertEqual(lc22.historic.mgDL, 140)

        XCTAssertEqual(LingoFastData.historicLifeCount(forLifeCount: 0), 0)
        XCTAssertEqual(LingoFastData.historicLifeCount(forLifeCount: 14345), 14325)
        XCTAssertEqual(LingoFastData.historicLifeCount(forLifeCount: 15175), 15155)
    }

    func testFastDataRejectsMissingFlagAndBadSizes() {
        XCTAssertThrowsError(try LingoFastData(plaintext: hexData("1600" + "0000000000000000" + "6400" + "6400"))) { error in
            XCTAssertEqual(error as? LingoFastDataError, .missingChannelFlag(lifeCountWord: 0x0016))
        }
        XCTAssertThrowsError(try LingoFastData(plaintext: Data(repeating: 0x80, count: 13))) { error in
            XCTAssertEqual(error as? LingoFastDataError, .wrongPlaintextSize(13))
        }
        XCTAssertThrowsError(try LingoFastData(plaintext: Data(repeating: 0x80, count: 15)))
    }

    // MARK: - Backfill commands (§6.1)

    func testBackfillWireValuesPerFamily() {
        XCTAssertEqual(BackfillStream.historical.wireValue(for: .libre3), 0x00)
        XCTAssertEqual(BackfillStream.clinical.wireValue(for: .libre3), 0x01)
        XCTAssertEqual(BackfillStream.historical.wireValue(for: .lingo), 0x02)
        XCTAssertEqual(BackfillStream.clinical.wireValue(for: .lingo), 0x03)
        XCTAssertEqual(BackfillStream.historical.wireValue, 0x00)
    }

    func testLingoBackfillCommandsEncodeAndEncryptWithKind0() throws {
        let history = PatchControlCommand.historicalBackfillGreaterEqual(lifeCount: 0x1234, family: .lingo)
        let clinical = PatchControlCommand.clinicalBackfillGreaterEqual(lifeCount: 0x0105, family: .lingo)
        XCTAssertEqual(history.plaintext, Data([0x01, 0x02, 0x01, 0x34, 0x12, 0x00, 0x00]))
        XCTAssertEqual(clinical.plaintext, Data([0x01, 0x03, 0x01, 0x05, 0x01, 0x00, 0x00]))
        XCTAssertEqual(
            PatchControlCommand.historicalBackfillGreaterEqual(lifeCount: 0x1234).plaintext,
            Data([0x01, 0x00, 0x01, 0x34, 0x12, 0x00, 0x00])
        )

        let crypto = try syntheticCrypto()
        for (seq, command) in [(UInt16(1), history), (UInt16(2), clinical)] {
            let frame = try crypto.encrypt(plaintext: command.plaintext, sequence: seq, kind: .patchControlWrite)
            XCTAssertEqual(frame.raw.count, 13)
            XCTAssertEqual(frame.sequenceNumber, seq)
            XCTAssertEqual(try crypto.decrypt(frame, kind: .kind0), command.plaintext)
            XCTAssertThrowsError(try crypto.decrypt(frame, kind: .kind3))
        }
    }

    func testLingoBackfillSendConditions() {
        func plaintexts(_ current: Int, _ hist: Int?, _ last: Int?) -> [Data] {
            PatchControlCommand.lingoBackfillCommands(
                currentLifeCount: current,
                lastHistoricLifeCountReceived: hist,
                lastLifeCountReceived: last
            ).map(\.plaintext)
        }
        // ((100-16)/5)*5 = 80: not > 80, so no history; clinical from 91.
        XCTAssertEqual(plaintexts(100, 80, 90), [Data([0x01, 0x03, 0x01, 91, 0, 0, 0])])
        // 80 > 75: history from 75.
        XCTAssertEqual(plaintexts(100, 75, 99), [Data([0x01, 0x02, 0x01, 75, 0, 0, 0])])
        // Nothing received yet: history from max(0, 5) = 5; no clinical.
        XCTAssertEqual(plaintexts(100, nil, nil), [Data([0x01, 0x02, 0x01, 5, 0, 0, 0])])
        // Early sensor: (20-16)/5*5 = 0, no history.
        XCTAssertEqual(plaintexts(20, nil, 10), [Data([0x01, 0x03, 0x01, 11, 0, 0, 0])])
        XCTAssertEqual(plaintexts(-1, nil, 10), [])
        XCTAssertEqual(
            PatchControlCommand.lingoBackfillCommands(
                currentLifeCount: 100, lastHistoricLifeCountReceived: 75, lastLifeCountReceived: 90, includeClinical: false
            ).count,
            1
        )
    }

    // MARK: - Data-plane state (change 8)

    private func packet(_ channel: DataPlaneChannel, _ payload: DataPlaneDecodedPayload) -> DataPlaneDecodedPacket {
        DataPlaneDecodedPacket(
            channel: channel,
            frame: DataFrame(encrypted: Data(), seq: 0, type: 0),
            kind: .kind3,
            preferredKind: nil,
            plaintext: Data(),
            payload: payload
        )
    }

    func testStateRecordsLingoRawValuesWithoutPolicy() throws {
        var state = Libre3DataPlaneState()
        let warmup = try LingoRealtimeReading(plaintext: vector("warmup_live2"))
        XCTAssertEqual(state.record(packet(.glucoseData, .lingoRealtime(warmup))), .lingoRealtime(warmup))
        XCTAssertEqual(state.latestLingoRealtime, warmup)
        XCTAssertEqual(state.latestLingoGlucose?.qualityFlag, true)
        XCTAssertEqual(state.latestLingoGlucoseByChannel[1]?.lifeCount, 4)
        XCTAssertNil(state.lastAcceptedGlucoseMgDL)
        XCTAssertNil(state.lastAcceptedGlucoseLifeCount)
        XCTAssertEqual(state.lastLingoLifeCountReceived, 4)

        let warm = try LingoRealtimeReading(plaintext: vector("warm_lc63"))
        _ = state.record(packet(.glucoseData, .lingoRealtime(warm)))
        XCTAssertEqual(state.latestLingoGlucose?.qualityFlag, false)
        XCTAssertEqual(state.latestLingoGlucose?.rangeBits, 2)
        XCTAssertEqual(state.latestLingoGlucose?.block.capped.mgDL, 201)
        XCTAssertEqual(state.lastAcceptedGlucoseLifeCount, 63)
        XCTAssertEqual(state.lastAcceptedGlucoseMgDL, 208) // uncapped, no clamp

        // A frame with no glucose channel keeps the per-channel snapshot.
        var buf = try vector("trend_166")
        buf[34] = 0x32
        let noGlucose = try LingoRealtimeReading(plaintext: buf)
        _ = state.record(packet(.glucoseData, .lingoRealtime(noGlucose)))
        XCTAssertNil(state.latestLingoGlucose)
        XCTAssertEqual(state.latestLingoGlucoseByChannel[1]?.lifeCount, 63)
        XCTAssertEqual(state.lastAcceptedGlucoseMgDL, 208)
        XCTAssertEqual(state.lastLingoLifeCountReceived, 14345)

        let page = try LingoHistoricalPage(plaintext: hexData("2880" + "6400" + "0080"))
        XCTAssertEqual(state.record(packet(.historicData, .lingoHistoricalPage(page))), .lingoHistoricalPage(page))
        XCTAssertEqual(state.lingoHistoricalPages, [page])
        XCTAssertEqual(state.lastLingoHistoricLifeCountReceived, 40) // 45 is flagged

        let fast = try LingoFastData(plaintext: hexData("4b80" + "0000000000000000" + "6400" + "6400"))
        XCTAssertEqual(state.record(packet(.clinicalData, .lingoFastData(fast))), .lingoFastData(fast))
        XCTAssertEqual(state.latestLingoFastData, fast)
        XCTAssertEqual(state.lastLingoHistoricLifeCountReceived, 55) // ((75-17)/5)*5
        XCTAssertEqual(state.lastLingoLifeCountReceived, 14345)
    }

    func testStateLingoReconnectBackfill() throws {
        var state = Libre3DataPlaneState()
        XCTAssertEqual(state.reconnectBackfillCommands(family: .lingo), [])

        let status = try PatchStatus(plaintext: hexData("640000000000000464000000" + "0000"), family: .lingo)
        _ = state.record(packet(.patchStatus, .patchStatus(status)))
        // current 100, nothing received: history from 5 only.
        XCTAssertEqual(
            state.reconnectBackfillCommands(family: .lingo).map(\.plaintext),
            [Data([0x01, 0x02, 0x01, 5, 0, 0, 0])]
        )
        let warm = try LingoRealtimeReading(plaintext: vector("warm_lc63"))
        _ = state.record(packet(.glucoseData, .lingoRealtime(warm)))
        XCTAssertEqual(
            state.reconnectBackfillCommands(family: .lingo).map(\.plaintext),
            [Data([0x01, 0x02, 0x01, 5, 0, 0, 0]), Data([0x01, 0x03, 0x01, 64, 0, 0, 0])]
        )
        XCTAssertEqual(state.reconnectBackfillCommands(family: .unknown), [])
        // Libre 3 path unchanged: >= last accepted lifeCount, streams 00/01.
        XCTAssertEqual(
            state.reconnectBackfillCommands().map(\.plaintext),
            [Data([0x01, 0x00, 0x01, 63, 0, 0, 0]), Data([0x01, 0x01, 0x01, 63, 0, 0, 0])]
        )
    }

    // MARK: - Lifecycle from patch info (change 13)

    private func patchInfoFrame(productType: UInt8, securityVersion: UInt16, wear: UInt16, warmupByte: UInt8) -> Data {
        var frame = Data([0x00, 0xa5, 0x00])
        frame += Data([UInt8(securityVersion & 0xff), UInt8(securityVersion >> 8)])
        frame += Data([0x01, 0x00, 0x00, 0x00]) // region, generation
        frame += Data([UInt8(wear & 0xff), UInt8(wear >> 8)])
        frame += Data([0x1e, 0x0d, 0x01, 0x01]) // firmware
        frame += Data([productType, warmupByte, 0x01])
        frame += Data("TESTSER01".utf8)
        frame += Data([0x00, 0x00])
        return frame
    }

    func testLifecycleDefaultsForLingoPatchInfo() throws {
        let zero = try Libre3NFCPatchInfo(raw: patchInfoFrame(productType: 9, securityVersion: 3, wear: 0, warmupByte: 0))
        XCTAssertEqual(zero.family, .lingo)
        XCTAssertEqual(SensorLifecycle.warmupDurationMinutes(for: zero), 60)
        XCTAssertEqual(SensorLifecycle.wearDurationMinutes(for: zero), 20160)
        let lifecycle = SensorLifecycle(currentLifeCountMinutes: 30, patchInfo: zero)
        XCTAssertEqual(lifecycle.phase, .warmup)
        XCTAssertEqual(lifecycle.remainingWearMinutes, 20130)

        let reported = try Libre3NFCPatchInfo(raw: patchInfoFrame(productType: 9, securityVersion: 3, wear: 0x4EC0, warmupByte: 0x0C))
        XCTAssertEqual(SensorLifecycle.warmupDurationMinutes(for: reported), 60)
        XCTAssertEqual(SensorLifecycle.wearDurationMinutes(for: reported), 20160)
        let custom = try Libre3NFCPatchInfo(raw: patchInfoFrame(productType: 9, securityVersion: 3, wear: 21600, warmupByte: 6))
        let state = Libre3DataPlaneState(patchInfo: custom)
        XCTAssertEqual(state.warmupDurationMinutes, 30)
        XCTAssertEqual(state.wearDurationMinutes, 21600)

        // Libre 3 keeps the raw values (upstream behaviour).
        let libre3Zero = try Libre3NFCPatchInfo(raw: patchInfoFrame(productType: 4, securityVersion: 1, wear: 0, warmupByte: 0))
        XCTAssertEqual(SensorLifecycle.warmupDurationMinutes(for: libre3Zero), 0)
        XCTAssertEqual(SensorLifecycle.wearDurationMinutes(for: libre3Zero), 0)

        let status = try PatchStatus(plaintext: hexData("0c000000000000040c000000" + "0000"), family: .lingo)
        XCTAssertEqual(status.lifecycle(patchInfo: zero).warmupDurationMinutes, 60)
        XCTAssertEqual(status.lifecycle(patchInfo: zero).wearDurationMinutes, 20160)
    }

    // MARK: - NFC activation error (extra)

    func testFourByteActivationErrorIsParsed() {
        XCTAssertThrowsError(try Libre3NFCActivationResponse(raw: hexData("00a501b1"))) { error in
            let activationError = error as? Libre3NFCActivationError
            XCTAssertEqual(activationError?.code, 0xb1)
            XCTAssertEqual(activationError?.isReceiverIDRejected, true)
            XCTAssertEqual(activationError?.reason(patchStateByte: 8), .receiverIDRejected)
            XCTAssertEqual(activationError?.raw, hexData("00a501b1"))
        }
        // Leading flag byte stripped by CoreNFC: `A5 01 xx` is normalised.
        XCTAssertThrowsError(try Libre3NFCActivationResponse(raw: hexData("a50122"))) { error in
            let activationError = error as? Libre3NFCActivationError
            XCTAssertEqual(activationError?.code, 0x22)
            XCTAssertEqual(activationError?.reason(patchStateByte: 8), .sensorTerminated)
            XCTAssertEqual(activationError?.reason(patchStateByte: 6), .sensorTerminated)
            XCTAssertEqual(activationError?.reason(patchStateByte: 4), .other(code: 0x22))
            XCTAssertEqual(activationError?.reason(patchStateByte: nil), .other(code: 0x22))
        }
        // Other short shapes still fail as invalidActivationResponse.
        for bad in ["00a500b1", "00a501b100", "00a501"] {
            XCTAssertThrowsError(try Libre3NFCActivationResponse(raw: hexData(bad))) { error in
                guard case Libre3NFCError.invalidActivationResponse = error else {
                    return XCTFail("\(bad): unexpected \(error)")
                }
            }
        }
        XCTAssertEqual(String(describing: Libre3NFCActivationError(code: 0xb1)), "activationError(code=0xb1)")
    }

    func testNineteenByteActivationSuccessStillParses() throws {
        let raw = hexData("00a500" + "060504030201" + "0a0b0c0d" + "10203040" + "beef")
        let response = try Libre3NFCActivationResponse(raw: raw)
        XCTAssertEqual(response.bleAddressDisplay, "01:02:03:04:05:06")
        XCTAssertEqual(response.blePIN, hexData("0a0b0c0d"))
        XCTAssertEqual(response.activationTimeRaw, hexData("10203040"))
    }
}
