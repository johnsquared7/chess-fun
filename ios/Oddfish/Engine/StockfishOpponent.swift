import Foundation

nonisolated struct StockfishBootResult: Sendable {
    let succeeded: Bool
    let report: String
}

/// A Swift value copied from Stockfish 18's structured `InfoFull` callback.
/// Stage 2 will turn this stream into the app's analysis service; Stage 0 keeps
/// the boundary structured so no UCI output parsing has to return later.
nonisolated struct StockfishAnalysisInfo: Sendable {
    enum Score: Sendable {
        case centipawns(Int)
        case mate(plies: Int)
        case tablebase(distance: Int)
    }

    let depth: Int
    let selectiveDepth: Int
    let multiPV: Int
    let score: Score
    let elapsedMilliseconds: UInt64
    let nodes: UInt64
    let nodesPerSecond: UInt64
    let tablebaseHits: UInt64
    let hashFull: Int
    let principalVariation: String
}

/// Analysis and completion callbacks share one stream so their original C++
/// ordering is preserved. In particular, every final info update is consumed
/// before the best-move event closes that search transaction.
nonisolated enum StockfishEngineEvent: Sendable {
    case analysis(StockfishAnalysisInfo)
    case bestMove(String)
}

/// Owns the one process-wide Stockfish 18 `Engine` instance.
///
/// Startup happens on the C++ bridge's background thread because allocating and
/// loading 107 MB of networks must never stall the first SwiftUI frame. Engine
/// callbacks are copied immediately into bounded `AsyncStream`s before their C
/// pointers expire.
nonisolated final class StockfishProcess: @unchecked Sendable {
    static let shared = StockfishProcess()
    static let bigNetworkName = "nn-c288c895ea92"
    static let smallNetworkName = "nn-37f18f62d772"

    let readyEvents: AsyncStream<StockfishBootResult>
    let engineEvents: AsyncStream<StockfishEngineEvent>

    private let readyContinuation: AsyncStream<StockfishBootResult>.Continuation
    private let engineEventContinuation: AsyncStream<StockfishEngineEvent>.Continuation

    private init() {
        var capturedReady: AsyncStream<StockfishBootResult>.Continuation!
        readyEvents = AsyncStream(bufferingPolicy: .bufferingNewest(1)) {
            capturedReady = $0
        }
        readyContinuation = capturedReady

        var capturedEvent: AsyncStream<StockfishEngineEvent>.Continuation!
        // MultiPV analysis can emit one update per legal root move at every
        // depth. Keep enough recent values for a full ordinary position rather
        // than dropping ranks before the actor can assemble a snapshot.
        engineEvents = AsyncStream(bufferingPolicy: .bufferingNewest(4_096)) {
            capturedEvent = $0
        }
        engineEventContinuation = capturedEvent
    }

    /// Begins asynchronous boot using the networks copied into the app bundle.
    /// Returns false when either resource is absent or startup was already begun.
    @discardableResult
    func start(bundle: Bundle = .main) -> Bool {
        guard let bigNetwork = bundle.url(
            forResource: Self.bigNetworkName,
            withExtension: "nnue"
        ), let smallNetwork = bundle.url(
            forResource: Self.smallNetworkName,
            withExtension: "nnue"
        ) else {
            return false
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let didStart = bigNetwork.path.withCString { bigPath in
            smallNetwork.path.withCString { smallPath in
                oddfish_engine_start(
                    bigPath,
                    smallPath,
                    { success, report, context in
                        guard let context else { return }
                        let process = Unmanaged<StockfishProcess>
                            .fromOpaque(context)
                            .takeUnretainedValue()
                        process.readyContinuation.yield(StockfishBootResult(
                            succeeded: success == 1,
                            report: report.map(String.init(cString:)) ?? ""
                        ))
                    },
                    { bestMove, _, context in
                        guard let bestMove, let context else { return }
                        let process = Unmanaged<StockfishProcess>
                            .fromOpaque(context)
                            .takeUnretainedValue()
                        process.engineEventContinuation.yield(
                            .bestMove(String(cString: bestMove))
                        )
                    },
                    { info, context in
                        guard let info, let context else { return }
                        let process = Unmanaged<StockfishProcess>
                            .fromOpaque(context)
                            .takeUnretainedValue()
                        let source = info.pointee
                        let score: StockfishAnalysisInfo.Score
                        switch source.score_kind.rawValue {
                        case OddfishEngineScoreMate.rawValue:
                            score = .mate(plies: Int(source.score_value))
                        case OddfishEngineScoreTablebase.rawValue:
                            score = .tablebase(distance: Int(source.score_value))
                        default:
                            score = .centipawns(Int(source.score_value))
                        }
                        process.engineEventContinuation.yield(.analysis(StockfishAnalysisInfo(
                            depth: Int(source.depth),
                            selectiveDepth: Int(source.selective_depth),
                            multiPV: Int(source.multi_pv),
                            score: score,
                            elapsedMilliseconds: source.time_ms,
                            nodes: source.nodes,
                            nodesPerSecond: source.nodes_per_second,
                            tablebaseHits: source.tablebase_hits,
                            hashFull: Int(source.hash_full),
                            principalVariation: source.principal_variation
                                .map(String.init(cString:)) ?? ""
                        )))
                    },
                    context
                )
            }
        }
        return didStart == 1
    }

    var isRunning: Bool { oddfish_engine_is_running() == 1 }
    var networksLoaded: Bool { oddfish_engine_networks_loaded() == 1 }

    @discardableResult
    func setPosition(fen: String) -> Bool {
        fen.withCString { oddfish_engine_set_position($0) == 1 }
    }

    @discardableResult
    func setStrength(_ band: OpponentEngineBand) -> Bool {
        switch band {
        case .skillLevel(let level):
            oddfish_engine_set_skill_level(Int32(level)) == 1
        case .calibratedElo(let rating):
            oddfish_engine_set_elo(Int32(rating)) == 1
        case .fullStrength:
            oddfish_engine_set_full_strength() == 1
        }
    }

    @discardableResult
    func setMultiPV(_ count: Int) -> Bool {
        oddfish_engine_set_multi_pv(Int32(count)) == 1
    }

    @discardableResult
    func go(thinkingTime: Duration?, depth: Int = 0, allowedMoves: [Move]) -> Bool {
        let moves = allowedMoves.map(StockfishOpponent.uciString(for:)).joined(separator: " ")
        let milliseconds = thinkingTime.map { max(50, $0.milliseconds) } ?? 0
        return moves.withCString {
            oddfish_engine_go(Int32(milliseconds), Int32(max(0, depth)), $0) == 1
        }
    }

    func stop() {
        oddfish_engine_stop()
    }

    func newGame() {
        oddfish_engine_new_game()
    }
}

/// Stockfish 18 behind the app's opponent protocol.
///
/// The engine receives a structured position, limits object, and callback. Its
/// root search is restricted to the moves the session already approved, which
/// preserves the same variant contract as the previous UCI bridge.
actor StockfishOpponent: ChessOpponent, ChessAnalysisService {
    nonisolated let name = "Stockfish"

    private let process: StockfishProcess
    private var bufferedBestMoves: [String] = []
    private var bestMoveWaiter: CheckedContinuation<String?, Never>?
    private var bufferedBootResults: [StockfishBootResult] = []
    private var bootWaiter: CheckedContinuation<StockfishBootResult?, Never>?
    private var engineEventReaderTask: Task<Void, Never>?
    private var bootReaderTask: Task<Void, Never>?
    private var configuredStrength: OpponentEngineBand?
    private var configuredMultiPV: Int?

    private enum ConversationKind: Sendable {
        case opponent
        case analysis
    }

    private struct Conversation: Sendable {
        let id = UUID()
        let kind: ConversationKind
    }

    private struct ConversationWaiter {
        let conversation: Conversation
        let continuation: CheckedContinuation<Void, Never>
    }

    /// Actor isolation is not enough here: a callback wait is an `await`, so a
    /// second transaction can enter the actor. Opponent work has strict
    /// priority. If it arrives during analysis, `stop()` makes Stockfish deliver
    /// that analysis search's best-move callback and release the engine.
    private var activeConversation: Conversation?
    private var opponentWaiters: [ConversationWaiter] = []
    private var analysisWaiters: [ConversationWaiter] = []

    private struct ActiveAnalysis {
        let id: UUID
        let request: AnalysisRequest
        let expectedLineCount: Int
        let continuation: AsyncStream<PositionAnalysis>.Continuation
        var updatesByDepth: [Int: [Int: StockfishAnalysisInfo]] = [:]
        var lastYieldedDepth = 0
    }

    private var activeAnalysis: ActiveAnalysis?

    /// Boots and verifies both NNUE resources. Returns nil if the bundle is
    /// incomplete or Stockfish does not become ready before the deadline.
    init?(process: StockfishProcess = .shared, bootTimeout: Duration = .seconds(12)) async {
        self.process = process
        startReadingCallbacks()

        guard process.isRunning || process.start() else { return nil }
        if !process.networksLoaded {
            guard let result = await readBootResult(timeout: bootTimeout), result.succeeded else {
                return nil
            }
        }
        guard process.networksLoaded else { return nil }
    }

    deinit {
        engineEventReaderTask?.cancel()
        bootReaderTask?.cancel()
    }

    private func startReadingCallbacks() {
        engineEventReaderTask = Task { [weak self, events = process.engineEvents] in
            for await event in events {
                guard let self else { return }
                await self.deliver(engineEvent: event)
            }
            await self?.finishBestMoveReading()
        }

        bootReaderTask = Task { [weak self, readyEvents = process.readyEvents] in
            for await event in readyEvents {
                guard let self else { return }
                await self.deliver(bootResult: event)
            }
            await self?.finishBootReading()
        }
    }

    private func deliver(engineEvent: StockfishEngineEvent) {
        switch engineEvent {
        case .analysis(let info):
            deliver(analysisInfo: info)
        case .bestMove(let bestMove):
            deliver(bestMove: bestMove)
        }
    }

    private func deliver(bestMove: String) {
        if let bestMoveWaiter {
            self.bestMoveWaiter = nil
            bestMoveWaiter.resume(returning: bestMove)
        } else {
            bufferedBestMoves.append(bestMove)
        }
    }

    private func deliver(bootResult: StockfishBootResult) {
        if let bootWaiter {
            self.bootWaiter = nil
            bootWaiter.resume(returning: bootResult)
        } else {
            bufferedBootResults.append(bootResult)
        }
    }

    private func finishBestMoveReading() {
        guard let bestMoveWaiter else { return }
        self.bestMoveWaiter = nil
        bestMoveWaiter.resume(returning: nil)
    }

    private func finishBootReading() {
        guard let bootWaiter else { return }
        self.bootWaiter = nil
        bootWaiter.resume(returning: nil)
    }

    private func beginConversation(_ kind: ConversationKind) async -> Conversation {
        let conversation = Conversation(kind: kind)
        guard activeConversation != nil else {
            activeConversation = conversation
            return conversation
        }

        if kind == .opponent, activeConversation?.kind == .analysis {
            process.stop()
        }

        await withCheckedContinuation { continuation in
            let waiter = ConversationWaiter(
                conversation: conversation,
                continuation: continuation
            )
            if kind == .opponent {
                opponentWaiters.append(waiter)
            } else {
                analysisWaiters.append(waiter)
            }
        }
        return conversation
    }

    private func endConversation(_ conversation: Conversation) {
        guard activeConversation?.id == conversation.id else { return }
        let next: ConversationWaiter?
        if !opponentWaiters.isEmpty {
            next = opponentWaiters.removeFirst()
        } else if !analysisWaiters.isEmpty {
            next = analysisWaiters.removeFirst()
        } else {
            next = nil
        }
        activeConversation = next?.conversation
        next?.continuation.resume()
    }

    func newGame() async {
        let conversation = await beginConversation(.opponent)
        defer { endConversation(conversation) }
        process.newGame()
        configuredStrength = nil
        configuredMultiPV = nil
    }

    func bestMove(for request: OpponentRequest) async -> Move? {
        guard !request.allowedMoves.isEmpty else { return nil }
        if request.allowedMoves.count == 1 { return request.allowedMoves[0] }

        let conversation = await beginConversation(.opponent)
        defer { endConversation(conversation) }
        guard !Task.isCancelled else { return nil }

        // A completed callback belongs to the previous transaction. Position
        // replacement waits for that search to finish, so clearing here cannot
        // discard a callback from the new search.
        bufferedBestMoves.removeAll(keepingCapacity: true)

        applyStrength(request.rating.engineBand)
        applyMultiPV(1)
        guard process.setPosition(fen: request.position.fen) else { return nil }
        guard process.go(
            thinkingTime: request.thinkingTime,
            allowedMoves: request.allowedMoves
        ) else { return nil }

        let watchdog = Task { [process] in
            try? await Task.sleep(for: request.thinkingTime + .milliseconds(600))
            guard !Task.isCancelled else { return }
            process.stop()
        }
        defer { watchdog.cancel() }

        guard let notation = await readBestMove(
            timeout: request.thinkingTime + .seconds(3)
        ) else {
            process.stop()
            return nil
        }

        return Self.move(fromUCINotation: notation, allowedMoves: request.allowedMoves)
    }

    private func applyStrength(_ strength: OpponentEngineBand) {
        guard configuredStrength != strength else { return }
        guard process.setStrength(strength) else { return }
        configuredStrength = strength
    }

    private func applyMultiPV(_ count: Int) {
        let bounded = min(max(count, 1), 256)
        guard configuredMultiPV != bounded else { return }
        guard process.setMultiPV(bounded) else { return }
        configuredMultiPV = bounded
    }

    // MARK: - Analysis

    func analysisUpdates(for request: AnalysisRequest) async -> AsyncStream<PositionAnalysis> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let task = Task { [weak self] in
                await self?.runAnalysis(id: id, request: request, continuation: continuation)
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                task.cancel()
                Task { await self?.cancelAnalysis(id: id) }
            }
        }
    }

    func cancelAnalysis() async {
        guard activeConversation?.kind == .analysis else { return }
        process.stop()
    }

    private func cancelAnalysis(id: UUID) {
        guard activeAnalysis?.id == id else { return }
        process.stop()
    }

    private func runAnalysis(
        id: UUID,
        request: AnalysisRequest,
        continuation: AsyncStream<PositionAnalysis>.Continuation
    ) async {
        guard !request.allowedMoves.isEmpty, request.requestedLineCount > 0 else {
            continuation.finish()
            return
        }

        let conversation = await beginConversation(.analysis)
        defer { endConversation(conversation) }
        guard !Task.isCancelled else {
            continuation.finish()
            return
        }

        bufferedBestMoves.removeAll(keepingCapacity: true)
        activeAnalysis = ActiveAnalysis(
            id: id,
            request: request,
            expectedLineCount: request.requestedLineCount,
            continuation: continuation
        )

        applyStrength(.fullStrength)
        applyMultiPV(request.requestedLineCount)
        guard process.setPosition(fen: request.position.fen),
              process.go(
                thinkingTime: request.maximumTime,
                depth: request.targetDepth,
                allowedMoves: request.allowedMoves
              ) else {
            finishAnalysis(id: id)
            return
        }

        let watchdog = request.maximumTime.map { maximumTime in
            Task { [process] in
                try? await Task.sleep(for: maximumTime + .milliseconds(300))
                guard !Task.isCancelled else { return }
                process.stop()
            }
        }
        defer { watchdog?.cancel() }

        _ = await readBestMove(timeout: request.maximumTime.map { $0 + .seconds(2) })
        finishAnalysis(id: id)
    }

    private func deliver(analysisInfo info: StockfishAnalysisInfo) {
        guard var analysis = activeAnalysis,
              info.multiPV > 0,
              info.multiPV <= analysis.expectedLineCount else { return }

        analysis.updatesByDepth[info.depth, default: [:]][info.multiPV] = info
        let isComplete = analysis.updatesByDepth[info.depth]?.count == analysis.expectedLineCount
        if isComplete, info.depth > analysis.lastYieldedDepth,
           let snapshot = makeSnapshot(from: analysis, depth: info.depth) {
            analysis.lastYieldedDepth = info.depth
            analysis.continuation.yield(snapshot)
        }
        activeAnalysis = analysis
    }

    private func finishAnalysis(id: UUID) {
        guard let analysis = activeAnalysis, analysis.id == id else { return }
        let completeDepth = analysis.updatesByDepth
            .filter { $0.value.count == analysis.expectedLineCount }
            .map(\.key)
            .max()
        if let depth = completeDepth,
           depth > analysis.lastYieldedDepth,
           let snapshot = makeSnapshot(from: analysis, depth: depth) {
            analysis.continuation.yield(snapshot)
        } else if analysis.lastYieldedDepth == 0,
                  let bestPartialDepth = analysis.updatesByDepth.keys.max(by: { lhs, rhs in
                      let leftCount = analysis.updatesByDepth[lhs]?.count ?? 0
                      let rightCount = analysis.updatesByDepth[rhs]?.count ?? 0
                      return leftCount == rightCount ? lhs < rhs : leftCount < rightCount
                  }),
                  let snapshot = makeSnapshot(from: analysis, depth: bestPartialDepth) {
            // Very short or interrupted searches may never complete a whole
            // MultiPV iteration. A partial snapshot is still useful, but it
            // must not overwrite a previously delivered complete one.
            analysis.continuation.yield(snapshot)
        }
        analysis.continuation.finish()
        activeAnalysis = nil
    }

    private func makeSnapshot(from analysis: ActiveAnalysis, depth: Int) -> PositionAnalysis? {
        guard let updates = analysis.updatesByDepth[depth] else { return nil }
        let lines = updates.keys.sorted().compactMap { rank -> AnalysisLine? in
            guard let info = updates[rank] else { return nil }
            return makeLine(from: info, request: analysis.request)
        }
        guard !lines.isEmpty else { return nil }
        return PositionAnalysis(position: analysis.request.position, lines: lines)
    }

    private func makeLine(
        from info: StockfishAnalysisInfo,
        request: AnalysisRequest
    ) -> AnalysisLine? {
        let tokens = info.principalVariation.split(separator: " ").map(String.init)
        guard let first = tokens.first,
              let rootMove = Self.move(
                fromUCINotation: first,
                allowedMoves: request.allowedMoves
              ) else { return nil }

        var variation: [Move] = []
        var cursor = request.position
        for token in tokens {
            let candidates = variation.isEmpty
                ? request.allowedMoves
                : ChessEngine.legalMoves(in: cursor)
            // `move` is one of `candidates`, so it is already legal here and
            // `apply`'s validation would just regenerate the list above.
            guard let move = Self.move(fromUCINotation: token, allowedMoves: candidates),
                  let next = ChessEngine.applyKnownLegal(move, to: cursor) else { break }
            variation.append(move)
            cursor = next
        }
        if variation.isEmpty { variation = [rootMove] }

        let score: AnalysisScore
        switch info.score {
        case .centipawns(let value): score = .centipawns(value)
        case .mate(let plies): score = .mate(plies: plies)
        case .tablebase(let distance): score = .tablebase(distance: distance)
        }
        return AnalysisLine(
            rank: info.multiPV,
            depth: info.depth,
            selectiveDepth: info.selectiveDepth,
            move: rootMove,
            score: score,
            principalVariation: variation,
            elapsedMilliseconds: info.elapsedMilliseconds,
            nodes: info.nodes,
            nodesPerSecond: info.nodesPerSecond,
            tablebaseHits: info.tablebaseHits,
            hashFull: info.hashFull
        )
    }

    // MARK: - Callback waits

    private func readBestMove(timeout: Duration?) async -> String? {
        if !bufferedBestMoves.isEmpty { return bufferedBestMoves.removeFirst() }
        guard let timeout else {
            return await withCheckedContinuation { continuation in
                bestMoveWaiter = continuation
            }
        }
        let deadline = ContinuousClock.now + timeout
        guard ContinuousClock.now < deadline else { return nil }

        let expiry = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            await self?.expireBestMoveWaiter()
        }
        defer { expiry.cancel() }

        return await withCheckedContinuation { continuation in
            bestMoveWaiter = continuation
        }
    }

    private func readBootResult(timeout: Duration) async -> StockfishBootResult? {
        if !bufferedBootResults.isEmpty { return bufferedBootResults.removeFirst() }
        let deadline = ContinuousClock.now + timeout
        guard ContinuousClock.now < deadline else { return nil }

        let expiry = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled else { return }
            await self?.expireBootWaiter()
        }
        defer { expiry.cancel() }

        return await withCheckedContinuation { continuation in
            bootWaiter = continuation
        }
    }

    private func expireBestMoveWaiter() {
        guard let bestMoveWaiter else { return }
        self.bestMoveWaiter = nil
        bestMoveWaiter.resume(returning: nil)
    }

    private func expireBootWaiter() {
        guard let bootWaiter else { return }
        self.bootWaiter = nil
        bootWaiter.resume(returning: nil)
    }

    // MARK: - UCI move notation

    nonisolated static func uciString(for move: Move) -> String {
        let promotion = move.promotion.map { String($0.fenCharacter).lowercased() } ?? ""
        return "\(move.from.algebraic)\(move.to.algebraic)\(promotion)"
    }

    /// Maps the structured callback's move token back onto a move the session
    /// offered. A token outside that list is discarded, never guessed at.
    nonisolated static func move(fromUCINotation notation: String, allowedMoves: [Move]) -> Move? {
        guard notation != "(none)", notation.count >= 4 else { return nil }
        return allowedMoves.first { uciString(for: $0) == notation }
    }

    /// Compatibility helper for the existing pure parser tests. Production no
    /// longer receives or parses a `bestmove ...` text line.
    nonisolated static func move(fromBestMoveLine line: String, allowedMoves: [Move]) -> Move? {
        let fields = line.split(separator: " ")
        guard fields.count >= 2, fields[0] == "bestmove" else { return nil }
        return move(fromUCINotation: String(fields[1]), allowedMoves: allowedMoves)
    }
}

private extension Duration {
    nonisolated var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
