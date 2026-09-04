import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var oddfishPGN: UTType { UTType(filenameExtension: "pgn", conformingTo: .plainText) ?? .plainText }
}

struct PGNFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.oddfishPGN, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct HistoryView: View {
    let records: [GameRecord]
    let stats: PlayerStats
    let onClear: () -> Void
    let onImport: (GameRecord) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmingClear = false
    @State private var importingPGN = false
    @State private var importError: String?

    init(
        records: [GameRecord],
        stats: PlayerStats,
        onClear: @escaping () -> Void,
        onImport: @escaping (GameRecord) -> Void = { _ in }
    ) {
        self.records = records
        self.stats = stats
        self.onClear = onClear
        self.onImport = onImport
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    statsRow
                    VStack(alignment: .leading, spacing: 12) {
                        OddfishEyebrow(text: "Recent dives")
                        if records.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(records) { record in
                                    NavigationLink {
                                        GameReviewView(record: record)
                                    } label: {
                                        HistoryRow(record: record)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("history-record-\(record.id.uuidString)")
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        importingPGN = true
                    } label: {
                        Label("Import PGN", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("history-import-pgn")

                    if !records.isEmpty {
                        Button("Clear", role: .destructive) { confirmingClear = true }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Clear game history?", isPresented: $confirmingClear) {
                Button("Clear history", role: .destructive, action: onClear)
                Button("Keep history", role: .cancel) {}
            } message: {
                Text("Your aggregate record will stay, but individual games will be removed from this device.")
            }
            .alert("Couldn’t import PGN", isPresented: importErrorBinding) {
                Button("Close") { importError = nil }
            } message: {
                Text(importError ?? "The selected file could not be read.")
            }
            .fileImporter(
                isPresented: $importingPGN,
                allowedContentTypes: [.oddfishPGN, .plainText],
                allowsMultipleSelection: false,
                onCompletion: importSelection
            )
            .oddfishScreenBackground()
        }
        .tint(OddfishTheme.seaGlass)
        .preferredColorScheme(.dark)
    }

    /// Three figures across, until the labels stop fitting.
    ///
    /// A third of a phone's width is not enough for "Games" at an accessibility
    /// text size, and a one-word label has nowhere to break: it split as
    /// "Ga"/"mes" and "Win"/"s". Stacking them is what the home screen's
    /// identical row already does at these sizes.
    @ViewBuilder
    private var statsRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) { statCells }
        } else {
            HStack(spacing: 10) { statCells }
        }
    }

