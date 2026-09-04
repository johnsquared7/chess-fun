import Foundation
import Observation
import StoreKit

/// The StoreKit product rendered by Oddfish's own UI.
///
/// Views receive only display-ready values so they never hard-code a price and
/// unit tests do not need to manufacture StoreKit's opaque `Product` type.
struct StoreProductInfo: Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
    let displayPrice: String
}

enum PurchaseEntitlement: Equatable, Sendable {
    case checking
    case locked
    case unlocked
}

enum ProductLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case unavailable
    case failed(String)
}

enum PurchaseOperation: Equatable, Sendable {
    case idle
    case purchasing
    case restoring
}

enum PurchaseNotice: Equatable, Identifiable, Sendable {
    case unlocked
    case pending
    case restored
    case nothingToRestore
    case error(String)

    var id: String {
        switch self {
        case .unlocked: "unlocked"
        case .pending: "pending"
        case .restored: "restored"
        case .nothingToRestore: "nothing-to-restore"
        case .error(let message): "error-\(message)"
        }
    }

    var title: String {
        switch self {
        case .unlocked: "Full Oddfish Unlocked"
        case .pending: "Purchase Pending"
        case .restored: "Purchase Restored"
        case .nothingToRestore: "No Purchase Found"
        case .error: "Purchase Not Completed"
        }
    }

    var message: String {
        switch self {
        case .unlocked:
            "Every Oddfish mode is now ready to play."
        case .pending:
            "The App Store is waiting for approval. The modes will unlock automatically when it completes."
        case .restored:
            "Full Oddfish is unlocked on this device."
        case .nothingToRestore:
            "The App Store did not find a previous Full Oddfish purchase for this account."
        case .error(let message):
            message
        }
    }
}

enum StorePurchaseResult: Equatable, Sendable {
    case purchased
    case pending
    case cancelled
}

@MainActor
protocol PurchaseStoreClient: AnyObject {
    var canMakePayments: Bool { get }

    func loadProduct(id: String) async throws -> StoreProductInfo?
    func currentEntitlement(id: String) async -> Bool
    func purchase(id: String) async throws -> StorePurchaseResult
    func updates(for id: String) -> AsyncStream<Void>
    func sync() async throws
}

enum PurchaseStoreError: LocalizedError {
    case productUnavailable
    case failedVerification

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            "Full Oddfish is not available from the App Store right now. Please try again."
        case .failedVerification:
            "The App Store transaction could not be verified, so no access was changed."
        }
    }
}

/// The live StoreKit boundary. Only verified transactions for the exact product
/// identifier can produce an entitlement, and unverified transactions are never
/// finished or trusted.
@MainActor
final class StoreKitPurchaseClient: PurchaseStoreClient {
    private var products: [String: Product] = [:]

    var canMakePayments: Bool { StoreKit.AppStore.canMakePayments }

    func loadProduct(id: String) async throws -> StoreProductInfo? {
        guard let product = try await Product.products(for: [id]).first(where: { $0.id == id }) else {
            products[id] = nil
            return nil
        }

        products[id] = product
        return StoreProductInfo(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice
        )
    }

    func currentEntitlement(id: String) async -> Bool {
        guard let verification = await Transaction.currentEntitlement(for: id),
              case .verified(let transaction) = verification,
              transaction.productID == id,
              transaction.revocationDate == nil else {
            return false
        }

        return true
    }

