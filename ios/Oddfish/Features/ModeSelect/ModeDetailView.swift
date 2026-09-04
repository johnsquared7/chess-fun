import SwiftUI

struct ModeDetailView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let mode: GameMode
    let onStart: (GameMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                lessonCard
                crownContract
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        // Pinned, not appended. Several modes explain enough rules that the one
        // button the screen exists for was below the fold.
        .safeAreaInset(edge: .bottom) { startBar }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .oddfishScreenBackground()
    }

    private var startBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [OddfishTheme.canvas.opacity(0), OddfishTheme.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)
            .allowsHitTesting(false)

            OddfishPrimaryButton(title: "Start \(mode.title)", systemImage: "play.fill") {
                onStart(mode)
            }
            .accessibilityHint(startHint)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .background(OddfishTheme.canvas)
        }
    }

    /// The rule, in Gil's voice, with the same verifiable handicap line the
    /// hinge uses.
    ///
    /// This replaced a templated eyebrow / tagline / rule-summary stack. Between
    /// that block, the rule list below it, and the cue on the game screen, a
    /// mode was being explained three times in three registers. It is explained
    /// once here now, by the character who explains everything else.
    private var intro: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OddfishTheme.Spacing.tight) {
                    GilView(size: 64, expression: .talking)
                    introCopy
                }
            } else {
                HStack(alignment: .top, spacing: OddfishTheme.Spacing.snug) {
                    GilView(size: 64, expression: .talking)
                    introCopy
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(OddfishTheme.Spacing.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oddfishSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gil says: \(mode.ruleSummary) \(handicapLine)")
    }

    private var introCopy: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.hairline) {
            OddfishEyebrow(text: mode.shortTitle)
            Text(mode.ruleSummary)
                .font(.oddfishTitle)
                .foregroundStyle(OddfishTheme.ivory)
                .fixedSize(horizontal: false, vertical: true)
            Text(handicapLine)
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.seaGlass)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the mode actually costs the opponent. Classic costs it nothing, and
    /// says so.
    private var handicapLine: String {
        GuideCopy.detailSubtitle(for: mode)
    }

    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("See it on the board", systemImage: mode.systemImage)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(mode.tint)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    ModeMicroLesson(mode: mode)
                    lessonRules
                }
                VStack(alignment: .leading, spacing: 16) {
                    ModeMicroLesson(mode: mode)
                    lessonRules
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .oddfishSurface(cornerRadius: 22)
        .accessibilityElement(children: .contain)
    }

    private var crownContract: some View {
        VStack(alignment: .leading, spacing: OddfishTheme.Spacing.snug) {
            VStack(alignment: .leading, spacing: OddfishTheme.Spacing.hairline) {
                Label("Crown run", systemImage: "crown.fill")
                    .font(.oddfishHeadline)
                    .foregroundStyle(OddfishTheme.ivory)
                Text("CHECKMATE")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(OddfishTheme.Guide.body)
            }
            ModeRuleLine(text: mode.crownRule.startingRequirementText, tint: OddfishTheme.Guide.body)
            ModeRuleLine(text: mode.crownRule.scoreDescription, tint: OddfishTheme.Guide.body)
            Text("Three crowns for a clean game. Analysis or a mid-game setting change earns two; undo or redo earns one.")
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.ivory)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OddfishTheme.Spacing.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OddfishTheme.surface, in: RoundedRectangle(cornerRadius: OddfishTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.card, style: .continuous)
                .stroke(OddfishTheme.Guide.body.opacity(0.24), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mode-crown-contract")
    }

    private var lessonRules: some View {
        VStack(alignment: .leading, spacing: 10) {
                    ForEach(lesson.rules, id: \.self) { rule in
                        ModeRuleLine(text: rule, tint: mode.tint)
                    }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lesson: ModeLesson {
        switch mode {
        case .classic:
            ModeLesson(
                rules: [
                    "Move from the outlined origin to a marked legal destination.",
                    "Standard checkmate, stalemate, and draw rules apply."
                ]
            )
        default:
            // The canvas beside this list already prints the cue, so repeating
            // it here put the same sentence twice in one card. The list states
            // the rule; the canvas shows when it fires.
            ModeLesson(rules: [mode.ruleSummary])
        }
    }

    private var startHint: String {
        "Starts a new game against the offline opponent."
    }
}

private struct ModeLesson {
    let rules: [String]
}

private struct ModeRuleLine: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(OddfishTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A code-drawn teaching canvas, using the same simple piece silhouette for
/// every mode. It deliberately avoids font-dependent chess and emoji glyphs.
private struct ModeMicroLesson: View {
    let mode: GameMode

    var body: some View {
        Group {
            switch mode {
            case .classic: MoveLessonCanvas()
            default: GimmickLessonCanvas(mode: mode)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch mode {
        case .classic: "Classic lesson: a friendly piece moves from the marked origin along an arrow to a marked legal destination."
        default: "\(mode.title) lesson. \(mode.ruleSummary)"
        }
    }
}

/// Catalogue modes do not all alter board geometry, so pretending each one is
/// a move-arrow lesson would teach the wrong thing. This compact diagram keeps
/// the exact mechanic and its trigger together without inventing board state.
private struct GimmickLessonCanvas: View {
    let mode: GameMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LessonCaption(text: "RULE IN PLAY", tint: mode.tint)
            HStack(spacing: 12) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(mode.tint)
                    .frame(width: 48, height: 48)
                    .background(mode.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // The mode's glyph, next to the mode's name. Announcing it
                    // would read out a raw symbol name and then repeat the
                    // title that follows it.
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(OddfishTheme.ivory)
                    Text(mode.tagline)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(mode.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(mode.inGameCue)
                .font(.oddfishCaption)
                .foregroundStyle(OddfishTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 188, alignment: .leading)
    }
}

private struct MoveLessonCanvas: View {
    private let tint = OddfishTheme.seaGlass

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            LessonCaption(text: "MOVE TO A LEGAL TARGET", tint: tint)
            ZStack {
                LessonBoard(cells: [1: .enemy, 5: .legalTarget, 13: .friendlyOrigin], accent: tint)
                MoveLessonArrow()
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 17)
                    .accessibilityHidden(true)
            }
            HStack(spacing: 7) {
                LessonCallout(text: "FROM", tint: tint)
                LessonLine()
                LessonCallout(text: "LEGAL TO", tint: tint)
            }
        }
        .frame(width: 188)
    }
}

private enum LessonCellKind { case empty, friendlyOrigin, enemy, legalTarget }

private struct LessonBoard: View {
    let cells: [Int: LessonCellKind]
    let accent: Color
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<16, id: \.self) { index in
                LessonBoardCell(kind: cells[index] ?? .empty, index: index, accent: accent).aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OddfishTheme.line, lineWidth: 1) }
        .frame(width: 188, height: 188)
    }
}

