# Oddfish Architecture

**Licence:** Oddfish is GPLv3, because it links Stockfish. See `COPYRIGHT.md`
for what that means and where the source is published.

## Product

Oddfish is a native, offline, single-player SwiftUI chess game with Classic
chess and twenty-eight variants grouped by what they change: opponent rating,
growth, chance, move constraints, or the opposing army. Restfish is the
resting-piece variant: a moved piece rests for the player's next two turns,
while check evasions always remain available.

The modes share one chess engine and differ through `GameMode`, focused
`GimmickRule` policies, and the small `ModeConfiguration` used by board-level
constraints. Classic remains the baseline and learning route.

## System contracts

### Core chess (`Core/Chess`)

- `Square`, `Piece`, `Move`, `Position`, and `GameOutcome` are value types, `Codable`, `Hashable`, and `Sendable` where practical.
- `ChessEngine` is deterministic and has no UI, timer, persistence, or mode knowledge.
- It generates pseudo-legal moves, filters moves that leave the mover in check, and supports castling, en passant, promotion, checkmate, stalemate, repetition, the fifty-move rule, and common insufficient-material draws.
- Applying a move returns a new position and move metadata. The UI never mutates board storage directly.
- Board coordinates are always White-oriented in the model: file 0 is a, rank 0 is White's home rank.

### Variant layer (`Core/Modes`)

- `GameMode` owns presentation metadata and immutable `ModeConfiguration`.
- `VariantState` stores only Restfish's per-square rest counters.
- `VariantRules` receives standard legal moves and may filter or annotate them. It must not duplicate standard move generation.
- Restfish restrictions apply symmetrically to the player and bot. If all standard legal check evasions would be filtered, standard evasions win.
- ThroneFish filters king movement and castling at the same legal-move boundary.
- Engine-facing gimmicks receive an explicit set of allowed root moves and can never manufacture an illegal move.

### Session (`Game/GameSession.swift`)

- A single `@Observable @MainActor` `GameSession` is the source of truth for position, selection, move history, outcome, bot state, pause state, and transient feedback.
- User input is accepted only while it is the player's turn, the game is active, and the bot is idle.
- Tap and drag both call the same `attemptMove(from:to:)` path.
- Promotion pauses commit and presents a native choice sheet.
- The session owns cancellable bot and analysis tasks. It cancels them on restart, exit, or deinit.

### Bot (`Core/Bot`)

- `ChessBot` runs off the main actor and receives an immutable search snapshot.
- Iterative/depth-limited negamax with alpha-beta, material, piece-square, mobility, king-safety, and capture ordering is sufficient for v1.
- Difficulty controls depth and a small top-move randomness window; it never makes an illegal move.
- Variant restrictions are provided as the final legal root moves and a rule callback/snapshot for deeper plies when needed.

### UI and interaction (`Features` and `DesignSystem`)

- Navigation: launch/home → mode detail/onboarding → game → result/rematch; settings and history are sheets/stacks that never discard an active game without confirmation.
- Board uses SwiftUI layout with stable square identities. Piece position changes animate with a short responsive spring; drag tracking itself is unanimated and remains under the finger.
- Drag contract: 6pt minimum distance, 1.08x lift, shadow, legal targets on lift, nearest-square hit testing, spring snap on invalid drop, no duplicate move path.
- Tap contract: first tap selects own movable piece; second legal tap commits; another own piece retargets; selected square tap cancels.
- Legal indicators distinguish quiet moves, captures, last move, selection, check, and Restfish rest without relying on color alone.
- All controls target at least 44pt, pieces/squares have VoiceOver labels and actions, Dynamic Type is supported outside the fixed-aspect board, and Reduce Motion removes decorative movement.

### Feedback (`Services/FeedbackService.swift`)

- A protocol-backed service coordinates sound and haptics after successful state changes.
- Native generated audio avoids copied assets: subtle move, capture, warning, check, and result cues.
- Haptics are restrained: selection, move, capture, invalid, check, and win/loss. Settings can disable sound or haptics independently.

### Persistence (`Services/AppStore.swift`)

- `UserDefaults` stores one current-shape Codable payload containing settings,
  onboarding state, aggregate stats, and compact completed-game records. The
  pre-release app carries no obsolete payload migration paths.
