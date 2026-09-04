# Oddfish

**Chess, but a little stranger.**

An iOS chess app built on [Stockfish](https://github.com/official-stockfish/Stockfish). The
engine plays properly — and then each mode changes one rule about *how* it is allowed to be
good at it. GluttonFish starts at 1000 Elo and gets stronger every time you feed it a piece.
RattleFish loses rating when you play well. Restfish has to let a piece sit still for a turn
after moving it.

Twenty-nine modes in six groups:

| Group | The idea |
|---|---|
| Classic | Standard chess |
| Bruise its ego | Good moves make its Elo worse |
| Feed the monster | Starts harmless. Allegedly. |
| Blame the dice | Skill, with plausible deniability |
| Bend the rules | Chess, but one rule had ideas |
| Perfectly normal armies | The back rank has gone peculiar |

Gil, a small gold fish with opinions, explains each one and reviews your moves afterwards.

Everything runs on device. No accounts, no network calls, no analytics — see
[`ios/Oddfish/PrivacyInfo.xcprivacy`](ios/Oddfish/PrivacyInfo.xcprivacy).

## Privacy

Oddfish does not collect or transmit personal data. Its plain-language privacy
policy is in [`PRIVACY.md`](PRIVACY.md).

## Licence

**GPL-3.0-or-later.** Oddfish links Stockfish, which is GPLv3, so Oddfish carries the same
licence. Full text in [`LICENSE`](LICENSE); the reasoning, third-party components and
attribution obligations are in [`COPYRIGHT.md`](COPYRIGHT.md) — read that one before
redistributing, as the piece artwork carries its own attribution requirement.

This repository exists so that anyone who receives a copy of Oddfish can get its complete
corresponding source, as GPLv3 requires.

## Building

Requires **Xcode 26.3 or later** and an iOS 18.0+ target. There are no package dependencies.

### 1. Fetch the big neural network

One of Stockfish's two NNUE networks is 103.8 MiB, over GitHub's 100 MiB file limit, so it
cannot live in the tree. It is attached to each release instead. Download it before your first
build:

```bash
curl -L -o ios/Oddfish/Engine/Networks/nn-c288c895ea92.nnue \
  https://github.com/johnsquared7/chess-fun/releases/download/v1.0.0/nn-c288c895ea92.nnue
```

Stockfish's own distribution point serves the identical file, if you would rather take it from
upstream:

```bash
curl -L -o ios/Oddfish/Engine/Networks/nn-c288c895ea92.nnue \
  https://tests.stockfishchess.org/api/nn/nn-c288c895ea92.nnue
```

Either way you can check you got the right bytes, because Stockfish names a network after its
own digest — the first twelve hex characters below are the filename:

```bash
shasum -a 256 ios/Oddfish/Engine/Networks/nn-c288c895ea92.nnue
# c288c895ea924429ea9092e3...  (108,919,594 bytes)
```

The smaller network (`nn-37f18f62d772.nnue`, 3.3 MiB) is already in the repository. Both are
GPLv3 and are the networks distributed with Stockfish 18.

Without the big network the app still builds and runs, but `StockfishOpponent.start()` returns
`false` and every game silently falls back to the simple built-in bot — so the engine tests
fail and the opponent is not the one the modes are calibrated against.

### 2. Build and run

```bash
open ios/Oddfish.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project ios/Oddfish.xcodeproj -scheme Oddfish \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### 3. Tests

```bash
xcodebuild test -project ios/Oddfish.xcodeproj -scheme Oddfish \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`OddfishTests` covers the chess core, variant rules, bot, engine and persistence.
`OddfishUITests` drives the real app, including system accessibility audits at both default and
AccessibilityXXXL text sizes.

Two known failures in a fresh clone:

- The engine tests fail until you fetch the network above.
- `Stage8ShipReadinessTests` fails until `ODDFISH_SOURCE_CODE_URL` is set (below).

### Release builds

A Release build refuses to archive without a public HTTPS URL for the exact source it was built
from — that is the GPL source offer, surfaced in the app under Settings → Licence:

```bash
xcodebuild -project ios/Oddfish.xcodeproj -scheme Oddfish \
  -configuration Release archive \
  ODDFISH_SOURCE_CODE_URL=https://github.com/johnsquared7/chess-fun/tree/v1.0.0
```

Tag the source for each release rather than pointing at a moving branch, and keep each tag
available for as long as the corresponding binary is distributed.

## Layout

```
ios/Oddfish/
  Core/Chess/        Stateless orthodox chess rules
  Core/Modes/        The 29 modes and their rule overrides
  Core/Bot/          Fallback negamax bot, opponent rating model
  Engine/            Stockfish 18 (unmodified) + C++ bridge + networks
  Features/          Home, Game, History, Settings, Paywall, Guide
  DesignSystem/      Palette, spacing, motion, piece artwork, Gil
  Game/              Session, snapshots, event log
Pieces/              Caliente source artwork + converter
Brand/               Marks and explorations
```

Deeper notes live in [`ARCHITECTURE.md`](ARCHITECTURE.md). Stockfish is vendored unmodified;
what Oddfish does around it is recorded in
[`ios/Oddfish/Engine/ODDFISH_CHANGES.md`](ios/Oddfish/Engine/ODDFISH_CHANGES.md).

## Credits

- [Stockfish](https://github.com/official-stockfish/Stockfish) and its NNUE networks — GPLv3,
  by the Stockfish developers.
- The [Caliente](https://github.com/avi-0/caliente) piece set — CC BY-SA 4.0, by **avi**.

Everything else — the chess core, the variant rules, the board, Gil and the interface — is
original to Oddfish.
