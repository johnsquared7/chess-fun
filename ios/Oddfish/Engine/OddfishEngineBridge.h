#ifndef ODDFISH_ENGINE_BRIDGE_H
#define ODDFISH_ENGINE_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Score variants delivered by Stockfish's structured analysis callback.
typedef enum OddfishEngineScoreKind {
    OddfishEngineScoreCentipawns = 0,
    OddfishEngineScoreMate = 1,
    OddfishEngineScoreTablebase = 2,
} OddfishEngineScoreKind;

/// A stable C representation of Stockfish 18's `Search::InfoFull`.
///
/// String pointers are valid only for the duration of the callback. Numeric
/// values are copied from Stockfish and may safely be retained by the caller.
typedef struct OddfishEngineInfo {
    int depth;
    int selective_depth;
    int multi_pv;
    OddfishEngineScoreKind score_kind;
    int score_value;
    uint64_t time_ms;
    uint64_t nodes;
    uint64_t nodes_per_second;
    uint64_t tablebase_hits;
    int hash_full;
    const char *principal_variation;
} OddfishEngineInfo;

/// Reports completion of asynchronous engine startup. `success` is 1 only
/// after both NNUE files have been loaded and verified by Stockfish.
typedef void (*OddfishEngineReadyHandler)(int success, const char *report, void *context);

/// Delivers the structured best-move callback from Stockfish. String pointers
/// are valid only for the duration of the callback.
typedef void (*OddfishEngineBestMoveHandler)(
    const char *best_move,
    const char *ponder_move,
    void *context
);

/// Delivers one structured full-analysis update.
typedef void (*OddfishEngineInfoHandler)(const OddfishEngineInfo *info, void *context);

/// Starts Stockfish 18 on a background thread and loads both NNUE resources.
/// Returns 1 when startup was accepted. Completion is reported asynchronously
/// through `ready_handler`; a missing resource is rejected synchronously.
int oddfish_engine_start(
    const char *big_network_path,
    const char *small_network_path,
    OddfishEngineReadyHandler ready_handler,
    OddfishEngineBestMoveHandler best_move_handler,
    OddfishEngineInfoHandler info_handler,
    void *context
);

/// Configures a position from a full FEN. Waits for any previous search to
/// finish before replacing the position.
int oddfish_engine_set_position(const char *fen);

/// Uses Stockfish's weakest uncalibrated playing style for ratings below 1320.
int oddfish_engine_set_skill_level(int skill_level);

/// Configures Stockfish 18's calibrated strength limiter (1320...3190 Elo).
int oddfish_engine_set_elo(int elo);

/// Disables both strength limiters. Ratings above 3190 are differentiated only
/// by the search time supplied to `oddfish_engine_go`.
int oddfish_engine_set_full_strength(void);

/// Sets how many root variations Stockfish reports. The bridge clamps the
/// value to the engine option's supported 1...256 range.
int oddfish_engine_set_multi_pv(int count);

/// Starts a non-blocking search. `search_moves` is a space-separated list of
/// UCI move tokens copied into `LimitsType.searchmoves` by the bridge. A
/// positive `depth` adds a depth limit; zero leaves the search time-only. A
/// non-positive `move_time_ms` omits the time limit entirely.
int oddfish_engine_go(int move_time_ms, int depth, const char *search_moves);

/// Stops the current search. Its best-move callback is still delivered.
void oddfish_engine_stop(void);

/// Stops any search, waits for it, and clears per-game engine state.
void oddfish_engine_new_game(void);

/// Stops the engine and releases its worker threads and networks.
void oddfish_engine_shutdown(void);

/// Whether startup has been accepted and the engine has not been shut down.
int oddfish_engine_is_running(void);

/// Whether Stockfish itself verified both bundled NNUE networks.
int oddfish_engine_networks_loaded(void);

#ifdef __cplusplus
}
#endif

#endif /* ODDFISH_ENGINE_BRIDGE_H */
