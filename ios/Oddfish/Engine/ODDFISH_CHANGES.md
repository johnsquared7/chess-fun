# Stockfish in Oddfish

`Engine/Stockfish/` is the library portion of **Stockfish 18** (tag `sf_18`,
commit `cb3d4ee9b47d0c5aae855b12379378ea1439675c`) from
<https://github.com/official-stockfish/Stockfish>. It is licensed under GNU GPL
version 3 or later. The full licence text is in
`Engine/Stockfish/COPYING.txt` and at the repository root.

## Source status

The vendored Stockfish source is **unmodified**. Oddfish links the 23 library
translation units exactly as released. Stockfish's standalone `main.cpp` is not
included because the iOS app supplies its own entry point; no replacement or
patch is made inside the vendored tree.

The integration lives entirely in `OddfishEngineBridge.cpp`. Stockfish 18's
public `Engine` class accepts positions and search limits directly and reports
best moves and analysis through structured callbacks, so the three source
patches and private UCI stream used for Stockfish 11 are gone.

## Networks

Oddfish bundles and explicitly loads both networks required by Stockfish 18:

- `nn-c288c895ea92.nnue` — SHA-256
  `c288c895ea924429ea9092e3f36b2b3c1f00f2a3a4c759ff7e57e79e3b43e4a7`
- `nn-37f18f62d772.nnue` — SHA-256
  `37f18f62d772f3107e1d6aaca3898c130c3c86f2ab63e6555fbbca20635a899d`

They are official files downloaded from
`https://tests.stockfishchess.org/api/nn/`. `NNUE_EMBEDDING_OFF` prevents a
second copy from being embedded in the executable. The bridge passes the bundle
paths through `EvalFile` / `EvalFileSmall` and does not report ready until
Stockfish's own `verify_networks()` has accepted both files.

## Build settings

The `Oddfish` target supplies the settings normally selected by Stockfish's
`armv8` Makefile configuration:

- `IS_64BIT`
- `USE_POPCNT`
- `USE_NEON=8` for arm64 builds
- `NDEBUG`
- `NNUE_EMBEDDING_OFF`
- `CLANG_CXX_LANGUAGE_STANDARD = gnu++17`
- `CLANG_CXX_LIBRARY = libc++`

## Licence consequence, resolved

Oddfish retains and links Stockfish. Oddfish therefore ships under GPLv3, with
its complete corresponding source made available to everyone who receives a
binary. A user-visible attribution and source-offer surface remains part of the
ship-readiness stage.