    func purchase(id: String) async throws -> StorePurchaseResult {
        let product: Product
        if let cached = products[id] {
            product = cached
        } else {
            _ = try await loadProduct(id: id)
            guard let loaded = products[id] else { throw PurchaseStoreError.productUnavailable }
            product = loaded
        }

        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verifiedTransaction(verification, productID: id)
            guard transaction.revocationDate == nil else {
                throw PurchaseStoreError.failedVerification
            }
            await transaction.finish()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func updates(for id: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await verification in Transaction.updates {
                    guard !Task.isCancelled else { break }
                    guard case .verified(let transaction) = verification,
                          transaction.productID == id else {
                        continue
                    }

                    await transaction.finish()
                    continuation.yield(())
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sync() async throws {
        try await StoreKit.AppStore.sync()
    }

    private func verifiedTransaction(
        _ verification: VerificationResult<Transaction>,
        productID: String
    ) throws -> Transaction {
        guard case .verified(let transaction) = verification,
              transaction.productID == productID else {
            throw PurchaseStoreError.failedVerification
        }
        return transaction
    }
}

/// App-lifetime owner of Full Oddfish purchase and entitlement state.
///
/// StoreKit's signed entitlement is the only shipping authority. The debug UI
/// override exists solely for deterministic UI automation and is compiled out
/// of Release builds.
@Observable
@MainActor
final class PurchaseManager {
    static let fullUnlockProductID = "com.oddfish.chess.fullunlock"

    private(set) var product: StoreProductInfo?
    private(set) var entitlement: PurchaseEntitlement = .checking
    private(set) var loadState: ProductLoadState = .idle
    private(set) var operation: PurchaseOperation = .idle
    var notice: PurchaseNotice?

    private let client: any PurchaseStoreClient
    #if DEBUG
    private let debugFullUnlock: Bool
    #endif
    private var transactionListener: Task<Void, Never>?
    private var hasPrepared = false

    #if DEBUG
    init(
        client: (any PurchaseStoreClient)? = nil,
        debugFullUnlock: Bool? = nil
    ) {
        self.client = client ?? StoreKitPurchaseClient()
        self.debugFullUnlock = debugFullUnlock ?? Self.uiTestUnlockOverride
    }
    #else
    init(client: (any PurchaseStoreClient)? = nil) {
        self.client = client ?? StoreKitPurchaseClient()
    }
    #endif

    var isFullVersionUnlocked: Bool { entitlement == .unlocked }
    var isBusy: Bool { operation != .idle }
    var isPurchasing: Bool { operation == .purchasing }
    var isRestoring: Bool { operation == .restoring }
    var canPurchase: Bool {
        product != nil && loadState == .loaded && client.canMakePayments
    }

    func canPlay(_ mode: GameMode) -> Bool {
        mode.isFree || isFullVersionUnlocked
    }

    /// Starts transaction observation before resolving current access, then
    /// loads the display product. Repeated view tasks are harmless.
    func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true
        startObservingTransactions()
        await refreshEntitlement()
        await reloadProduct()
    }

    func reloadProduct() async {
        guard loadState != .loading else { return }
        loadState = .loading

        do {
            product = try await client.loadProduct(id: Self.fullUnlockProductID)
            if product == nil || !client.canMakePayments {
                loadState = .unavailable
            } else {
                loadState = .loaded
            }
        } catch {
            product = nil
            loadState = .failed(Self.message(for: error))
        }
    }

    func purchaseFullUnlock() async {
        guard operation == .idle, !isFullVersionUnlocked else { return }

        if product == nil {
            await reloadProduct()
        }
        guard canPurchase else {
            notice = .error("Full Oddfish is not available from the App Store right now. Please try again.")
            return
        }

        operation = .purchasing
        notice = nil

        do {
            switch try await client.purchase(id: Self.fullUnlockProductID) {
            case .purchased:
                entitlement = .unlocked
                notice = .unlocked
            case .pending:
                notice = .pending
            case .cancelled:
                break
            }
        } catch {
            notice = .error(Self.message(for: error))
        }

        operation = .idle
    }

    /// Restore is deliberately user initiated. StoreKit can show account UI, so
    /// calling sync silently at launch would be surprising and against platform
    /// guidance.
    func restorePurchases() async {
        guard operation == .idle else { return }
        operation = .restoring
        notice = nil

        do {
            try await client.sync()
            await refreshEntitlement()
            notice = isFullVersionUnlocked ? .restored : .nothingToRestore
        } catch {
            notice = .error(Self.message(for: error))
        }

        operation = .idle
    }

    func clearNotice() {
        notice = nil
    }

    /// The app owns one manager for its lifetime. Tests stop listeners explicitly
    /// so separate fakes never keep consuming update streams.
    func stopObservingTransactions() {
        transactionListener?.cancel()
        transactionListener = nil
    }

    private func startObservingTransactions() {
        guard transactionListener == nil else { return }
        let updates = client.updates(for: Self.fullUnlockProductID)

        transactionListener = Task { [weak self] in
            for await _ in updates {
                guard !Task.isCancelled, let self else { return }
                await self.refreshEntitlement()
            }
        }
    }

    private func refreshEntitlement() async {
        #if DEBUG
        if debugFullUnlock {
            entitlement = .unlocked
            return
        }
        #endif

        entitlement = await client.currentEntitlement(id: Self.fullUnlockProductID)
            ? .unlocked
            : .locked
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? any LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "The App Store could not complete that request. Please try again."
    }

    #if DEBUG
    private static var uiTestUnlockOverride: Bool {
        ProcessInfo.processInfo.arguments.contains("-oddfishUITestFullUnlock")
    }
    #endif
}
