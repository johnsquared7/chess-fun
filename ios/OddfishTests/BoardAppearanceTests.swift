import Foundation
import SwiftUI
import Testing
@testable import Oddfish

/// Stage 7: board themes, piece styles, and the detail toggles.
struct BoardAppearanceTests {

    @Test func everyThemeHasAUniqueIdentifier() {
        let ids = BoardTheme.all.map(\.id)
        #expect(Set(ids).count == ids.count, "Duplicate ids would make theme(id:) ambiguous")
        #expect(BoardTheme.all.count >= 4)
    }

    @Test func anUnknownThemeIdentifierFallsBackRatherThanFailing() {
        // A payload written by a build with a theme this one does not have must
        // not take the whole settings object down with it.
        #expect(BoardTheme.theme(id: "a-theme-from-the-future") == .midnight)
        #expect(BoardTheme.theme(id: "") == .midnight)
        for theme in BoardTheme.all {
            #expect(BoardTheme.theme(id: theme.id) == theme)
        }
    }

    @Test func coordinatesAlwaysContrastWithTheSquareTheySitOn() {
        // Pale squares use dark ink. Mid-tone "dark" squares do too; truly dark
        // squares use light ink. At the configured opacities each pairing clears
        // the normal-text contrast target used by the accessibility review.
        for theme in BoardTheme.all {
            #expect(
                (theme.coordinate(onLight: true) != theme.coordinate(onLight: false))
                    == !theme.darkSquareNeedsDarkInk
            )
            #expect(theme.coordinate(onLight: true) == Color.black.opacity(0.85))
            #expect(
                theme.coordinate(onLight: false)
                    == (theme.darkSquareNeedsDarkInk ? Color.black.opacity(0.85) : Color.white.opacity(0.90))
            )
        }
    }

    /// Move markers are drawn in ink rather than in a theme accent, because an
    /// accent has to clear both square colours at once and on most boards it
    /// clears neither.
    @Test func moveMarkersUseContrastingInkOnEverySquare() {
        for theme in BoardTheme.all {
            #expect(
                (theme.moveDot(onLight: true) != theme.moveDot(onLight: false))
                    == !theme.darkSquareNeedsDarkInk
            )
            #expect(theme.moveDot(onLight: true) == Color.black.opacity(0.60))
            #expect(
                theme.moveDot(onLight: false)
                    == (theme.darkSquareNeedsDarkInk ? Color.black.opacity(0.60) : Color.white.opacity(0.60))
            )
            #expect(theme.moveDot(onLight: true) != theme.lightSquare)
            #expect(theme.moveDot(onLight: false) != theme.darkSquare)
        }
    }

    /// The last-move wash is its own token. Reusing `indicator` for it made the
    /// board draw "where they went" and "where you may go" in one hue.
    @Test func theLastMoveWashIsNotTheMoveIndicator() {
        for theme in BoardTheme.all {
            #expect(theme.highlight != theme.indicator, "\(theme.title) reuses one colour for two meanings")
            #expect(theme.highlight != theme.lightSquare)
            #expect(theme.highlight != theme.darkSquare)
        }
    }

    @Test func everyThemeDistinguishesItsTwoSquares() {
        for theme in BoardTheme.all {
            #expect(theme.lightSquare != theme.darkSquare, "\(theme.title) has one square colour")
            #expect(theme.whitePieceFill != theme.blackPieceFill, "\(theme.title) has one piece colour")
            // The markers must not be either square, or they vanish on half the board.
            #expect(theme.indicator != theme.lightSquare)
            #expect(theme.indicator != theme.darkSquare)
        }
    }

    /// The two axes have to stay independent: a set decides the shape, a style
    /// decides the treatment, and every combination has to be a usable board.
    @Test func everySetAndStyleCombinationIsDrawable() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        for set in PieceSet.allCases {
            #expect(!set.title.isEmpty)
            #expect(!set.detail.isEmpty)
            for kind in PieceKind.allCases {
                #expect(!ChessPieceShape(kind: kind, set: set).path(in: rect).isEmpty)
            }
        }
        #expect(Set(PieceSet.allCases.map(\.id)).count == PieceSet.allCases.count)
    }

    @Test func pieceStylesDifferInTreatmentNotSilhouette() {
        // The shared foot line and height ramp are what make the set read as one
        // set; a style may only change contour, fill and shadow.
        #expect(PieceStyle.flat.outlineWidthMultiplier == 0)
        #expect(PieceStyle.outline.outlineWidthMultiplier > PieceStyle.carved.outlineWidthMultiplier)
        #expect(PieceStyle.carved.castsShadow)
        #expect(!PieceStyle.flat.castsShadow)
        #expect(!PieceStyle.outline.castsShadow)

        for kind in PieceKind.allCases {
            let metrics = PieceMetrics.metrics(for: kind)
            #expect(metrics.width > 0 && metrics.height > 0)
        }
    }

    @Test func appearanceSurvivesARoundTrip() throws {
        var settings = AppSettings.default
        settings.boardThemeID = BoardTheme.classic.id
        settings.pieceSet = .caliente
        settings.pieceStyle = .outline
        settings.showsCoordinates = false
        settings.highlightsLastMove = false

        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)

        #expect(restored.boardTheme == .classic)
        #expect(restored.pieceSet == .caliente)
        #expect(restored.pieceStyle == .outline)
        #expect(restored.boardDecoration.showsCoordinates == false)
        #expect(restored.boardDecoration.highlightsLastMove == false)
    }

    /// The whole of `AppSettings` is stored as one document, so a field that
    /// refused to decode would take a player's stats and game history down with
    /// it. Retiring a piece set has to cost the set and nothing else.
    @Test func aRetiredPieceSetFallsBackWithoutLosingTheRest() throws {
        var settings = AppSettings.default
        settings.boardThemeID = BoardTheme.ember.id
        settings.analysisDepth = 20

        var encoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(settings)
        ) as! [String: Any]
        encoded["pieceSet"] = "compass"

        let restored = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONSerialization.data(withJSONObject: encoded)
        )

        #expect(restored.pieceSet == .caliente, "An unknown set must resolve to one that exists")
        #expect(restored.boardTheme == .ember, "…without discarding everything stored beside it")
        #expect(restored.analysisDepth == 20)
    }

    @Test func anUnknownThemeStillYieldsAUsableBoard() {
        let settings = AppSettings(boardThemeID: "neon")
        #expect(settings.boardThemeID == "neon", "The id is preserved as written")
        #expect(settings.boardTheme == .midnight, "…but it resolves to a board that exists")
    }

    /// Exercises every setting together so Codable synthesis cannot regress
    /// silently when the model changes.
    @Test func everySettingSurvivesARoundTrip() throws {
        var settings = AppSettings.default
        settings.soundEnabled = false
        settings.hapticsEnabled = false
        settings.showLegalMoves = false
        settings.autoQueen = true
        settings.playAsBlack = true
        settings.guideChattiness = .sparse
        settings.evaluationEnabled = true
        settings.analysisDepth = 22
        settings.analysisTimeLimit = .tenSeconds
        settings.showEvaluationBar = false
        settings.showMoveRanks = false
        settings.showMoveAnalysis = false
        settings.ponderEnabled = true
        settings.bestMoveToleranceCentipawns = 40
        settings.boardThemeID = BoardTheme.ember.id
        settings.pieceSet = .caliente
        settings.pieceStyle = .flat
        settings.showsCoordinates = false
        settings.highlightsLastMove = false
        settings.setRating(OpponentRating(1_800), for: .rattleFish)

        let restored = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONEncoder().encode(settings)
        )
        #expect(restored == settings, "A field is missing from the hand-written encoder")
    }

    @Test func theDefaultIsUnchangedFromWhatShipped() {
        // Existing players should not find their board changed underneath them.
        // The piece set is the exception: Staunton was retired, so the stored
        // identifier of anyone still on it resolves forward to the set that
        // exists rather than resetting their whole settings document.
        #expect(AppSettings.default.boardTheme == .midnight)
        #expect(AppSettings.default.pieceSet == .caliente)
        #expect(AppSettings.default.pieceStyle == .carved)
        #expect(AppSettings.defaultBoardThemeID == BoardTheme.midnight.id)
    }
}
