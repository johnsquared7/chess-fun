import Foundation

/// Immutable input that may safely cross the main-actor boundary before a bot search.
nonisolated struct BotSearchInput: Hashable, Sendable {
    let position: Position
    /// Already-filtered root moves for variants. Pass standard legal moves for classic chess.
    let legalRootMoves: [Move]
    let history: [Position]
    let configuration: ChessBot.Configuration

    init(
        position: Position,
        legalRootMoves: [Move]? = nil,
        history: [Position] = [],
        configuration: ChessBot.Configuration = .init()
    ) {
        self.position = position
        self.legalRootMoves = legalRootMoves ?? ChessEngine.legalMoves(in: position)
        self.history = history
        self.configuration = configuration
    }
}

nonisolated enum ChessBot {
    struct Configuration: Codable, Hashable, Sendable {
        var depth: Int
        /// Selects deterministically from the best N moves. Zero preserves the principal variation.
        var variationWindow: Int
        var seed: UInt64

        init(rating: OpponentRating = .default, seed: UInt64 = 0) {
            switch rating.rawValue {
            case ..<1_320:
                self.depth = 1
                self.variationWindow = 3
            case ..<2_200:
                self.depth = 1
                self.variationWindow = 2
            case ..<3_190:
                self.depth = 2
                self.variationWindow = 1
            case 3_190:
                self.depth = 3
                self.variationWindow = 0
            default:
                self.depth = 4
                self.variationWindow = 0
            }
            self.seed = seed
        }

        init(depth: Int, variationWindow: Int = 0, seed: UInt64 = 0) {
            self.depth = max(1, depth)
            self.variationWindow = max(0, variationWindow)
            self.seed = seed
        }
    }

    /// Returns only a member of `input.legalRootMoves`, or nil when the root has no moves.
    static func chooseMove(for input: BotSearchInput) -> Move? {
        // One generation, hoisted out of the filter. Inside it, every candidate
        // root move regenerated the whole legal-move list to check itself
        // against it.
        let legal = Set(ChessEngine.legalMoves(in: input.position))
        let rootMoves = input.legalRootMoves.filter(legal.contains)
        guard !rootMoves.isEmpty else { return nil }

        var scored: [(move: Move, score: Int)] = []
        scored.reserveCapacity(rootMoves.count)
        var history = input.history
        history.append(input.position)
        let orderedRoots = ordered(rootMoves, in: input.position)
        for move in orderedRoots {
            // Legal by the filter above, so this skips `apply`'s validation
            // scan — which is another full legal-move generation per move.
            guard let next = ChessEngine.applyKnownLegal(move, to: input.position) else { continue }
            let score = -negamax(
                position: next,
                history: &history,
                depth: input.configuration.depth - 1,
                alpha: -infinity,
                beta: infinity
            )
            scored.append((move, score))
        }
        guard !scored.isEmpty else { return rootMoves.first }
        scored.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.move < rhs.move : lhs.score > rhs.score
        }

        let window = min(input.configuration.variationWindow + 1, scored.count)
        guard window > 1 else { return scored[0].move }
        let fingerprint = stableFingerprint(input.position.repetitionKey)
        let index = Int((fingerprint ^ input.configuration.seed) % UInt64(window))
        return scored[index].move
    }

    static func chooseMove(
        in position: Position,
        legalMoves: [Move]? = nil,
        history: [Position] = [],
        configuration: Configuration = .init()
    ) -> Move? {
        chooseMove(for: BotSearchInput(position: position, legalRootMoves: legalMoves, history: history, configuration: configuration))
    }

    private static let infinity = 1_000_000
    private static let mateScore = 100_000

    /// `history` is one buffer pushed and popped down the tree rather than a
    /// fresh array per node: it is only read for repetition detection, and
    /// copying it at every node cost an allocation per node for nothing.
    private static func negamax(position: Position, history: inout [Position], depth: Int, alpha initialAlpha: Int, beta: Int) -> Int {
        switch ChessEngine.outcome(for: position, history: history) {
        case .checkmate: return -mateScore - depth
        case .stalemate, .draw: return 0
        case .ongoing: break
        }
        // A leaf is the common case, and it needs no move list: `outcome` above
        // has already answered the only question it asks. Generating one here
        // is what made the old search pay for a full list at every leaf.
        guard depth > 0 else { return evaluate(position) }

        var alpha = initialAlpha
        var best = -infinity
        history.append(position)
        defer { history.removeLast() }
        for move in ordered(ChessEngine.legalMoves(in: position), in: position) {
            guard let next = ChessEngine.applyKnownLegal(move, to: position) else { continue }
            let score = -negamax(position: next, history: &history, depth: depth - 1, alpha: -beta, beta: -alpha)
            best = max(best, score)
            alpha = max(alpha, score)
            if alpha >= beta { break }
        }
        return best
    }

    /// Positive scores favour the side to move, making this directly suitable for negamax.
    private static func evaluate(_ position: Position) -> Int {
        var score = 0
        for square in position.squares() {
            guard let piece = position.piece(at: square) else { continue }
            let base: Int
            switch piece.kind {
            case .pawn: base = 100
            case .knight: base = 320
            case .bishop: base = 330
            case .rook: base = 500
            case .queen: base = 900
            case .king: base = 0
            }
            // A small center/advancement term breaks otherwise arbitrary opening ties.
            let center = 6 - (abs(2 * square.file - 7) + abs(2 * square.rank - 7)) / 2
            let advancement = piece.kind == .pawn ? (piece.color == .white ? square.rank : 7 - square.rank) * 3 : 0
            let contribution = base + center + advancement
            score += piece.color == position.sideToMove ? contribution : -contribution
        }
        let mobility = ChessEngine.pseudoLegalMoves(in: position).count
        return score + mobility
    }

    /// Each move is scored once and the scores are sorted, rather than scoring
    /// both sides of every comparison — which recomputed `moveOrder` O(n log n)
    /// times per node for an n-element list.
    private static func ordered(_ moves: [Move], in position: Position) -> [Move] {
        var scored: [(move: Move, order: Int)] = []
        scored.reserveCapacity(moves.count)
        for move in moves {
            scored.append((move: move, order: moveOrder(move, in: position)))
        }
        scored.sort { lhs, rhs in
            lhs.order == rhs.order ? lhs.move < rhs.move : lhs.order > rhs.order
        }
        return scored.map(\.move)
    }

    private static func moveOrder(_ move: Move, in position: Position) -> Int {
        var score = 0
        if move.flags.contains(.capture) {
            let captured = move.flags.contains(.enPassant) ? PieceKind.pawn : position.piece(at: move.to)?.kind
            score += 10_000 + value(of: captured)
            score -= value(of: position.piece(at: move.from)?.kind)
        }
        if let promotion = move.promotion { score += 8_000 + value(of: promotion) }
        return score
    }

    private static func value(of kind: PieceKind?) -> Int {
        switch kind {
        case .pawn?: 100
        case .knight?: 320
        case .bishop?: 330
        case .rook?: 500
        case .queen?: 900
        case .king?: 10_000
        case nil: 0
        }
    }

    private static func stableFingerprint(_ value: String) -> UInt64 {
        // Swift's `hashValue` intentionally changes between launches. FNV-1a keeps
        // light variation reproducible for a saved game and in automated tests.
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }
}
