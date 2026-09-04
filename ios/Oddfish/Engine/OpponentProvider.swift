import Foundation

/// Decides who the player is actually up against.
///
/// There is exactly one engine in the process — Stockfish keeps its state in
/// globals, and its output stream has a single consumer — so the booted
/// opponent is shared by every game. Booting is attempted once; if it fails,
/// every caller gets the built-in search and the game plays on.
@MainActor
enum OpponentProvider {
    private static var bootTask: Task<any ChessOpponent, Never>?

    /// The strongest opponent this device can run. Safe to call from anywhere,
    /// any number of times: concurrent callers all await the same boot.
    static func shared() async -> any ChessOpponent {
        if let bootTask { return await bootTask.value }

        let task = Task<any ChessOpponent, Never> {
            if let engine = await StockfishOpponent() { return engine }
            return LocalOpponent()
        }
        bootTask = task
        return await task.value
    }

    /// Starts the engine without waiting for it. Called at launch so the first
    /// game does not pay the handshake.
    static func warmUp() {
        Task { _ = await shared() }
    }

    /// Stops any search in progress.
    ///
    /// Stockfish runs on its own thread and does not know the app has gone to
    /// the background. Left alone it keeps a core busy behind the home screen,
    /// which drains the battery and is a good way to be terminated by the
    /// system. Nothing is torn down — the engine and its 107 MB of networks stay
    /// loaded so returning to the app is instant.
    static func suspendSearches() async {
        guard let opponent = await bootTask?.value else { return }
        guard let service = opponent as? any ChessAnalysisService else { return }
        await service.cancelAnalysis()
    }
}
