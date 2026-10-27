import Foundation
import LingoCore
import Testing
@testable import LingoScan

@MainActor
struct MealAnalysisViewModelTests {
    private func proposal(_ env: MealTestEnvironment, ids: IDSequence = IDSequence()) async -> MealAnalysisViewModel {
        let model = env.viewModel(ids: ids)
        await model.prepare()
        model.descriptionText = "arepa con queso"
        await model.analyze()
        return model
    }

    private func texts(_ model: MealAnalysisViewModel) -> (kcal: String, carbs: String) {
        (model.text(for: .kcal), model.text(for: .carbsG))
    }

    // MARK: Porciones

    @Test func sliderRecalculatesFromTheBaseAndReturnsExactly() async throws {
        let env = try await MealTestEnvironment.make()
        let model = await proposal(env)
        #expect(model.phase == .proposal)
        #expect(texts(model) == ("200", "30"))
        model.setMultiplier(1.5)
        #expect(texts(model) == ("300", "45"))
        #expect(model.multiplierText == "1,5")
        model.setMultiplier(1.0)
        #expect(texts(model) == ("200", "30"))
        #expect(model.baseNutrients.kcal == 200 && model.baseNutrients.carbsG == 30, "la base no se toca")
        #expect(env.provider.analyzeCalls.count == 1, "el slider nunca llama al proveedor")
    }

    @Test func manualCorrectionSurvivesTheSliderAndResetRestoresTheCalculatedValue() async throws {
        let env = try await MealTestEnvironment.make()
        let model = await proposal(env)
        model.setText("40,5", for: .carbsG)
        #expect(model.isManual(.carbsG))
        model.setMultiplier(2.0)
        #expect(model.adjusted.carbsG == 40.5, "el slider no toca lo corregido a mano")
        #expect(model.adjusted.kcal == 400, "el resto sí se recalcula")
        model.reset(.carbsG)
        #expect(!model.isManual(.carbsG))
        #expect(model.adjusted.carbsG == 60)
        #expect(model.text(for: .carbsG) == "60")
    }

    @Test func emptyOrInvalidTextIsNeverZero() async throws {
        let env = try await MealTestEnvironment.make()
        let model = await proposal(env)
        model.setText("", for: .proteinG)
        #expect(model.overrides.proteinG == nil)
        model.commitEditing(.proteinG)
        #expect(model.text(for: .proteinG) == "6", "vacío vuelve al valor calculado")
        model.setText("abc", for: .fatG)
        #expect(model.isInvalid(.fatG))
        #expect(!model.canSave, "un texto inválido bloquea el guardado")
        model.setText("-3", for: .fatG)
        #expect(model.isInvalid(.fatG), "negativo fuera de rango")
        model.setText("3.5", for: .fatG)
        #expect(model.overrides.fatG == 3.5)
        #expect(model.canSave)
    }

    @Test func unknownIsSavedAsNilNotZero() async throws {
        var analysis = FakeLLMProvider.arepa
        analysis.baseNutrients = Nutrients(kcal: 200, carbsG: nil, proteinG: nil, fatG: 7)
        let env = try await MealTestEnvironment.make(provider: FakeLLMProvider(analysis: analysis))
        let model = await proposal(env)
        #expect(model.text(for: .carbsG) == "")
        model.setMultiplier(3.0)
        #expect(await model.save())
        let record = try #require(await env.store.savedRecords.last)
        #expect(record.baseNutrients.carbsG == nil && record.effectiveNutrients.carbsG == nil)
        let event = try #require(await env.store.savedEvents.last)
        #expect(event.carbsG == nil)
        #expect(record.effectiveNutrients.kcal == 600)
    }

    @Test func noFiguresMeansNoSlider() async throws {
        var analysis = FakeLLMProvider.arepa
        analysis.baseNutrients = .unknown
        let env = try await MealTestEnvironment.make(provider: FakeLLMProvider(analysis: analysis))
        let model = await proposal(env)
        #expect(!model.hasFigures)
        #expect(model.phase == .proposal)
    }

    // MARK: Guardar y reabrir

