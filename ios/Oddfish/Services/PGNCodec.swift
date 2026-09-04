import Foundation

nonisolated enum PGNError: LocalizedError, Equatable {
    case emptyGame
    case invalidStartingPosition
    case invalidMove(String, ply: Int)

    var errorDescription: String? {
        switch self {
        case .emptyGame:
            "This PGN has no moves to import."
        case .invalidStartingPosition:
            "The PGN's starting position is not a valid FEN."
        case .invalidMove(let token, let ply):
            "Move \(ply) (\(token)) is not legal from the recorded position."
        }
    }
}

nonisolated struct ReplayPly: Hashable, Sendable, Identifiable {
    let number: Int
    let move: Move
    let san: String
    let positionBefore: Position
    let positionAfter: Position

    var id: Int { number }
}

nonisolated struct GameReplay: Hashable, Sendable {
    let startingPosition: Position
    let plies: [ReplayPly]

    var positions: [Position] { [startingPosition] + plies.map(\.positionAfter) }
    var sanMoves: [String] { plies.map(\.san) }

    init(record: GameRecord) throws {
        try self.init(
            notation: record.notation ?? "",
            startingPosition: record.startingPosition,
            mode: GameMode(rawValue: record.modeID) ?? .classic,
            playerColor: record.playerColor,
            parameters: record.parameters
        )
    }

    init(
        notation: String,
        startingPosition: Position,
        mode: GameMode,
        playerColor: PieceColor,
        parameters: GimmickParameters
    ) throws {
        let tokens = ChessNotation.moveTokens(from: notation)
        var position = startingPosition
        var variantState = VariantState()
        var plies: [ReplayPly] = []
        var completedPlayerTurns = 0
        var isBonusMove = false
        // Only TempoFish and ComboFish can keep the player on move, so only
        // their replays need the per-ply terminal check below. `outcome` runs
        // a full legal-move generation plus a scan over every prior position,
        // which is what made long games quadratic.
        let needsTerminalScan = mode.gimmickRule.canGrantBonusMoves
        var priorPositions: [Position] = needsTerminalScan ? [startingPosition] : []

        for (offset, token) in tokens.enumerated() {
            let legalMoves = VariantRules.legalMoves(
                in: position,
                state: variantState,
                configuration: mode.configuration
            )
            guard let move = ChessNotation.move(matching: token, in: position, legalMoves: legalMoves),
                  let movingPiece = position.piece(at: move.from),
                  let rawNext = ChessEngine.applyKnownLegal(move, to: position) else {
                throw PGNError.invalidMove(token, ply: offset + 1)
            }

            let san = ChessNotation.san(for: move, in: position, legalMoves: legalMoves, positionAfter: rawNext)
            var next = rawNext
            let wasBonusMove = isBonusMove
            if movingPiece.color == playerColor {
                if wasBonusMove {
                    isBonusMove = false
                } else {
                    completedPlayerTurns += 1
                }
            }

            let wasCapture = move.isCapture
            let givesCheck = ChessEngine.isInCheck(next.sideToMove, in: next)
            let ply = GimmickPly(
                move: move,
                movingPiece: movingPiece,
                positionBefore: position,
                positionAfter: next,
                ply: offset + 1,
                wasCapture: wasCapture,
                givesCheck: givesCheck,
                analysis: nil,
                playerColor: playerColor
            )
            if needsTerminalScan {
                let isTerminal = ChessEngine.outcome(for: next, history: priorPositions).isTerminal
                if !isTerminal,
                   movingPiece.color == playerColor,
                   !wasBonusMove,
                   mode.gimmickRule.grantsBonusMove(
                       after: ply,
                       completedPlayerTurns: completedPlayerTurns,
                       parameters: parameters
                   ) {
                    next = next.replacingSideToMove(playerColor, clearEnPassant: true)
                    isBonusMove = true
                }
            }

            variantState = VariantRules.applying(
                move,
                in: position,
                state: variantState,
                configuration: mode.configuration
            )
            if needsTerminalScan { priorPositions.append(position) }
            plies.append(ReplayPly(
                number: offset + 1,
                move: move,
                san: san,
                positionBefore: position,
                positionAfter: next
            ))
            position = next
        }

        self.startingPosition = startingPosition
        self.plies = plies
    }
}

