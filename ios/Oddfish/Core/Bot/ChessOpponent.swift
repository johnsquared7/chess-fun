import Foundation

/// Everything an opponent needs to choose a move, and nothing else.
///
/// `allowedMoves` is the contract that keeps variants correct. The session has
/// already applied the mode's rules, so an opponent must choose from this list
/// rather than generating its own — that is how Restfish's rest restriction
/// binds an engine that knows nothing about Restfish.
nonisolated struct OpponentRequest: Hashable, Sendable {
    let position: Position
    let allowedMoves: [Move]
    /// Earlier positions, for repetition awareness.
    let history: [Position]
    let rating: OpponentRating
    /// Upper bound on thinking time.
    let thinkingTime: Duration

    init(
        position: Position,
        allowedMoves: [Move],
        history: [Position] = [],
        rating: OpponentRating = .default,
        thinkingTime: Duration? = nil
    ) {
        self.position = position
        self.allowedMoves = allowedMoves
        self.history = history
        self.rating = rating
        self.thinkingTime = thinkingTime ?? rating.thinkingTime
    }
}

/// A source of opponent moves.
///
/// The point of this protocol is that the game does not care whether it is
/// playing a bundled engine or the small built-in search. Both must obey the
/// same rule: the returned move is a member of `request.allowedMoves`, or nil.
nonisolated protocol ChessOpponent: Sendable {
    /// A short name for diagnostics and for telling the player who they beat.
    var name: String { get }

    /// Chooses a move. Returning nil means "no opinion" — the caller falls back
    /// to a validated legal move rather than trusting anything unchecked.
    func bestMove(for request: OpponentRequest) async -> Move?

    /// Resets any state carried between searches. Called when a game starts or
    /// restarts, so a stateful engine does not reason about a previous game.
    func newGame() async
}

extension ChessOpponent {
    func newGame() async {}
}

/// Supplies an opponent, possibly after booting one.
///
/// A game is created synchronously but the engine boots asynchronously, so the
/// session holds one of these rather than a ready-made opponent.
typealias OpponentResolver = @Sendable () async -> any ChessOpponent

/// The built-in search, wrapped in the shared protocol.
///
/// This is not only a fallback. It is deterministic and runs without any engine
/// process, which makes it what the test suite plays against.
nonisolated struct LocalOpponent: ChessOpponent {
    let name = "Oddfish"

    func bestMove(for request: OpponentRequest) async -> Move? {
        let input = BotSearchInput(
            position: request.position,
            legalRootMoves: request.allowedMoves,
            history: request.history,
            configuration: ChessBot.Configuration(rating: request.rating)
        )
        return await Task.detached(priority: .userInitiated) {
            ChessBot.chooseMove(for: input)
        }.value
    }
}