    @Test func saveAndReopenKeepsBaseMultiplierAndOverrides() async throws {
        let env = try await MealTestEnvironment.make()
        let ids = IDSequence()
        let model = await proposal(env, ids: ids)
        model.setMultiplier(1.5)
        model.setText("50", for: .carbsG)
        #expect(await model.save())
        let event = try #require(await env.store.savedEvents.last)
        let record = try #require(try await env.store.mealNutrition(eventID: event.eventID))
        #expect(event.kind == .meal && event.text == "Arepa con queso")
        #expect(event.carbsG == 50)
        #expect(event.revision == 1 && event.parentEditID == nil)
        #expect(record.source == .llm(provider: "anthropic", model: "claude-haiku-5-5"))
        #expect(record.baseNutrients == Nutrients(kcal: 200, carbsG: 30, proteinG: 6, fatG: 7))
        #expect(record.multiplier == 1.5)
        #expect(record.overrides == Nutrients(carbsG: 50))

        let reopened = MealAnalysisViewModel(
            reopening: event, record: record, services: env.services, calendar: MealTestEnvironment.calendar,
            now: { MealTestEnvironment.now }, newID: { ids.next() })
        #expect(reopened.phase == .proposal)
        #expect(reopened.externalChangeNotice == nil)
        #expect(reopened.multiplier == 1.5 && reopened.baseNutrients == record.baseNutrients)
        #expect(reopened.isManual(.carbsG) && reopened.adjusted.kcal == 300)
        reopened.setMultiplier(2.0)
        #expect(await reopened.save())
        let second = try #require(await env.store.savedEvents.last)
        #expect(second.eventID == event.eventID)
        #expect(second.revision == 2 && second.parentEditID == event.editID && second.editID != event.editID)
        #expect(second.carbsG == 50, "la corrección manual sigue protegida")
    }

    @Test func reopeningWarnsWhenTheEventChangedOutsideTheApp() async throws {
        let env = try await MealTestEnvironment.make()
        let model = await proposal(env)
        #expect(await model.save())
        var event = try #require(await env.store.savedEvents.last)
        let record = try #require(try await env.store.mealNutrition(eventID: event.eventID))
        event.carbsG = 12
        let reopened = MealAnalysisViewModel(reopening: event, record: record, services: env.services)
        let notice = try #require(reopened.externalChangeNotice)
        #expect(notice.contains("12"), "el aviso incluye los carbohidratos guardados (el idioma depende del simulador)")
        #expect(await env.store.savedEvents.count == 1, "no se sobrescribe hasta que el usuario guarde")
    }

    @Test func failedSaveReportsAndDoesNotMarkSaved() async throws {
        let env = try await MealTestEnvironment.make()
        let model = await proposal(env)
        await env.store.setFailNextSave(true)
        #expect(await model.save() == false)
        #expect(model.saveFailure == .failed && !model.didSave)
    }

    // MARK: Análisis

    @Test func notFoodCannotBeSaved() async throws {
        let env = try await MealTestEnvironment.make(provider: FakeLLMProvider(analysis: FoodAnalysis(kind: .notFood)))
        let model = await proposal(env)
        #expect(model.kind == .notFood && model.phase == .proposal)
        #expect(!model.canSave)
        #expect(await model.save() == false)
        #expect(await env.store.savedEvents.isEmpty)
        model.backToInput()
        #expect(model.phase == .input)
    }

    @Test func cannotAnalyzeWithoutPhotoOrDescription() async throws {
        let env = try await MealTestEnvironment.make()
        let model = env.viewModel()
        await model.prepare()
        #expect(!model.canAnalyze)
        model.descriptionText = "   \n"
        #expect(!model.canAnalyze)
        await model.analyze()
        #expect(env.provider.analyzeCalls.isEmpty)
        model.setPhoto(LLMFixtures.fakeJPEG)
        #expect(model.canAnalyze)
    }

    @Test func photoWithModelWithoutConfirmedVisionDoesNotCallTheProvider() async throws {
        for support in [ImageSupport.none, .unconfirmed] {
            let env = try await MealTestEnvironment.make(imageSupport: support)
            let model = env.viewModel()
            await model.prepare()
            model.setPhoto(LLMFixtures.fakeJPEG)
            model.descriptionText = "arepa"
            #expect(model.photoBlockedByModel && !model.canAnalyze)
            await model.analyze()
            #expect(env.provider.analyzeCalls.isEmpty)
            model.discardPhoto()
            #expect(model.canAnalyze, "solo con la descripción sí se puede")
            await model.analyze()
            #expect(env.provider.analyzeCalls.count == 1)
            #expect(env.provider.analyzeCalls[0].request.imageJPEG == nil)
        }
    }

    @Test func requestCarriesOnlyThePhotoAndTheDescription() async throws {
        let env = try await MealTestEnvironment.make()
        let model = env.viewModel()
        await model.prepare()
        model.setPhoto(LLMFixtures.fakeJPEG)
        model.descriptionText = "  arepa con queso  "
        await model.analyze()
        let call = try #require(env.provider.analyzeCalls.first)
        #expect(call.request.imageJPEG == LLMFixtures.fakeJPEG)
        #expect(call.request.description == "arepa con queso")
        let labels = Set(Mirror(reflecting: call.request).children.compactMap(\.label))
        #expect(labels.isSubset(of: ["imageJPEG", "description", "locale"]), "nada más sale del teléfono: \(labels)")
        #expect(call.apiKey == LLMFixtures.testKey)
        #expect(call.model.id == "claude-haiku-5-5")
    }