nonisolated enum ChessNotation {
    static func notation(
        for moves: [Move],
        startingPosition: Position,
        mode: GameMode,
        playerColor: PieceColor,
        parameters: GimmickParameters
    ) -> String {
        let coordinates = moves.map(uci).joined(separator: " ")
        guard let replay = try? GameReplay(
            notation: coordinates,
            startingPosition: startingPosition,
            mode: mode,
            playerColor: playerColor,
            parameters: parameters
        ) else { return coordinates }
        return replay.sanMoves.joined(separator: " ")
    }

    static func moveTokens(from text: String) -> [String] {
        let stripped = strippingCommentsAndVariations(from: text)
        return stripped
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .compactMap(cleanMoveToken)
    }

    static func move(matching token: String, in position: Position, legalMoves: [Move]) -> Move? {
        if let coordinate = legalMoves.first(where: { uci($0).lowercased() == token.lowercased() }) {
            return coordinate
        }
        guard let parsed = ParsedSAN(token) else { return nil }
        let matches = legalMoves.filter { parsed.matches($0, in: position) }
        return matches.count == 1 ? matches[0] : nil
    }

    /// A SAN token broken into matchable parts without rendering candidates.
    /// `move(matching:)` used to render every legal move's full SAN per ply —
    /// each render applying the move and running a full outcome scan — which
    /// made replaying one long game cost seconds on the main thread.
    private nonisolated struct ParsedSAN {
        var kingsideCastle = false
        var queensideCastle = false
        var piece: PieceKind = .pawn
        var fromFile: Int?
        var fromRank: Int?
        var isCapture = false
        var toFile = 0
        var toRank = 0
        var promotion: PieceKind?

        init?(_ token: String) {
            let text = ChessNotation.normalizedSAN(token)
            if text == "O-O-O" { queensideCastle = true; return }
            if text == "O-O" { kingsideCastle = true; return }
            var chars = Array(text)
            // Piece letter, uppercase only — mirroring what san() emits.
            if let first = chars.first, "KQRBN".contains(first) {
                piece = Self.kind(for: first) ?? .pawn
                chars.removeFirst()
            }
            // Promotion suffix: "=Q" as emitted, or a bare trailing letter.
            if chars.count >= 3, chars[chars.count - 2] == "=",
               let promo = Self.kind(for: chars[chars.count - 1]) {
                promotion = promo
                chars.removeLast(2)
            } else if chars.count >= 3, piece == .pawn,
                      let promo = Self.kind(for: chars[chars.count - 1]) {
                promotion = promo
                chars.removeLast()
            }
            // Destination is always the last two squares.
            guard chars.count >= 2,
                  let file = Self.fileIndex(chars[chars.count - 2]),
                  let rank = Self.rankIndex(chars[chars.count - 1]) else { return nil }
            toFile = file
            toRank = rank
            chars.removeLast(2)
            if chars.last == "x" { isCapture = true; chars.removeLast() }
            // Disambiguation: a file and/or a rank, in that order.
            switch chars.count {
            case 0: break
            case 1:
                if let file = Self.fileIndex(chars[0]) { fromFile = file } else if let rank = Self.rankIndex(chars[0]) { fromRank = rank } else { return nil }
            case 2:
                guard let file = Self.fileIndex(chars[0]), let rank = Self.rankIndex(chars[1]) else { return nil }
                fromFile = file
                fromRank = rank
            default: return nil
            }
            // Pawns state their file only when capturing; anything else was
            // never emitted, so it matches nothing.
            if piece == .pawn {
                if isCapture {
                    guard chars.count == 1, fromFile != nil else { return nil }
                } else {
                    guard chars.isEmpty else { return nil }
                }
            }
        }

        func matches(_ move: Move, in position: Position) -> Bool {
            if kingsideCastle { return move.flags.contains(.castleKingside) }
            if queensideCastle { return move.flags.contains(.castleQueenside) }
            guard position.piece(at: move.from)?.kind == piece,
                  move.to.file == toFile, move.to.rank == toRank,
                  move.isCapture == isCapture,
                  move.promotion == promotion else { return false }
            if let fromFile, move.from.file != fromFile { return false }
            if let fromRank, move.from.rank != fromRank { return false }
            return true
        }

        private static func kind(for character: Character) -> PieceKind? {
            switch character {
            case "K": .king
            case "Q": .queen
            case "R": .rook
            case "B": .bishop
            case "N": .knight
            default: nil
            }
        }

        private static func fileIndex(_ character: Character) -> Int? {
            guard let ascii = character.asciiValue, character >= "a", character <= "h" else { return nil }
            return Int(ascii - Character("a").asciiValue!)
        }

        private static func rankIndex(_ character: Character) -> Int? {
            guard let digit = character.wholeNumberValue, character >= "1", character <= "8" else { return nil }
            return digit - 1
        }
    }

    /// SAN when the resulting position is already known (replay), without
    /// re-applying the move or running a full outcome scan for the suffix.
    static func san(for move: Move, in position: Position, legalMoves: [Move], positionAfter: Position) -> String {
        sanCore(for: move, in: position, legalMoves: legalMoves) + checkSuffix(positionAfter: positionAfter)
    }

    static func san(for move: Move, in position: Position, legalMoves: [Move]? = nil) -> String {
        guard let piece = position.piece(at: move.from),
              let next = ChessEngine.apply(move, to: position) else {
            return uci(move)
        }
        _ = piece
        let legal = legalMoves ?? ChessEngine.legalMoves(in: position)
        return sanCore(for: move, in: position, legalMoves: legal) + checkSuffix(positionAfter: next)
    }

    /// "+" and "#" without `outcome`'s fifty-move, repetition, and material
    /// scans. Those decide draws, which never take a suffix; only mate does,
    /// and mate is exactly "in check with no legal reply".
    private static func checkSuffix(positionAfter next: Position) -> String {
        guard ChessEngine.isInCheck(next.sideToMove, in: next) else { return "" }
        return ChessEngine.legalMoves(in: next).isEmpty ? "#" : "+"
    }

    private static func sanCore(for move: Move, in position: Position, legalMoves: [Move]) -> String {
        guard let piece = position.piece(at: move.from) else { return uci(move) }

        var notation: String
        if move.flags.contains(.castleKingside) {
            notation = "O-O"
        } else if move.flags.contains(.castleQueenside) {
            notation = "O-O-O"
        } else {
            let legal = legalMoves
            let capture = move.isCapture
            if piece.kind == .pawn {
                notation = capture ? String(move.from.algebraic.prefix(1)) : ""
            } else {
                notation = pieceLetter(piece.kind)
                let alternatives = legal.filter { candidate in
                    candidate != move
                        && candidate.to == move.to
                        && position.piece(at: candidate.from)?.kind == piece.kind
                }
                if !alternatives.isEmpty {
                    let sameFile = alternatives.contains { $0.from.file == move.from.file }
                    let sameRank = alternatives.contains { $0.from.rank == move.from.rank }
                    if !sameFile {
                        notation += String(move.from.algebraic.prefix(1))
                    } else if !sameRank {
                        notation += String(move.from.algebraic.suffix(1))
                    } else {
                        notation += move.from.algebraic
                    }
                }
            }
            if capture { notation += "x" }
            notation += move.to.algebraic
            if let promotion = move.promotion {
                notation += "=\(pieceLetter(promotion))"
            }
        }

        return notation
    }

    static func uci(_ move: Move) -> String {
        let promotedTo = move.promotion.map { String($0.fenCharacter) } ?? ""
        return "\(move.from.algebraic)\(move.to.algebraic)\(promotedTo)"
    }

    private static func pieceLetter(_ kind: PieceKind) -> String {
        switch kind {
        case .king: "K"
        case .queen: "Q"
        case .rook: "R"
        case .bishop: "B"
        case .knight: "N"
        case .pawn: ""
        }
    }

    private static func cleanMoveToken(_ raw: String) -> String? {
        var token = raw
        while let dot = token.firstIndex(of: "."),
              token[..<dot].allSatisfy(\.isNumber) {
            token = String(token[token.index(after: dot)...])
            while token.first == "." { token.removeFirst() }
        }
        guard !token.isEmpty,
              !["1-0", "0-1", "1/2-1/2", "*"].contains(token),
              !token.hasPrefix("$") else { return nil }
        return token
    }

    private static func normalizedSAN(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "0-0-0", with: "O-O-O")
            .replacingOccurrences(of: "0-0", with: "O-O")
            .replacingOccurrences(of: "e.p.", with: "")
            .replacingOccurrences(of: "ep", with: "")
        while let last = value.last, "+#!?".contains(last) { value.removeLast() }
        return value
    }

    private static func strippingCommentsAndVariations(from text: String) -> String {
        var output = ""
        var braceDepth = 0
        var variationDepth = 0
        var inLineComment = false
        for character in text {
            if inLineComment {
                if character == "\n" { inLineComment = false; output.append(" ") }
                continue
            }
            if character == ";" && braceDepth == 0 && variationDepth == 0 {
                inLineComment = true
                continue
            }
            if character == "{" { braceDepth += 1; continue }
            if character == "}" { braceDepth = max(0, braceDepth - 1); continue }
            if braceDepth > 0 { continue }
            if character == "(" { variationDepth += 1; continue }
            if character == ")" { variationDepth = max(0, variationDepth - 1); continue }
            if variationDepth == 0 { output.append(character) }
        }
        return output
    }
}