private struct LessonBoardCell: View {
    let kind: LessonCellKind
    let index: Int
    let accent: Color
    var body: some View {
        ZStack {
            ((index + index / 4).isMultiple(of: 2) ? OddfishTheme.surfaceHigh : OddfishTheme.surface)
            switch kind {
            case .friendlyOrigin:
                LessonPiece(fill: OddfishTheme.ivory).frame(width: 27, height: 33); LessonSquareRing(color: accent, lineWidth: 2.4)
            case .enemy:
                LessonPiece(fill: OddfishTheme.coral).frame(width: 27, height: 33)
            case .legalTarget:
                Circle().stroke(accent, lineWidth: 2.5).frame(width: 24, height: 24); Circle().fill(accent.opacity(0.75)).frame(width: 7, height: 7); LessonSquareRing(color: accent.opacity(0.72), lineWidth: 1)
            case .empty: EmptyView()
            }
        }
    }
}

private struct LessonSquareRing: View {
    let color: Color; let lineWidth: CGFloat
    var body: some View { RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(color, lineWidth: lineWidth).padding(3).accessibilityHidden(true) }
}

private struct LessonPiece: View {
    let fill: Color
    var body: some View {
        ZStack {
            Circle().fill(fill).frame(width: 10, height: 10).offset(y: -8)
            Capsule().fill(fill).frame(width: 15, height: 16).offset(y: 2)
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(fill).frame(width: 25, height: 5).offset(y: 11)
        }.accessibilityHidden(true)
    }
}

private struct MoveLessonArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(); let x = rect.minX + rect.width * 0.24; let start = rect.minY + rect.height * 0.82; let end = rect.minY + rect.height * 0.30
        path.move(to: CGPoint(x: x, y: start)); path.addLine(to: CGPoint(x: x, y: end)); path.move(to: CGPoint(x: x, y: end)); path.addLine(to: CGPoint(x: x - 5, y: end + 8)); path.move(to: CGPoint(x: x, y: end)); path.addLine(to: CGPoint(x: x + 5, y: end + 8)); return path
    }
}

private struct LessonCaption: View {
    let text: String; let tint: Color
    var body: some View {
        Canvas { context, size in
            let label = context.resolve(
                Text(text)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(tint)
            )
            context.draw(
                label,
                at: CGPoint(x: 0, y: size.height / 2),
                anchor: .leading
            )
        }
            .frame(width: 188, height: 16)
            // ModeMicroLesson exposes the complete spoken lesson; this compact
            // heading is redundant diagram geometry rather than body copy.
            .accessibilityHidden(true)
    }
}

private struct LessonCallout: View {
    let text: String; let tint: Color
    var body: some View {
        Text(text)
            .font(.oddfishOverline)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(tint.opacity(0.11), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.38), lineWidth: 1))
    }
}

private struct LessonLine: View {
    var body: some View { Rectangle().fill(OddfishTheme.line).frame(height: 1).accessibilityHidden(true) }
}

#Preview("Detail") {
    NavigationStack { ModeDetailView(mode: .flinchFish, onStart: { _ in }) }
}
