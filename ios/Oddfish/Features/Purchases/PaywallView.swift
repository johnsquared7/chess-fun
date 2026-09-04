import SwiftUI

/// The single purchase surface for Oddfish's non-consumable full unlock.
///
/// The App Store supplies the price and remains the source of truth for access;
/// this view only explains the offer and reflects `PurchaseManager` state.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases

    let requestedMode: GameMode?
    let onUnlocked: () -> Void

    private var premiumModeCount: Int {
        GameMode.allCases.filter(\.requiresFullUnlock).count
    }

    /// Read from `GameMode.freeModes`, in catalogue order, rather than written
    /// out here. This promise names specific modes, the free set has already
    /// been widened once, and a hand-typed sentence is the one part of that
    /// change nothing would have failed on — it would simply have gone on
    /// under-promising to the person deciding whether to pay.
    private var freeModeSentence: String {
        let names = GameMode.allCases.filter(\.isFree).map(\.title)
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
        }
    }

    private var headline: String {
        if let requestedMode {
            return "Unlock \(requestedMode.title)"
        }
        return "Unlock Full Oddfish"
    }

    private var supportingCopy: String {
        if requestedMode != nil {
            return "Get this mode and \(premiumModeCount - 1) more strange ways to play."
        }
        return "Get \(premiumModeCount) more strange ways to play."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OddfishTheme.Spacing.loose) {
                    hero
                    benefits
                    purchaseControls
                }
                .padding(.horizontal, OddfishTheme.Spacing.screenEdge)
                .padding(.top, OddfishTheme.Spacing.tight)
                .padding(.bottom, OddfishTheme.Spacing.section)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .oddfishScreenBackground()
            .navigationTitle("Full Oddfish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("full-unlock-close")
                }
            }
        }
        .tint(OddfishTheme.seaGlass)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .task { await purchases.prepare() }
        .alert(item: noticeBinding) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text(noticeGrantsAccess(notice) ? "Continue" : "OK")) {
                    purchases.clearNotice()
                    if noticeGrantsAccess(notice) {
                        finishUnlock()
                    }
                }
            )
        }
        .accessibilityIdentifier("full-unlock-paywall")
    }

    private var hero: some View {
        VStack(spacing: OddfishTheme.Spacing.snug) {
            ZStack {
                Circle()
                    .fill(OddfishTheme.gold.opacity(0.12))
                    .frame(width: 104, height: 104)
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(OddfishTheme.gold)
            }
            .accessibilityHidden(true)

            VStack(spacing: OddfishTheme.Spacing.hairline) {
                Text(headline)
                    .font(.oddfishTitle)
                    .foregroundStyle(OddfishTheme.ivory)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(supportingCopy)
                    .font(.oddfishBody)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.snug) {
            benefit(
                icon: "fish.fill",
                title: "The whole aquarium",
                detail: "All \(premiumModeCount) premium modes in the Oddfish catalogue."
            )
            benefit(
                icon: "creditcard.fill",
                title: "One purchase",
                detail: "Pay once. No subscription, adverts, or Oddfish account required."
            )
            benefit(
                icon: "checkmark.shield.fill",
                title: "Your free modes stay free",
                detail: "\(freeModeSentence) never require this unlock."
            )
        }
        .padding(OddfishTheme.Spacing.loose)
        .oddfishSurface()
    }

    private func benefit(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
            Image(systemName: icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(OddfishTheme.seaGlass)
                .frame(width: 26, height: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.oddfishHeadline)
                    .foregroundStyle(OddfishTheme.ivory)
                Text(detail)
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var purchaseControls: some View {
        VStack(spacing: OddfishTheme.Spacing.tight) {
            if purchases.isFullVersionUnlocked {
                Label("Full Oddfish is unlocked", systemImage: "checkmark.seal.fill")
                    .font(.oddfishHeadline)
                    .foregroundStyle(OddfishTheme.seaGlass)
                    .padding(.bottom, OddfishTheme.Spacing.hairline)

                Button("Continue", systemImage: "arrow.right") { finishUnlock() }
                    .buttonStyle(OddfishPrimaryButtonStyle())
                    .accessibilityIdentifier("full-unlock-buy")
            } else if purchases.canPurchase, let product = purchases.product {
                Button {
                    Task { await purchases.purchaseFullUnlock() }
                } label: {
                    HStack(spacing: OddfishTheme.Spacing.tight) {
                        if purchases.isPurchasing {
                            ProgressView()
                                .tint(OddfishTheme.onAccent)
                        }
                        Text(purchases.isPurchasing ? "Contacting App Store…" : "Unlock for \(product.displayPrice)")
                    }
                }
                .buttonStyle(OddfishPrimaryButtonStyle(tint: OddfishTheme.gold))
                .disabled(purchases.isBusy)
                .accessibilityIdentifier("full-unlock-buy")
            } else {
                productUnavailableState
            }

            Button {
                Task { await purchases.restorePurchases() }
            } label: {
                HStack(spacing: OddfishTheme.Spacing.tight) {
                    if purchases.isRestoring {
                        ProgressView()
                    }
                    Text(purchases.isRestoring ? "Restoring…" : "Restore Purchase")
                }
            }
            .buttonStyle(OddfishSecondaryButtonStyle())
            .disabled(purchases.isBusy)
            .accessibilityIdentifier("full-unlock-restore")

            Text("Purchases are handled by the App Store and can be restored on your other devices using the same Apple Account.")
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.faintInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var productUnavailableState: some View {
        switch purchases.loadState {
        case .idle, .loading:
            HStack(spacing: OddfishTheme.Spacing.tight) {
                ProgressView()
                Text("Loading App Store price…")
                    .font(.oddfishControl)
            }
            .foregroundStyle(OddfishTheme.mutedInk)
            .frame(maxWidth: .infinity, minHeight: 54)

        case .failed(let message):
            VStack(spacing: OddfishTheme.Spacing.tight) {
                Text(message)
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.coral)
                    .multilineTextAlignment(.center)
                retryButton
            }

        case .unavailable:
            VStack(spacing: OddfishTheme.Spacing.tight) {
                Text("Full Oddfish is not available from the App Store right now.")
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .multilineTextAlignment(.center)
                retryButton
            }

        case .loaded:
            // A loaded state without a product cannot normally occur, but the
            // retry remains a safe recovery if StoreKit changes underneath us.
            retryButton
        }
    }

    private var retryButton: some View {
        Button("Try Again", systemImage: "arrow.clockwise") {
            Task { await purchases.reloadProduct() }
        }
        .buttonStyle(OddfishPrimaryButtonStyle())
        .disabled(purchases.isBusy)
    }

    private var noticeBinding: Binding<PurchaseNotice?> {
        Binding(
            get: { purchases.notice },
            set: { newValue in
                if newValue == nil { purchases.clearNotice() }
            }
        )
    }

    private func noticeGrantsAccess(_ notice: PurchaseNotice) -> Bool {
        switch notice {
        case .unlocked, .restored:
            purchases.isFullVersionUnlocked
        case .pending, .nothingToRestore, .error:
            false
        }
    }

    private func finishUnlock() {
        purchases.clearNotice()
        onUnlocked()
        dismiss()
    }
}

#Preview("Full unlock") {
    PaywallView(requestedMode: .moodSwingFish, onUnlocked: {})
        .environment(PurchaseManager())
}
