import SwiftUI

/// A slim, player-relative evaluation tide. Positive scores fill upward from
/// the player's side of the board; mate and tablebase results pin near an end
/// rather than pretending to be ordinary centipawn values.
struct EvaluationTideView: View {
    let score: AnalysisScore?
    let playerColor: PieceColor
    let isAnalyzing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let fraction = playerFraction
            let playerFill = playerColor == .white
                ? OddfishTheme.ivory
                : OddfishTheme.Board.blackPieceFill
            let opponentFill = playerColor == .white
                ? OddfishTheme.Board.blackPieceFill
                : OddfishTheme.ivory

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(opponentFill)
                Rectangle()
                    .fill(playerFill)
                    .frame(height: proxy.size.height * fraction)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(OddfishTheme.canvas.opacity(0.9), lineWidth: 1.5)
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: fraction)
        }
        .frame(width: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("game-evaluation-tide")
        .accessibilityLabel("Evaluation")
        .accessibilityValue(score.map(analysisScoreText) ?? (isAnalyzing ? "Analyzing" : "Waiting"))
    }

    private var playerFraction: CGFloat {
        CGFloat(score?.playerEvaluationFraction ?? 0.5)
    }
}

/// Numeric companion to the tide. It lives in the stable game header instead
/// of floating over a piece on whichever rank the tide currently reaches.
struct EvaluationScoreLabel: View {
    let score: AnalysisScore?
    let isAnalyzing: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("EVAL")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(OddfishTheme.mutedInk)
            HStack(spacing: 3) {
                if isAnalyzing {
                    Circle()
                        .fill(OddfishTheme.seaGlass)
                        .frame(width: 4, height: 4)
                }
                Text(score.map(analysisScoreText) ?? "…")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(OddfishTheme.ivory)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("game-evaluation-score")
        .accessibilityLabel("Evaluation score")
        .accessibilityValue(score.map(analysisScoreText) ?? (isAnalyzing ? "Analyzing" : "Waiting"))
    }
}

struct MoveReviewCard: View {
    let classification: MoveClassification

    var body: some View {
        HStack(alignment: .center, spacing: OddfishTheme.Spacing.snug) {
            GilView(
                size: 48,
                expression: classification.quality.gilExpression,
                barTint: classification.quality.tint
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(classification.quality.title)
                        .font(.oddfishHeadline)
                        .foregroundStyle(classification.quality.tint)
                    Text("#\(classification.rank)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(OddfishTheme.mutedInk)
                }
                Text(classification.quality.reviewCopy)
                    .font(.oddfishCaption)
                    .foregroundStyle(OddfishTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                if !classification.isBest {
                    Label(
                        "Gil's square: \(classification.bestMove.to.algebraic) · \(moveText(classification.bestMove))",
                        systemImage: "scope"
                    )
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(OddfishTheme.Guide.body)
                }
            }
            Spacer(minLength: 0)

            Text(analysisScoreText(classification.playedScore))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(OddfishTheme.ivory)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(OddfishTheme.surfaceHigh, in: Capsule())
        }
        .padding(OddfishTheme.Spacing.snug)
        .background(classification.quality.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(classification.quality.tint.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("game-move-review")
    }

    private func moveText(_ move: Move) -> String {
        "\(move.from.algebraic)–\(move.to.algebraic)"
    }
}

func analysisScoreText(_ score: AnalysisScore) -> String {
    switch score {
    case .centipawns(let value):
        return String(format: "%+.2f", Double(value) / 100)
    case .mate(let plies):
        let moves = max(1, (abs(plies) + 1) / 2)
        return plies >= 0 ? "+M\(moves)" : "−M\(moves)"
    case .tablebase(let distance):
        if distance == 0 { return "TB=" }
        return distance > 0 ? "TB+\(distance)" : "TB−\(abs(distance))"
    }
}

private extension MoveQuality {
    var tint: Color {
        switch self {
        case .best: OddfishTheme.seaGlass
        case .good: OddfishTheme.ivory
        case .inaccuracy: OddfishTheme.Guide.body
        case .mistake: Color.orange
        case .blunder: OddfishTheme.coral
        }
    }

    var gilExpression: GilExpression {
        switch self {
        case .best: .cheer
        case .good: .idle
        case .inaccuracy: .doubtful
        case .mistake: .surprised
        case .blunder: .wince
        }
    }

    var reviewCopy: String {
        switch self {
        case .best: "Stockfish's first choice. Clean water."
        case .good: "Solid. The tide barely shifted."
        case .inaccuracy: "A quieter line was available."
        case .mistake: "This gave away a clear edge."
        case .blunder: "The position swung sharply here."
        }
    }
}
