import Foundation
import Testing
@testable import Oddfish

@Suite(.serialized)
@MainActor
struct PurchaseManagerTests {
    @Test func freeAndPremiumModesHaveOneCentralAccessRule() {
        let client = FakePurchaseStoreClient()
        let manager = PurchaseManager(client: client, debugFullUnlock: false)

        #expect(GameMode.freeModes == [.classic, .rattleFish, .fumbleFish, .restfish, .gluttonFish, .chapelFish])
        #expect(GameMode.allCases.filter(\.isFree).count == 6)
        #expect(GameMode.allCases.filter(\.requiresFullUnlock).count == 23)
        #expect(GameMode.allCases.filter(\.isFree).allSatisfy(manager.canPlay))
        #expect(GameMode.allCases.filter(\.requiresFullUnlock).allSatisfy { !manager.canPlay($0) })
    }

    @Test func localStoreKitConfigurationMatchesTheShippingContract() throws {
        let configurationURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "StoreKit/Oddfish.storekit")
        let data = try Data(contentsOf: configurationURL)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try #require(object["products"] as? [[String: Any]])
        let fullUnlock = try #require(products.first)

        #expect(products.count == 1)
        #expect(fullUnlock["productID"] as? String == PurchaseManager.fullUnlockProductID)
        #expect(fullUnlock["type"] as? String == "NonConsumable")
    }

    @Test func runSchemePointsAtTheLocalStoreKitConfiguration() throws {
        let iosDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let schemeURL = iosDirectory
            .appending(path: "Oddfish.xcodeproj/xcshareddata/xcschemes/Oddfish.xcscheme")
        let scheme = try String(contentsOf: schemeURL, encoding: .utf8)

        #expect(scheme.contains("identifier = \"../StoreKit/Oddfish.storekit\""))
        #expect(FileManager.default.fileExists(
            atPath: iosDirectory.appending(path: "StoreKit/Oddfish.storekit").path
        ))
    }

    @Test func prepareLoadsTheProductAndResolvesLockedAccess() async {
        let client = FakePurchaseStoreClient()
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }

        await manager.prepare()

        #expect(manager.product == client.defaultProduct)
        #expect(manager.loadState == .loaded)
        #expect(manager.entitlement == .locked)
        #expect(client.loadedProductIDs == [PurchaseManager.fullUnlockProductID])
        #expect(client.entitlementChecks == 1)
    }

    @Test func prepareRecognizesAnExistingEntitlement() async {
        let client = FakePurchaseStoreClient()
        client.isEntitled = true
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }

        await manager.prepare()

        #expect(manager.entitlement == .unlocked)
        #expect(manager.canPlay(.moodSwingFish))
    }

    @Test func aVerifiedPurchaseUnlocksPremiumModes() async {
        let client = FakePurchaseStoreClient()
        client.purchaseResult = .purchased
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        await manager.purchaseFullUnlock()

        #expect(manager.entitlement == .unlocked)
        #expect(manager.notice == .unlocked)
        #expect(manager.operation == .idle)
        #expect(client.purchasedProductIDs == [PurchaseManager.fullUnlockProductID])
    }

    @Test func aCancelledPurchaseLeavesStateQuietlyLocked() async {
        let client = FakePurchaseStoreClient()
        client.purchaseResult = .cancelled
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        await manager.purchaseFullUnlock()

        #expect(manager.entitlement == .locked)
        #expect(manager.notice == nil)
        #expect(manager.operation == .idle)
    }

    @Test func aPendingPurchaseExplainsThatAccessIsNotReadyYet() async {
        let client = FakePurchaseStoreClient()
        client.purchaseResult = .pending
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        await manager.purchaseFullUnlock()

        #expect(manager.entitlement == .locked)
        #expect(manager.notice == .pending)
    }

    @Test func purchaseErrorsDoNotGrantAccess() async {
        let client = FakePurchaseStoreClient()
        client.purchaseError = FakePurchaseError.purchaseFailed
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        await manager.purchaseFullUnlock()

        #expect(manager.entitlement == .locked)
        #expect(manager.notice == .error("The test purchase failed."))
        #expect(manager.operation == .idle)
    }

    @Test func restoreFindsAPreviousPurchase() async {
        let client = FakePurchaseStoreClient()
        client.entitlementAfterSync = true
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        await manager.restorePurchases()

        #expect(client.syncCount == 1)
        #expect(manager.entitlement == .unlocked)
        #expect(manager.notice == .restored)
    }

    @Test func restoreExplainsWhenNoPurchaseExists() async {
        let client = FakePurchaseStoreClient()
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        await manager.restorePurchases()

        #expect(manager.entitlement == .locked)
        #expect(manager.notice == .nothingToRestore)
    }

    @Test func restoreErrorsDoNotChangeAccess() async {
        let client = FakePurchaseStoreClient()
        client.syncError = FakePurchaseError.restoreFailed
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        await manager.restorePurchases()

        #expect(manager.entitlement == .locked)
        #expect(manager.notice == .error("The test restore failed."))
        #expect(manager.operation == .idle)
    }

    @Test func transactionUpdatesUnlockAndRevokeAccess() async {
        let client = FakePurchaseStoreClient()
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }
        await manager.prepare()

        client.isEntitled = true
        client.sendTransactionUpdate()
        await waitForTasks()
        #expect(manager.entitlement == .unlocked)

        client.isEntitled = false
        client.sendTransactionUpdate()
        await waitForTasks()
        #expect(manager.entitlement == .locked)
    }

    @Test func anUnavailableProductCanBeRetried() async {
        let client = FakePurchaseStoreClient()
        client.product = nil
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }

        await manager.prepare()
        #expect(manager.loadState == .unavailable)

        client.product = client.defaultProduct
        await manager.reloadProduct()
        #expect(manager.product == client.defaultProduct)
        #expect(manager.loadState == .loaded)
    }

    @Test func purchasesDisabledOnTheDeviceCannotStartACharge() async {
        let client = FakePurchaseStoreClient()
        client.canMakePayments = false
        let manager = PurchaseManager(client: client, debugFullUnlock: false)
        defer { manager.stopObservingTransactions() }

        await manager.prepare()
        #expect(manager.loadState == .unavailable)
        #expect(!manager.canPurchase)

        await manager.purchaseFullUnlock()
        #expect(client.purchasedProductIDs.isEmpty)
        #expect(manager.entitlement == .locked)
        #expect(manager.notice != nil)
    }

    @Test func debugAutomationOverrideNeverNeedsAFakeReceipt() async {
        let client = FakePurchaseStoreClient()
        let manager = PurchaseManager(client: client, debugFullUnlock: true)
        defer { manager.stopObservingTransactions() }

        await manager.prepare()

        #expect(manager.entitlement == .unlocked)
        #expect(client.entitlementChecks == 0)
    }

    private func waitForTasks() async {
        for _ in 0..<8 { await Task.yield() }
    }
}