    @ViewBuilder
    private var statCells: some View {
        StatCell(value: "\(stats.gamesPlayed)", label: "Games")
        StatCell(value: "\(stats.wins)", label: "Wins", tint: OddfishTheme.seaGlass)
        // The placeholder is not coral. Coral is the palette's lowest-contrast
        // ink and it means loss — and a dash is a thin enough stroke in it that
        // the accessibility audit measured the pair as failing. A win rate that
        // does not exist yet is not a loss, so it takes the neutral ink; the
        // figure keeps the accent once there is a figure.
        StatCell(
            value: stats.gamesPlayed == 0 ? "—" : "\(Int((stats.winRate * 100).rounded()))%",
            label: "Win rate",
            tint: stats.gamesPlayed == 0 ? OddfishTheme.mutedInk : OddfishTheme.coral
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "water.waves")
                .font(.largeTitle)
                .foregroundStyle(OddfishTheme.seaGlass)
                // Decoration above a heading that already says this. Unhidden,
                // VoiceOver announced the symbol's own name — "water.waves".
                .accessibilityHidden(true)
            Text("No games to review")
                .font(.oddfishHeadline)
                .foregroundStyle(OddfishTheme.ivory)
            Text("Finish a game here or import a PGN to step through every move.")
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.mutedInk)
                .multilineTextAlignment(.center)
            Button("Import PGN", systemImage: "square.and.arrow.down") {
                importingPGN = true
            }
            .buttonStyle(OddfishSecondaryButtonStyle(fillsWidth: false))
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .oddfishSurface(cornerRadius: 22)
    }

    private var importErrorBinding: Binding<Bool> {
        Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )
    }

    private func importSelection(_ result: Result<[URL], any Error>) {
        do {
            guard let url = try result.get().first else { throw CocoaError(.fileNoSuchFile) }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            onImport(try PGNCodec.importRecord(from: text))
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct StatCell: View {
    let value: String
    let label: String
    var tint: Color = OddfishTheme.ivory

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .oddfishSurface()
        .accessibilityElement(children: .combine)
        // Named, the way the home screen's identical tile is. Combining
        // children without a label leaves a node with no accessible name, and
        // the accessibility audit could then only report a contrast failure
        // against an anonymous "SwiftUI.AccessibilityNode" — measured across
        // the whole card rather than against any of the text in it.
        .accessibilityLabel(spokenLabel)
    }

    /// "0 Games", and "Win rate, no games yet" instead of reading out the
    /// em dash that stands in for a percentage there is no data for.
    private var spokenLabel: String {
        value == "—" ? "\(label), no games yet" : "\(value) \(label)"
    }
}

private struct HistoryRow: View {
    let record: GameRecord

    private var mode: GameMode { GameMode(rawValue: record.modeID) ?? .classic }

    var body: some View {
        HStack(spacing: 13) {
            OddfishModeGlyph(mode: mode, size: 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(mode.title)
                        .font(.oddfishHeadline)
                        .foregroundStyle(OddfishTheme.ivory)
                    if record.isImported {
                        Text("IMPORTED")
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(OddfishTheme.mutedInk)
                    }
                }
                Text(detail)
                    .font(.oddfishCaption)
                    .foregroundStyle(resultTint)
                if let award = record.award {
                    HStack(spacing: 7) {
                        CrownIcons(tier: award.tier, size: 10)
                        Text(award.score.formatted)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(OddfishTheme.Guide.body)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(record.date, format: .dateTime.month(.abbreviated).day())
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(OddfishTheme.mutedInk)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OddfishTheme.mutedInk)
            }
        }
        .padding(13)
        .oddfishSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var detail: String {
        "\(resultTitle) · \(record.moveCount) plies · \(durationText)"
    }

    private var accessibilityText: String {
        var value = "\(mode.title), \(detail), \(record.date.formatted(date: .abbreviated, time: .omitted))"
        if record.isImported { value += ", imported, not crown eligible" }
        if let award = record.award { value += ", \(award.tier) crowns, \(award.score.formatted)" }
        return value
    }

    private var resultTitle: String {
        switch record.result {
        case .win: "Victory"
        case .loss: "Defeat"
        case .draw: "Draw"
        case .abandoned: "Resigned"
        case .unknown: "Finished"
        }
    }

    private var resultTint: Color {
        switch record.result {
        case .win: OddfishTheme.seaGlass
        case .loss: OddfishTheme.coral
        default: OddfishTheme.mutedInk
        }
    }

    private var durationText: String {
        guard record.duration > 0 else { return "time unknown" }
        let seconds = max(0, Int(record.duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct GameReviewView: View {
    let record: GameRecord

    /// Built off the main thread: replaying a long game used to run
    /// synchronously in `init`, freezing the app through the navigation push.
    @State private var replay: GameReplay?
    @State private var replayFailed = false
    @State private var exportText: String?
    @State private var selectedPly: Int
    @State private var exportingPGN = false
    @State private var exportError: String?

    init(record: GameRecord) {
        self.record = record
        _selectedPly = State(initialValue: record.moveCount)
    }

    private var mode: GameMode { GameMode(rawValue: record.modeID) ?? .classic }
    /// Reads the one position being shown. Building the whole `[Position]` array
    /// to subscript it once meant every step of the transport copied every
    /// position in the game.
    private var selectedPosition: Position {
        guard let replay else { return record.startingPosition }
        let ply = min(max(selectedPly, 0), replay.plies.count)
        return ply == 0 ? replay.startingPosition : replay.plies[ply - 1].positionAfter
    }
    private var selectedMove: Move? {
        guard selectedPly > 0, let replay, replay.plies.indices.contains(selectedPly - 1) else { return nil }
        return replay.plies[selectedPly - 1].move
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OddfishTheme.Spacing.regular) {
                summary
                if replay != nil {
                    board
                    transport
                    moveHistory
                } else if replayFailed {
                    board
                    fallbackHistoryText
                } else {
                    loadingRow
                }
                exportButton
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, OddfishTheme.Spacing.regular)
            .padding(.vertical, OddfishTheme.Spacing.regular)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Game review")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let record = record
            let (built, text) = await Task.detached(priority: .userInitiated) {
                let built = try? GameReplay(record: record)
                return (built, PGNCodec.export(record, replay: built))
            }.value
            replay = built
            exportText = text
            replayFailed = built == nil
            selectedPly = min(selectedPly, built?.plies.count ?? record.moveCount)
        }
        .fileExporter(
            isPresented: $exportingPGN,
            document: PGNFileDocument(text: exportText ?? ""),
            contentType: .oddfishPGN,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .alert("Couldn’t export PGN", isPresented: exportErrorBinding) {
            Button("Close") { exportError = nil }
        } message: {
            Text(exportError ?? "The PGN could not be saved.")
        }
        .oddfishScreenBackground()
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
            OddfishModeGlyph(mode: mode, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title)
                    .font(.oddfishTitle)
                    .foregroundStyle(OddfishTheme.ivory)
                Text(record.date.formatted(date: .long, time: .omitted))
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
                if let award = record.award {
                    HStack(spacing: 8) {
                        CrownIcons(tier: award.tier)
                        Text(award.score.formatted)
                            .font(.oddfishCaption)
                            .foregroundStyle(OddfishTheme.Guide.body)
                    }
                } else if record.isImported {
                    Label("Imported · not crown eligible", systemImage: "square.and.arrow.down")
                        .font(.oddfishCaption)
                        .foregroundStyle(OddfishTheme.mutedInk)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(OddfishTheme.Spacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oddfishSurface()
    }

    private var board: some View {
        ChessBoardView(
            position: selectedPosition,
            mode: mode,
            playerColor: record.playerColor,
            selectedSquare: nil,
            legalMoves: [],
            showsMoveHints: false,
            lastMove: selectedMove,
            restingState: VariantState(),
            isInputEnabled: false,
            invalidMoveNonce: 0,
            onTap: { _ in },
            onDragStart: { _ in },
            onMove: { _, _ in false }
        )
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("history-review-board")
    }

    private var transport: some View {
        HStack(spacing: OddfishTheme.Spacing.tight) {
            transportButton("Start", image: "backward.end.fill", disabled: selectedPly == 0) { selectedPly = 0 }
            transportButton("Previous", image: "chevron.left", disabled: selectedPly == 0) { selectedPly -= 1 }
            VStack(spacing: 1) {
                Text(selectedPly == 0 ? "START" : "PLY \(selectedPly)")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(OddfishTheme.mutedInk)
                Text(selectedPly == 0 ? "Initial position" : replay?.plies[selectedPly - 1].san ?? "—")
                    .font(.oddfishNumeric)
                    .foregroundStyle(OddfishTheme.ivory)
            }
            .frame(maxWidth: .infinity)
            transportButton("Next", image: "chevron.right", disabled: selectedPly >= (replay?.plies.count ?? 0)) { selectedPly += 1 }
            transportButton("End", image: "forward.end.fill", disabled: selectedPly >= (replay?.plies.count ?? 0)) {
                selectedPly = replay?.plies.count ?? 0
            }
        }
        .padding(OddfishTheme.Spacing.tight)
        .background(OddfishTheme.surfaceHigh, in: RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.control, style: .continuous)
                .stroke(OddfishTheme.line, lineWidth: 1)
        }
        .accessibilityIdentifier("history-review-controls")
    }

    private func transportButton(_ label: String, image: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .bold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? OddfishTheme.mutedInk.opacity(0.4) : OddfishTheme.seaGlass)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var moveHistory: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.tight) {
            OddfishEyebrow(text: "Move history")
            if let replay, !replay.plies.isEmpty {
                MoveHistoryList(plies: replay.plies, selectedPly: selectedPly) { selectedPly = $0 }
            } else {
                fallbackHistoryText
            }
        }
    }

    private var fallbackHistoryText: some View {
        Text("This older record has no replayable move notation. Its original text is preserved in the exported PGN.")
            .font(.oddfishCaption)
            .foregroundStyle(OddfishTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var loadingRow: some View {
        HStack(spacing: OddfishTheme.Spacing.snug) {
            ProgressView()
                .tint(OddfishTheme.seaGlass)
            Text("Loading game…")
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading game")
    }

    private var exportButton: some View {
        Button {
            exportingPGN = true
        } label: {
            Label("Export PGN", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(OddfishSecondaryButtonStyle())
        .disabled(exportText == nil)
        .accessibilityIdentifier("history-export-pgn")
    }

    private var exportFilename: String {
        let safeMode = mode.title.replacingOccurrences(of: " ", with: "-")
        return "Oddfish-\(safeMode)-\(record.date.formatted(.iso8601.year().month().day())).pgn"
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
    }
}

/// The replay's move list.
///
/// Scrolls in its own right and follows the transport, so stepping through a
/// game keeps the move you are on in view instead of leaving it below the fold
/// of the review screen. Rows are lazy: a long game now builds the handful on
/// screen rather than every ply again on every step.
private struct MoveHistoryList: View {
    let plies: [ReplayPly]
    let selectedPly: Int
    let onSelect: (Int) -> Void

    /// Grows with Dynamic Type, so the visible-row budget below stays honest
    /// at larger text sizes instead of cutting rows in half.
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 44
    private let rowSpacing: CGFloat = 6
    /// The list grows to this many rows and then scrolls.
    private let maximumVisibleRows = 6

    private var listHeight: CGFloat {
        let rows = CGFloat(min(plies.count, maximumVisibleRows))
        return rows * rowHeight + max(0, rows - 1) * rowSpacing
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: rowSpacing) {
                    ForEach(plies) { ply in
                        MoveHistoryRow(
                            number: ply.number,
                            side: ply.positionBefore.sideToMove,
                            san: ply.san,
                            isSelected: ply.number == selectedPly,
                            minHeight: rowHeight,
                            action: { onSelect(ply.number) }
                        )
                        .id(ply.number)
                    }
                }
            }
            .frame(height: listHeight)
            // Explicit, because the review screen hides its own indicators and
            // `scrollIndicators` travels down the environment. This list is the
            // one place on the screen where the bar is the whole point: it is
            // what says a long game continues past the sixth row.
            .scrollIndicators(.visible)
            // A short game fills the list exactly, so there is nothing to
            // scroll: without this it would bounce, and swallow the review
            // screen's own scroll while doing it.
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: selectedPly) { _, ply in
                withAnimation(OddfishTheme.Motion.chrome) {
                    proxy.scrollTo(max(ply, 1), anchor: .center)
                }
            }
            .onAppear { proxy.scrollTo(max(selectedPly, 1), anchor: .center) }
        }
        .accessibilityIdentifier("history-move-list")
    }
}

private struct MoveHistoryRow: View {
    let number: Int
    let side: PieceColor
    let san: String
    let isSelected: Bool
    let minHeight: CGFloat
    let action: () -> Void

    /// The two label columns scale with the text in them.
    ///
    /// They were fixed at 34 and 42 points while the type inside them was a
    /// scaling style, so at larger text sizes the ply number and the side ran
    /// out of their own columns — and the row's height was already `@ScaledMetric`,
    /// which made the row grow while its contents stayed put.
    @ScaledMetric(relativeTo: .subheadline) private var numberWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .caption2) private var sideWidth: CGFloat = 42

    var body: some View {
        Button(action: action) {
            HStack(spacing: OddfishTheme.Spacing.snug) {
                Text("\(number)")
                    .font(.oddfishNumeric)
                    .foregroundStyle(isSelected ? OddfishTheme.canvas : OddfishTheme.mutedInk)
                    .frame(width: numberWidth, alignment: .trailing)
                Text(side == .white ? "WHITE" : "BLACK")
                    // The theme's own small all-caps label, with the tracking
                    // its documentation pairs it with. This was a hard 8pt,
                    // which is below the readable floor and stayed there at
                    // every Dynamic Type setting.
                    .font(.oddfishOverline)
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? OddfishTheme.canvas.opacity(0.72) : OddfishTheme.mutedInk)
                    .frame(width: sideWidth, alignment: .leading)
                Text(san)
                    .font(.oddfishNumeric)
                    .foregroundStyle(isSelected ? OddfishTheme.canvas : OddfishTheme.ivory)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, OddfishTheme.Spacing.snug)
            .frame(minHeight: minHeight)
            .background(
                isSelected ? OddfishTheme.seaGlass : OddfishTheme.surfaceHigh,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ply \(number), \(san). Jump to position")
        .accessibilityIdentifier("history-ply-\(number)")
    }
}

#Preview("History") {
    HistoryView(records: [], stats: PlayerStats(), onClear: {})
}
