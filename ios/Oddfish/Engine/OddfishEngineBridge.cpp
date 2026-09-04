#include "OddfishEngineBridge.h"

#include <algorithm>
#include <condition_variable>
#include <exception>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "Stockfish/bitboard.h"
#include "Stockfish/engine.h"
#include "Stockfish/position.h"
#include "Stockfish/score.h"
#include "Stockfish/search.h"
#include "Stockfish/ucioption.h"

namespace {

std::mutex lifecycleMutex;
std::condition_variable bootCondition;
std::once_flag stockfishInitialization;
std::unique_ptr<Stockfish::Engine> engine;
bool engineRunning = false;
bool bootInProgress = false;
bool networksLoaded = false;

OddfishEngineReadyHandler readyHandler = nullptr;
OddfishEngineBestMoveHandler bestMoveHandler = nullptr;
OddfishEngineInfoHandler infoHandler = nullptr;
void *callbackContext = nullptr;

bool readableFile(const char *path) {
    if (path == nullptr || *path == '\0') {
        return false;
    }
    std::ifstream file(path, std::ios::binary);
    return file.good();
}

void setOption(Stockfish::Engine &target, const std::string &name, const std::string &value) {
    std::istringstream command("name " + name + " value " + value);
    target.get_options().setoption(command);
}

std::string combinedReport(const std::vector<std::string> &lines) {
    std::string result;
    for (const auto &line : lines) {
        if (!result.empty()) {
            result += '\n';
        }
        result += line;
    }
    return result;
}

void deliverReady(bool success, const std::string &report) {
    OddfishEngineReadyHandler handler = nullptr;
    void *context = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifecycleMutex);
        handler = readyHandler;
        context = callbackContext;
    }
    if (handler != nullptr) {
        handler(success ? 1 : 0, report.c_str(), context);
    }
}

void deliverBestMove(std::string_view bestMove, std::string_view ponderMove) {
    OddfishEngineBestMoveHandler handler = nullptr;
    void *context = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifecycleMutex);
        handler = bestMoveHandler;
        context = callbackContext;
    }
    if (handler == nullptr) {
        return;
    }

    const std::string best(bestMove);
    const std::string ponder(ponderMove);
    handler(best.c_str(), ponder.c_str(), context);
}

void deliverInfo(const Stockfish::Engine::InfoFull &source) {
    OddfishEngineInfoHandler handler = nullptr;
    void *context = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifecycleMutex);
        handler = infoHandler;
        context = callbackContext;
    }
    if (handler == nullptr) {
        return;
    }

    OddfishEngineInfo destination{};
    destination.depth = source.depth;
    destination.selective_depth = source.selDepth;
    destination.multi_pv = static_cast<int>(source.multiPV);
    destination.time_ms = static_cast<uint64_t>(source.timeMs);
    destination.nodes = static_cast<uint64_t>(source.nodes);
    destination.nodes_per_second = static_cast<uint64_t>(source.nps);
    destination.tablebase_hits = static_cast<uint64_t>(source.tbHits);
    destination.hash_full = source.hashfull;

    if (source.score.is<Stockfish::Score::Mate>()) {
        destination.score_kind = OddfishEngineScoreMate;
        destination.score_value = source.score.get<Stockfish::Score::Mate>().plies;
    } else if (source.score.is<Stockfish::Score::Tablebase>()) {
        const auto tablebase = source.score.get<Stockfish::Score::Tablebase>();
        destination.score_kind = OddfishEngineScoreTablebase;
        destination.score_value = tablebase.win ? tablebase.plies : -tablebase.plies;
    } else {
        destination.score_kind = OddfishEngineScoreCentipawns;
        destination.score_value = source.score.get<Stockfish::Score::InternalUnits>().value;
    }

    const std::string principalVariation(source.pv);
    destination.principal_variation = principalVariation.c_str();
    handler(&destination, context);
}

void boot(std::string bigNetworkPath, std::string smallNetworkPath) {
    try {
        std::call_once(stockfishInitialization, [] {
            Stockfish::Bitboards::init();
            Stockfish::Position::init();
        });

        auto bootedEngine = std::make_unique<Stockfish::Engine>();
        std::vector<std::string> networkReport;

        bootedEngine->set_on_bestmove(
            [](std::string_view best, std::string_view ponder) { deliverBestMove(best, ponder); }
        );
        bootedEngine->set_on_update_full(
            [](const Stockfish::Engine::InfoFull &info) { deliverInfo(info); }
        );
        bootedEngine->set_on_verify_networks(
            [&networkReport](std::string_view message) { networkReport.emplace_back(message); }
        );

        // The app ships the nets as resources rather than embedding another copy
        // in the executable. Assigning the options both loads the files and makes
        // Stockfish's own verifier expect these exact paths.
        setOption(*bootedEngine, "EvalFile", bigNetworkPath);
        setOption(*bootedEngine, "EvalFileSmall", smallNetworkPath);
        bootedEngine->verify_networks();

        // `go()` verifies again before every search. Do not leave the engine
        // holding the boot-only callback, which captured the local report.
        bootedEngine->set_on_verify_networks([](std::string_view) {});

        const std::string report = combinedReport(networkReport);
        {
            std::lock_guard<std::mutex> lock(lifecycleMutex);
            engine = std::move(bootedEngine);
            networksLoaded = true;
            bootInProgress = false;
        }
        bootCondition.notify_all();
        deliverReady(true, report);
    } catch (const std::exception &error) {
        {
            std::lock_guard<std::mutex> lock(lifecycleMutex);
            engineRunning = false;
            bootInProgress = false;
            networksLoaded = false;
        }
        bootCondition.notify_all();
        deliverReady(false, error.what());
    } catch (...) {
        {
            std::lock_guard<std::mutex> lock(lifecycleMutex);
            engineRunning = false;
            bootInProgress = false;
            networksLoaded = false;
        }
        bootCondition.notify_all();
        deliverReady(false, "Stockfish failed to start for an unknown reason.");
    }
}

