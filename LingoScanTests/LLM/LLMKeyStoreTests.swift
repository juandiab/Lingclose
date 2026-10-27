import Foundation
import Synchronization
import Testing
@testable import LingoScan

/// `LLMKeyStore` sobre `InMemorySecretItem` (sin Llavero real): una clave por proveedor.
struct LLMKeyStoreTests {
    private func makeStore() -> (LLMKeyStore, [LLMProviderID: InMemorySecretItem]) {
        let items = Dictionary(uniqueKeysWithValues: LLMProviderID.allCases.map { ($0, InMemorySecretItem()) })
        return (LLMKeyStore(itemFor: { items[$0]! }), items)
    }

    @Test func savesReadsAndDeletesPerProvider() async throws {
        let (store, items) = makeStore()
        #expect(try await store.key(for: .anthropic) == nil)
        try await store.save("  \(LLMFixtures.testKey)\n", for: .anthropic)
        #expect(try await store.key(for: .anthropic) == LLMFixtures.testKey, "se guarda sin espacios")
        #expect(try await store.key(for: .openai) == nil, "cada proveedor tiene su cuenta")
        #expect(await store.hasKey(for: .anthropic))
        #expect(try items[.anthropic]!.read() == Data(LLMFixtures.testKey.utf8))
        try await store.delete(for: .anthropic)
        #expect(try await store.key(for: .anthropic) == nil)
        #expect(await store.hasKey(for: .anthropic) == false)
    }

    @Test func emptyKeyForgetsTheStoredOne() async throws {
        let (store, _) = makeStore()
        try await store.save(LLMFixtures.testKey, for: .gemini)
        try await store.save("   ", for: .gemini)
        #expect(try await store.key(for: .gemini) == nil)
    }

    @Test func keychainItemUsesTheLLMServiceAndProviderAccount() {
        let item = LLMKeyStore.keychainItem(for: .openrouter) as? KeychainItem
        #expect(item?.service == "com.otalvaro.lingoscan.llm")
        #expect(item?.account == "openrouter")
    }

    @Test func storeDescriptionDoesNotRevealTheKey() async throws {
        let (store, _) = makeStore()
        try await store.save(LLMFixtures.testKey, for: .deepseek)
        #expect(!String(describing: store).contains(LLMFixtures.testKey))
    }
}