@MainActor
private final class FakePurchaseStoreClient: PurchaseStoreClient {
    let defaultProduct = StoreProductInfo(
        id: PurchaseManager.fullUnlockProductID,
        displayName: "Full Oddfish",
        description: "Unlock every mode.",
        displayPrice: "$4.99"
    )

    var canMakePayments = true
    var product: StoreProductInfo?
    var productLoadError: (any Error)?
    var isEntitled = false
    var purchaseResult: StorePurchaseResult = .purchased
    var purchaseError: (any Error)?
    var entitlementAfterSync: Bool?
    var syncError: (any Error)?

    private(set) var loadedProductIDs: [String] = []
    private(set) var purchasedProductIDs: [String] = []
    private(set) var entitlementChecks = 0
    private(set) var syncCount = 0
    private var updateContinuations: [AsyncStream<Void>.Continuation] = []

    init() {
        product = defaultProduct
    }

    func loadProduct(id: String) async throws -> StoreProductInfo? {
        loadedProductIDs.append(id)
        if let productLoadError { throw productLoadError }
        return product
    }

    func currentEntitlement(id: String) async -> Bool {
        entitlementChecks += 1
        return isEntitled
    }

    func purchase(id: String) async throws -> StorePurchaseResult {
        purchasedProductIDs.append(id)
        if let purchaseError { throw purchaseError }
        return purchaseResult
    }

    func updates(for id: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            updateContinuations.append(continuation)
        }
    }

    func sync() async throws {
        syncCount += 1
        if let syncError { throw syncError }
        if let entitlementAfterSync { isEntitled = entitlementAfterSync }
    }

    func sendTransactionUpdate() {
        for continuation in updateContinuations { continuation.yield(()) }
    }
}

private enum FakePurchaseError: LocalizedError {
    case purchaseFailed
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .purchaseFailed: "The test purchase failed."
        case .restoreFailed: "The test restore failed."
        }
    }
}