Stockfish::Engine *readyEngine() {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    return networksLoaded ? engine.get() : nullptr;
}

} // namespace

int oddfish_engine_start(
    const char *big_network_path,
    const char *small_network_path,
    OddfishEngineReadyHandler ready_handler,
    OddfishEngineBestMoveHandler best_move_handler,
    OddfishEngineInfoHandler info_handler,
    void *context
) {
    if (!readableFile(big_network_path) || !readableFile(small_network_path)) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(lifecycleMutex);
    if (engineRunning) {
        return 0;
    }

    readyHandler = ready_handler;
    bestMoveHandler = best_move_handler;
    infoHandler = info_handler;
    callbackContext = context;
    engineRunning = true;
    bootInProgress = true;
    networksLoaded = false;

    try {
        std::thread(
            boot,
            std::string(big_network_path),
            std::string(small_network_path)
        ).detach();
    } catch (...) {
        engineRunning = false;
        bootInProgress = false;
        return 0;
    }
    return 1;
}

int oddfish_engine_set_position(const char *fen) {
    if (fen == nullptr) {
        return 0;
    }
    auto *target = readyEngine();
    if (target == nullptr) {
        return 0;
    }
    target->wait_for_search_finished();
    target->set_position(fen, {});
    return 1;
}

int oddfish_engine_set_skill_level(int skill_level) {
    auto *target = readyEngine();
    if (target == nullptr) {
        return 0;
    }
    target->wait_for_search_finished();
    setOption(*target, "UCI_LimitStrength", "false");
    setOption(*target, "Skill Level", std::to_string(std::clamp(skill_level, 0, 20)));
    return 1;
}

int oddfish_engine_set_elo(int elo) {
    auto *target = readyEngine();
    if (target == nullptr) {
        return 0;
    }
    target->wait_for_search_finished();
    const int boundedElo = std::clamp(elo, 1320, 3190);
    setOption(*target, "Skill Level", "20");
    setOption(*target, "UCI_LimitStrength", "true");
    setOption(*target, "UCI_Elo", std::to_string(boundedElo));
    return 1;
}

int oddfish_engine_set_full_strength(void) {
    auto *target = readyEngine();
    if (target == nullptr) {
        return 0;
    }
    target->wait_for_search_finished();
    setOption(*target, "UCI_LimitStrength", "false");
    setOption(*target, "Skill Level", "20");
    return 1;
}

int oddfish_engine_set_multi_pv(int count) {
    auto *target = readyEngine();
    if (target == nullptr) {
        return 0;
    }
    target->wait_for_search_finished();
    setOption(*target, "MultiPV", std::to_string(std::clamp(count, 1, 256)));
    return 1;
}

int oddfish_engine_go(int move_time_ms, int depth, const char *search_moves) {
    auto *target = readyEngine();
    if (target == nullptr || search_moves == nullptr || *search_moves == '\0') {
        return 0;
    }

    Stockfish::Search::LimitsType limits;
    if (move_time_ms > 0) {
        limits.movetime = move_time_ms;
    }
    if (depth > 0) {
        limits.depth = depth;
    }

    std::istringstream moves(search_moves);
    std::string move;
    while (moves >> move) {
        limits.searchmoves.push_back(std::move(move));
    }
    if (limits.searchmoves.empty()) {
        return 0;
    }

    target->go(limits);
    return 1;
}

void oddfish_engine_stop(void) {
    if (auto *target = readyEngine()) {
        target->stop();
    }
}

void oddfish_engine_new_game(void) {
    if (auto *target = readyEngine()) {
        target->stop();
        target->wait_for_search_finished();
        target->search_clear();
    }
}

void oddfish_engine_shutdown(void) {
    std::unique_ptr<Stockfish::Engine> engineToDestroy;
    {
        std::unique_lock<std::mutex> lock(lifecycleMutex);
        bootCondition.wait(lock, [] { return !bootInProgress; });
        engineToDestroy = std::move(engine);
        engineRunning = false;
        networksLoaded = false;
        readyHandler = nullptr;
        bestMoveHandler = nullptr;
        infoHandler = nullptr;
        callbackContext = nullptr;
    }
    if (engineToDestroy) {
        engineToDestroy->stop();
        engineToDestroy->wait_for_search_finished();
    }
}

int oddfish_engine_is_running(void) {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    return engineRunning ? 1 : 0;
}

int oddfish_engine_networks_loaded(void) {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    return networksLoaded ? 1 : 0;
}