nonisolated enum PGNCodec {
    static func export(_ record: GameRecord) -> String {
        export(record, replay: try? GameReplay(record: record))
    }

    /// Export reusing an already-built replay. `GameReviewView` replays once
    /// and shares it here instead of paying for the walk twice.
    static func export(_ record: GameRecord, replay: GameReplay?) -> String {
        let mode = GameMode(rawValue: record.modeID) ?? .classic
        let result = resultToken(for: record)
        let date = formattedDate(record.date)
        let white = record.playerColor == .white ? "Player" : "Oddfish"
        let black = record.playerColor == .black ? "Player" : "Oddfish"
        var tags: [(String, String)] = [
            ("Event", "Oddfish · \(mode.title)"),
            ("Site", "Oddfish iOS"),
            ("Date", date),
            ("Round", "-"),
            ("White", white),
            ("Black", black),
            ("Result", result),
            ("OddfishMode", mode.rawValue),
            ("OddfishPlayerColor", record.playerColor.rawValue)
        ]
        if record.startingPosition != .starting {
            tags.append(("SetUp", "1"))
            tags.append(("FEN", record.startingPosition.fen))
        }
        if let rating = record.startingRating { tags.append(("OddfishStartingElo", "\(rating)")) }
        if let rating = record.endingRating { tags.append(("OddfishEndingElo", "\(rating)")) }
        if record.duration > 0 { tags.append(("OddfishDuration", "\(Int(record.duration.rounded()))")) }
        if !record.parameterValues.isEmpty {
            let values = record.parameterValues.keys.sorted().map { key in
                "\(key)=\(compactNumber(record.parameterValues[key] ?? 0))"
            }.joined(separator: ";")
            tags.append(("OddfishParameters", values))
        }
        if let award = record.award {
            tags.append(("OddfishCrowns", "\(award.tier)"))
            tags.append(("OddfishScore", "\(award.score.value)"))
            tags.append(("OddfishScoreMetric", award.score.metric.rawValue))
        }
        if record.isImported { tags.append(("OddfishImported", "true")) }

        let tagText = tags.map { "[\($0.0) \"\(escapeTag($0.1))\"]" }.joined(separator: "\n")
        let moveText: String
        if let replay {
            moveText = numberedMoveText(replay: replay, result: result)
        } else {
            let raw = record.notation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            moveText = raw.isEmpty ? result : "\(raw) \(result)"
        }
        return "\(tagText)\n\n\(moveText)\n"
    }

    static func importRecord(from text: String) throws -> GameRecord {
        let parsed = parse(text)
        let mode = mode(from: parsed.tags["OddfishMode"] ?? parsed.tags["Variant"])
        let playerColor = PieceColor(rawValue: parsed.tags["OddfishPlayerColor"]?.lowercased() ?? "") ?? .white
        let startingPosition: Position
        if let fen = parsed.tags["FEN"] {
            guard let decoded = Position(fen: fen) else { throw PGNError.invalidStartingPosition }
            startingPosition = decoded
        } else {
            startingPosition = mode.gimmickRule.startingPosition(playerColor: playerColor)
        }
        let parameters = parseParameters(parsed.tags["OddfishParameters"])
        let replay = try GameReplay(
            notation: parsed.moveText,
            startingPosition: startingPosition,
            mode: mode,
            playerColor: playerColor,
            parameters: parameters
        )
        guard !replay.plies.isEmpty else { throw PGNError.emptyGame }

        let resultToken = parsed.tags["Result"] ?? resultToken(in: parsed.moveText)
        return GameRecord(
            modeID: mode.rawValue,
            result: gameResult(from: resultToken, playerColor: playerColor),
            duration: TimeInterval(Int(parsed.tags["OddfishDuration"] ?? "") ?? 0),
            moveCount: replay.plies.count,
            date: parsed.tags["Date"].flatMap(parseDate) ?? Date(),
            notation: replay.sanMoves.joined(separator: " "),
            startingFEN: startingPosition.fen,
            playerColorID: playerColor.rawValue,
            startingRating: Int(parsed.tags["OddfishStartingElo"] ?? ""),
            endingRating: Int(parsed.tags["OddfishEndingElo"] ?? ""),
            origin: .imported,
            parameterValues: parameters.storedValues
        )
    }

    private static func parse(_ text: String) -> (tags: [String: String], moveText: String) {
        var tags: [String: String] = [:]
        var moveLines: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]"),
               let space = trimmed.firstIndex(of: " ") {
                let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<space])
                let rest = trimmed[trimmed.index(after: space)..<trimmed.index(before: trimmed.endIndex)]
                    .trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("\""), rest.hasSuffix("\"") {
                    let value = String(rest.dropFirst().dropLast())
                        .replacingOccurrences(of: "\\\"", with: "\"")
                        .replacingOccurrences(of: "\\\\", with: "\\")
                    tags[key] = value
                }
            } else if !trimmed.isEmpty {
                moveLines.append(trimmed)
            }
        }
        return (tags, moveLines.joined(separator: " "))
    }

    private static func mode(from value: String?) -> GameMode {
        guard let value else { return .classic }
        if let direct = GameMode(rawValue: value) { return direct }
        let normalized = value.lowercased().filter(\.isLetter)
        return GameMode.allCases.first {
            $0.title.lowercased().filter(\.isLetter) == normalized
                || $0.rawValue.lowercased().filter(\.isLetter) == normalized
        } ?? (normalized == "standard" || normalized == "standardchess" ? .classic : .classic)
    }

    private static func parseParameters(_ value: String?) -> GimmickParameters {
        guard let value else { return GimmickParameters() }
        let pairs = value.split(separator: ";").compactMap { component -> (String, Double)? in
            let pieces = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard pieces.count == 2, let number = Double(pieces[1]) else { return nil }
            return (pieces[0], number)
        }
        return GimmickParameters(values: Dictionary(uniqueKeysWithValues: pairs))
    }

    private static func gameResult(from token: String?, playerColor: PieceColor) -> GameResult {
        switch token {
        case "1-0": playerColor == .white ? .win : .loss
        case "0-1": playerColor == .black ? .win : .loss
        case "1/2-1/2": .draw
        default: .unknown
        }
    }

    private static func resultToken(for record: GameRecord) -> String {
        switch record.result {
        case .win: record.playerColor == .white ? "1-0" : "0-1"
        case .loss, .abandoned: record.playerColor == .white ? "0-1" : "1-0"
        case .draw: "1/2-1/2"
        case .unknown: "*"
        }
    }

    private static func resultToken(in moveText: String) -> String? {
        moveText.split(whereSeparator: \.isWhitespace).map(String.init).last {
            ["1-0", "0-1", "1/2-1/2", "*"].contains($0)
        }
    }

    private static func numberedMoveText(replay: GameReplay, result: String) -> String {
        var tokens: [String] = []
        for ply in replay.plies {
            if ply.positionBefore.sideToMove == .white {
                tokens.append("\(ply.positionBefore.fullmoveNumber).")
            } else if tokens.isEmpty || ply.number > 1 && replay.plies[ply.number - 2].positionBefore.sideToMove == .black {
                tokens.append("\(ply.positionBefore.fullmoveNumber)...")
            }
            tokens.append(ply.san)
        }
        tokens.append(result)
        return wrap(tokens: tokens, width: 80)
    }

    private static func wrap(tokens: [String], width: Int) -> String {
        var lines: [String] = []
        var current = ""
        for token in tokens {
            if current.isEmpty {
                current = token
            } else if current.count + token.count + 1 <= width {
                current += " \(token)"
            } else {
                lines.append(current)
                current = token
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.joined(separator: "\n")
    }

    private static func escapeTag(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func compactNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func formattedDate(_ date: Date) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        return String(format: "%04d.%02d.%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func parseDate(_ value: String) -> Date? {
        let pieces = value.split(separator: ".").compactMap { Int($0) }
        guard pieces.count == 3 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = pieces[0]
        components.month = pieces[1]
        components.day = pieces[2]
        return components.date
    }
}

extension GameRecord {
    nonisolated var pgn: String { PGNCodec.export(self) }
}
