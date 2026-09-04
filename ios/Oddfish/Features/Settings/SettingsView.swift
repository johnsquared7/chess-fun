import SwiftUI

struct SettingsView: View {
    @Binding var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @ScaledMetric(relativeTo: .caption) private var presetMinimumWidth: CGFloat = 76
    @State private var showsPaywall = false
    @State private var restoreNotice: PurchaseNotice?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $settings.soundEnabled) {
                        Label("Sound", systemImage: "speaker.wave.2.fill")
                    }
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label("Haptics", systemImage: "waveform")
                    }
                    Toggle(isOn: $settings.showLegalMoves) {
                        Label("Move hints", systemImage: "lightbulb.fill")
                    }
                } header: {
                    Text("Feedback")
                } footer: {
                    Text("You can change these anytime during a game.")
                }
                .listRowBackground(OddfishTheme.surface)

                Section {
                    ForEach(GameModeCategory.allCases) { category in
                        DisclosureGroup {
                            ForEach(category.modes) { mode in
                                modeSettings(for: mode)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                Text(category.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Modes")
                } footer: {
                    Text("Open a family to tune its starting rating and rule controls. Each mode remembers its own values.")
                }
                .listRowBackground(OddfishTheme.surface)

                Section {
                    Toggle(isOn: $settings.evaluationEnabled) {
                        Label("Evaluation", systemImage: "chart.bar.xaxis")
                    }

                    if settings.evaluationEnabled {
                        Stepper(
                            value: $settings.analysisDepth,
                            in: 10...28,
                            step: 2
                        ) {
                            LabeledContent("Analysis depth", value: "\(settings.analysisDepth)")
                        }

                        Picker("Max think time", selection: $settings.analysisTimeLimit) {
                            ForEach(AnalysisTimeLimit.allCases) { limit in
                                Text(limit.title).tag(limit)
                            }
                        }

                        Toggle("Show evaluation tide", isOn: $settings.showEvaluationBar)
                        Toggle("Show top-five move ranks", isOn: $settings.showMoveRanks)
                        Toggle("Show last-move review", isOn: $settings.showMoveAnalysis)
                    }

                    Stepper(
                        value: $settings.bestMoveToleranceCentipawns,
                        in: 0...200,
                        step: 5
                    ) {
                        LabeledContent(
                            "Best-move tolerance",
                            value: "\(settings.bestMoveToleranceCentipawns) cp"
                        )
                    }

                    Toggle(isOn: $settings.ponderEnabled) {
                        Label("Predictive thinking", systemImage: "bolt.horizontal.circle")
                    }
                } header: {
                    Text("Analysis")
                } footer: {
                    Text("A move within the tolerance of Stockfish's first choice counts as best. Predictive thinking keeps one hidden line warm while you play; it uses more CPU and battery.")
                }
                .listRowBackground(OddfishTheme.surface)

                Section {

                    Toggle(isOn: $settings.playAsBlack) {
                        Label("Play as Black", systemImage: "circle.lefthalf.filled")
                    }

                    Toggle(isOn: $settings.autoQueen) {
                        Label("Auto-queen", systemImage: "crown.fill")
                    }

                    Picker("Gil", selection: $settings.guideChattiness) {
                        ForEach(GuideChattiness.allCases, id: \.self) { level in
                            Text(level.title).tag(level)
                        }
                    }
                } header: {
                    Text("Play")
                } footer: {
                    Text("Your chosen side applies to new games. Auto-queen promotes immediately when a pawn reaches the far shore.")
                }
                .listRowBackground(OddfishTheme.surface)

                Section {
                    if purchases.isFullVersionUnlocked {
                        Label("Full Oddfish unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(OddfishTheme.seaGlass)
                            .accessibilityIdentifier("settings-full-unlock")
                    } else {
                        Button {
                            showsPaywall = true
                        } label: {
                            LabeledContent {
                                Text(fullUnlockPriceLabel)
                            } label: {
                                Label("Unlock all modes", systemImage: "lock.open.fill")
                            }
                        }
                        .disabled(purchases.isBusy)
                        .accessibilityIdentifier("settings-full-unlock")
                    }

                    Button {
                        restoreFromSettings()
                    } label: {
                        HStack(spacing: 8) {
                            Label("Restore Purchase", systemImage: "arrow.clockwise")
                            Spacer()
                            if purchases.isRestoring {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(purchases.isBusy)
                    .accessibilityIdentifier("settings-restore-purchases")
                } header: {
                    Text("Full Oddfish")
                } footer: {
                    Text("A one-time purchase unlocks every premium mode. Classic, RattleFish, FumbleFish, Restfish, GluttonFish, and ChapelFish stay free.")
                }
                .listRowBackground(OddfishTheme.surface)

                Section("Appearance") {
                    NavigationLink {
                        BoardAppearanceView(settings: $settings)
                    } label: {
                        LabeledContent("Board") {
                            Text("\(settings.boardTheme.title) · \(settings.pieceSet.title) · \(settings.pieceStyle.title)")
                        }
                    }
                    .accessibilityIdentifier("settings-board-appearance")
                }
                .listRowBackground(OddfishTheme.surface)

                Section("Legal") {
                    NavigationLink {
                        LicenceView()
                    } label: {
                        LabeledContent("Licence", value: "GPLv3")
                    }
                    .accessibilityIdentifier("settings-licence")
                }
                .listRowBackground(OddfishTheme.surface)

                Section("About Oddfish") {
                    LabeledContent("Version", value: LicenceMetadata.current.compactVersionLabel)
                    LabeledContent("Play style", value: "Offline · single player")
                    Text("Oddfish is chess after someone left the rulebook beside the aquarium.")
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(OddfishTheme.surface)
            }
            // A native Form, wearing the app's palette. Left on the system
            // grouped background it read as a different app's settings screen
            // bolted onto this one.
            .scrollContentBackground(.hidden)
            .background(OddfishTheme.canvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(OddfishTheme.seaGlass)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsPaywall) {
            PaywallView(requestedMode: nil) {
                showsPaywall = false
            }
        }
        .alert(item: $restoreNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func rating(for mode: GameMode) -> OpponentRating {
        settings.rating(for: mode, default: mode.gimmickRule.startingRating)
    }

    @ViewBuilder
    private func modeSettings(for mode: GameMode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !purchases.canPlay(mode) {
                Label("Unlock Full Oddfish to change this mode", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                ratingRow(for: mode)
                ForEach(mode.gimmickRule.parameterDefinitions) { definition in
                    parameterRow(definition, for: mode)
                }
            }
            .disabled(!purchases.canPlay(mode))
            .opacity(purchases.canPlay(mode) ? 1 : 0.55)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }

    private func ratingRow(for mode: GameMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(mode.title, systemImage: mode.systemImage)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(rating(for: mode).rawValue)")
                        .font(.headline.monospacedDigit())
                    Text(ratingBand(for: mode))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Slider(
                value: ratingBinding(for: mode),
                in: Double(OpponentRating.minimum.rawValue)...Double(OpponentRating.maximum.rawValue),
                step: 10
            )
            .tint(mode.tint)
            .accessibilityLabel("\(mode.title) starting rating")
            .accessibilityValue("\(rating(for: mode).rawValue)")

            presetButtons(for: mode)
        }
        .padding(.vertical, 4)
    }

    /// Presets read as a choice with one answer selected, rather than as four
    /// identical buttons where the current one is only a shade different.
    private func presetButtons(for mode: GameMode) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: min(presetMinimumWidth, 144)), spacing: 6)],
            spacing: 6
        ) {
            ForEach(OpponentPreset.allCases, id: \.self) { preset in
                let isSelected = rating(for: mode) == preset.rating
                Button(preset.title) {
                    settings.setRating(preset.rating, for: mode)
                }
                .font(.oddfishCaption.weight(.heavy))
                .foregroundStyle(isSelected ? OddfishTheme.onAccent : OddfishTheme.mutedInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, OddfishTheme.Spacing.hairline)
                .background(isSelected ? mode.tint : OddfishTheme.surfaceHigh, in: Capsule())
                .buttonStyle(OddfishPressableStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func ratingBinding(for mode: GameMode) -> Binding<Double> {
        Binding(
            get: { Double(rating(for: mode).rawValue) },
            set: { settings.setRating(OpponentRating(Int($0.rounded())), for: mode) }
        )
    }

    private func ratingBand(for mode: GameMode) -> String {
        switch rating(for: mode).engineBand {
        case .skillLevel: "Skill"
        case .calibratedElo: "Calibrated Elo"
        case .fullStrength: "Full · time scaled"
        }
    }

    @ViewBuilder
    private func parameterRow(_ definition: GimmickParameterDefinition, for mode: GameMode) -> some View {
        if definition.range == 0...1, definition.step == 1 {
            Toggle(definition.title, isOn: Binding(
                get: { parameterValue(definition, for: mode) >= 0.5 },
                set: { settings.setParameter($0 ? 1 : 0, definition: definition, for: mode) }
            ))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(definition.title, value: parameterLabel(definition, for: mode))
                    .font(.subheadline)
                Slider(
                    value: Binding(
                        get: { parameterValue(definition, for: mode) },
                        set: { settings.setParameter($0, definition: definition, for: mode) }
                    ),
                    in: definition.range,
                    step: definition.step
                )
                .tint(mode.tint)
                .accessibilityValue(parameterLabel(definition, for: mode))
            }
        }
    }

    private func parameterValue(_ definition: GimmickParameterDefinition, for mode: GameMode) -> Double {
        settings.parameters(for: mode, default: mode.gimmickRule.defaultParameters).value(for: definition)
    }

    private func parameterLabel(_ definition: GimmickParameterDefinition, for mode: GameMode) -> String {
        let value = Int(parameterValue(definition, for: mode).rounded())
        if definition.id == GimmickParameterKey.chance { return "\(value)%" }
        if definition.id == GimmickParameterKey.tolerance { return "\(value) cp" }
        if definition.id == GimmickParameterKey.cycle { return "\(value) turns" }
        return "\(value) Elo"
    }

    private var fullUnlockPriceLabel: String {
        if purchases.canPurchase, let price = purchases.product?.displayPrice { return price }
        switch purchases.loadState {
        case .idle, .loading:
            return "Loading price…"
        case .unavailable:
            return "Unavailable"
        case .loaded, .failed:
            return "One-time purchase"
        }
    }

    private func restoreFromSettings() {
        Task {
            await purchases.restorePurchases()
            restoreNotice = purchases.notice
            purchases.clearNotice()
        }
    }
}

#Preview("Settings") {
    SettingsView(settings: .constant(.default))
        .environment(PurchaseManager())
}