    @Test func errorShowsMessageAndOnlyManualRetryCallsAgain() async throws {
        let provider = FakeLLMProvider(analyzeError: .rateLimited)
        let env = try await MealTestEnvironment.make(provider: provider)
        let model = env.viewModel()
        await model.prepare()
        model.descriptionText = "arepa"
        await model.analyze()
        #expect(model.phase == .failed(LLMError.rateLimited.description))
        #expect(provider.analyzeCalls.count == 1, "sin reintentos automáticos")
        provider.analyzeError = nil
        await model.analyze()
        #expect(model.phase == .proposal)
        #expect(provider.analyzeCalls.count == 2)
    }

    @Test func cancellingReturnsToInputAndIgnoresTheLateResult() async throws {
        let provider = FakeLLMProvider()
        provider.delay = .seconds(5)
        let env = try await MealTestEnvironment.make(provider: provider)
        let model = env.viewModel()
        await model.prepare()
        model.descriptionText = "arepa"
        model.startAnalysis()
        #expect(model.phase == .analyzing)
        let task = try #require(model.analysisTask)
        model.cancelAnalysis()
        #expect(model.phase == .input)
        await task.value
        #expect(model.phase == .input, "el resultado tardío se ignora")
    }

    @Test func unconfiguredAssistantCannotAnalyze() async throws {
        let env = try await MealTestEnvironment.make(configured: false)
        let model = env.viewModel()
        await model.prepare()
        #expect(model.readiness == .notConfigured)
        model.descriptionText = "arepa"
        #expect(!model.canAnalyze)
    }

    @Test func labelAnalysisIsSavedAsLabelSourceWithItsBasis() async throws {
        let label = FoodAnalysis(
            kind: .nutritionLabel, name: "Barra", basis: .per100g,
            baseNutrients: Nutrients(kcal: 400, carbsG: 50, proteinG: nil, fatG: 10), unreadableFields: ["protein_g"])
        let env = try await MealTestEnvironment.make(provider: FakeLLMProvider(analysis: label))
        let model = await proposal(env)
        #expect(model.basisSummary?.contains("100 g") == true)
        #expect(model.unreadableText?.contains("protein_g") == true)
        #expect(await model.save())
        let record = try #require(await env.store.savedRecords.last)
        #expect(record.source == .label(provider: "anthropic", model: "claude-haiku-5-5"))
        #expect(record.basis == .per100g)
    }

    @Test func estimatedServingBasisSentence() async throws {
        let env = try await MealTestEnvironment.make()
        let model = await proposal(env)
        #expect(model.basisSummary?.contains("1 arepa mediana (120 g)") == true)
        #expect(model.confidenceText?.contains("70") == true)
    }
}

/// "+" → Comida: la cámara se abre sola una vez y la foto que llega de ahí lanza el análisis sin otro toque.
struct MealAutoCameraTests {
    @Test func autoCameraIsConsumedOnceAndThePhotoStartsTheAnalysis() async throws {
        let env = try await MealTestEnvironment.make()
        let model = await MainActor.run {
            MealAnalysisViewModel(services: env.services, at: MealTestEnvironment.now, autoCamera: true,
                                  calendar: MealTestEnvironment.calendar, now: { MealTestEnvironment.now })
        }
        await model.prepare()
        await MainActor.run {
            #expect(model.autoCameraPending)
            #expect(model.consumeAutoCamera())
            #expect(!model.autoCameraPending)
            #expect(!model.consumeAutoCamera(), "solo una vez")
            model.setPhoto(Data([0xFF, 0xD8, 0xFF]))
            #expect(model.phase == .analyzing, "la foto de la cámara automática analiza sola")
            model.cancelAnalysis()
        }
    }

    @Test func cancelledCameraOrManualFlowNeverAnalyzesAlone() async throws {
        let env = try await MealTestEnvironment.make()
        let auto = await MainActor.run {
            MealAnalysisViewModel(services: env.services, at: MealTestEnvironment.now, autoCamera: true,
                                  calendar: MealTestEnvironment.calendar, now: { MealTestEnvironment.now })
        }
        await auto.prepare()
        await MainActor.run {
            _ = auto.consumeAutoCamera()
            auto.cameraCancelled()
            auto.setPhoto(Data([0xFF, 0xD8, 0xFF]))
            #expect(auto.phase == .input, "tras cancelar la cámara, la foto espera al botón Analizar")
        }
        let manual = await MainActor.run { env.viewModel() }
        await manual.prepare()
        await MainActor.run {
            #expect(!manual.autoCameraPending)
            manual.setPhoto(Data([0xFF, 0xD8, 0xFF]))
            #expect(manual.phase == .input)
        }
    }
}