- Active sessions are restored from a versioned snapshot after interruption
  (`Game/GameSnapshot.swift`). The snapshot carries what a position cannot
  reconstruct — the live rating, rest counters, the bonus-move flag, the
  integrity audit, and the seed a gimmick's randomness depends on. A snapshot
  from another version, for another mode, or from a game with no moves is
  refused rather than misread: losing one interrupted game is a better outcome
  than restoring a corrupted one.
- History is bounded and never blocks launch.

## Visual direction

Oddfish uses an original midnight-aquatic identity rather than chess-green
convention: deep navy canvas, warm ivory pieces, sea-glass cyan, coral urgency.
The board remains the visual anchor. Typography is rounded for mode personality
and monospaced where numeric values need to stay visually stable.

Three rules govern the interface, and every screen is checked against them.

**Flat surfaces, four steps.** `canvas → surface → surfaceHigh → surfaceTop`,
each a clear jump in luminance, all opaque. Translucent material was removed
throughout: it costs a full-screen blur pass, it muddies small type, and it
makes every card the same weight, which is the opposite of hierarchy.

**One accent.** Sea-glass carries every primary action. Coral is reserved for
urgency and loss, gold for crowns and for Gil, and a mode's tint appears only on
that mode's own glyph and tagline. Nothing else is allowed a colour. Move
markers are drawn in ink rather than in an accent, because an accent has to
clear both square colours at once and on most boards it clears neither.

**The board is the screen.** On a phone it runs edge to edge, framed by two
symmetrical player strips and a move tape, with a four-item bar pinned at the
bottom. Spare vertical height goes above the board, where the guide speaks.

Two axes describe a piece: a `PieceSet` decides its shape, a `PieceStyle`
decides its treatment, and every combination has to be a usable board. One set
ships — avi's Caliente, CC BY-SA 4.0 — converted from the artist's own SVG by
`Pieces/GeneratePieceArt.swift`. Only geometry is imported: its fills collapse
to four ink roles that the board theme supplies, because a set carrying its own
palette would be the one thing on the board a theme could not reach. The set
axis is kept rather than collapsed because adding a set is now a role
declaration and a re-run, and because the choice is persisted in `AppSettings`.

### Motion

`OddfishTheme.Motion` is a ramp — `instant`, `chrome`, `standard`, `piece`,
`entrance`, `exit`, `celebrate` — and views pick a step rather than inventing a
spring. `OddfishTheme.Beat` holds the timings that sequence one thing after
another.

The governing rule is that **the player must finish seeing one thing before the
next one starts.** The end of a game is the case that rule exists for: the
result card used to be drawn the instant the position became terminal, on top of
a mating piece that was still travelling, so the most important half-second of a
game was never actually seen. `EndgameChoreography` now holds the sequence — the
piece lands, the board blooms and names the result on its own for over half a
second, and only then does the scrim rise. Its durations are parameters so
`EndgameChoreographyTests` can assert the order and the gaps in milliseconds.

A transition is always declared on the thing that moves, never on a layer that
contains it: `.transition(.scale)` outside a `.position` scales the whole
board-sized layer and drags every marker toward the centre as it appears.

## Verification

- Unit tests: initial/perft move counts, every special move, check legality, outcomes, FEN fixtures, mode filters, current-shape persistence, and bot legality.
- UI tests: launch, choose each mode, onboarding dismissal, tap move, drag move, pause/restart, settings, and rematch.
- Build after every integration wave with a workspace-local DerivedData directory.
- Simulator review at small iPhone, current Pro iPhone, and iPad sizes, including Dark Mode, larger text, VoiceOver labels, and Reduce Motion.

## Component quality gates

1. **Engine:** correct legal moves and outcomes; deterministic tests pass.
2. **Board:** selection/drag feels immediate; invalid drops recover cleanly; no visual/input race during bot turns.
3. **Modes:** rule is understood from one sentence plus one in-game cue; both sides follow it; restart is exact.
4. **Game loop:** launch-to-first-move is fast; pause, result, rematch, and change-mode flows preserve user intent.
5. **Polish:** sound/haptic timing follows state commit, layouts survive supported devices, accessibility conveys all nonvisual state.
