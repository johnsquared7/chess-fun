# Licence and source

Oddfish is free software, licensed under the **GNU General Public License,
version 3 or later**. The repository contains the full text in `LICENSE`; every
app build also bundles Stockfish's `COPYING.txt` and exposes it from Settings →
Licence.

## Why

Oddfish links [Stockfish](https://github.com/official-stockfish/Stockfish),
which is GPLv3. Linking it makes Oddfish a derivative work, so Oddfish carries
the same licence. This was a deliberate choice: the alternative was shipping a
much weaker opponent, and the whole product is built on the engine's calibrated
strength range.

## What this means in practice

- Anyone who receives a copy of Oddfish — including from the App Store — is
  entitled to its complete corresponding source code.
- They may modify and redistribute it, under the same licence.
- The source must stay available for as long as the binary is distributed.

## Where the source lives

Each distributed build must link to its complete corresponding source from
Settings → Licence. The URL is deliberately release metadata rather than a
hard-coded constant:

```text
ODDFISH_SOURCE_CODE_URL=https://<public-host>/<project>/<release-or-tag>
```

The Release build gate rejects an absent, non-HTTPS, or obvious placeholder
value. Before archiving, publish and tag the exact source used by that archive,
verify the URL works without an account, then pass that URL as the
`ODDFISH_SOURCE_CODE_URL` Xcode build setting. The app records the URL alongside
its version and build number in `Info.plist`.

The project currently defaults this setting, in both configurations, to the
`v1.0.0` tag. **That default must be bumped with every release.** The gate only
checks that the value is a plausible public HTTPS URL — it cannot tell that a
syntactically valid URL points at the wrong commit, so a stale tag will archive
happily while offering source that is not the source of that binary. Overriding
it per build (`xcodebuild … ODDFISH_SOURCE_CODE_URL=…`) is still the safer
habit; the default exists so a fresh clone can build and test without one.

Do not use the repository's default branch as the only source offer: it can move
after release and cease to represent the shipped binary. Keep each tagged
source release available for as long as its corresponding binary is
distributed.

## Third-party components

| Component | Licence | Notes |
|---|---|---|
| Stockfish 18 | GPLv3 | `ios/Oddfish/Engine/Stockfish/`. **Unmodified.** The app drives its `Engine` C++ class directly rather than patching it — see `ios/Oddfish/Engine/ODDFISH_CHANGES.md`. |
| Stockfish NNUE networks | GPLv3 | `ios/Oddfish/Engine/Networks/`, distributed with Stockfish. |
| Caliente piece set | CC BY-SA 4.0 | By **avi** — <https://github.com/avi-0/caliente>. Upstream licence in `Pieces/LICENSE-caliente.txt`. |

Source artwork is in `Pieces/`, unmodified, alongside the converter that turns
it into the app's drawing tables. See `Pieces/README.md`.

Everything else — the chess core, the variant and gimmick rules, the board and
its themes, Gil, and the interface — is original to Oddfish.

### The Caliente set

Caliente is the only piece set Oddfish ships, so its licence is not a footnote.
CC BY-SA 4.0 is [one-way compatible][cc-gpl] with GPLv3, so material under it
may be redistributed inside this GPLv3 app. Two obligations come with it:

- **Attribution.** The artist's name and source appear in `Pieces/README.md`, in
  the header of the generated table, and in the app itself — Settings → Licence
  credits the set and its terms, and the Board screen names the artist under the
  piece controls. Because this is now the app's only set, that credit is
  load-bearing: removing it breaches the licence, and there is no in-house set
  to fall back on.
- **Share-alike.** The converted drawing tables are a derivative of the artwork
  and are distributed under GPLv3 as part of Oddfish, which the compatibility
  declaration permits. Anyone wanting the artwork under its own terms should
  take it from `Pieces/caliente.svg`, which is stored here unmodified.

Only the *geometry* is used. The upstream file paints a fixed grey pair; the app
maps those fills to four roles and colours them from the board theme instead.

Note that lichess's `COPYING.md` lists Caliente as CC BY-NC-SA 4.0 while the
artist's own `LICENSE.txt` says CC BY-SA 4.0. The artist's file is what is
relied on here; if it ever needs settling, ask the artist.

### Sets that were removed

Staunty (CC BY-NC-SA 4.0), Alpha ("free for personal non-commercial use") and
Alfarishy (no licence stated) were converted and then removed, because GPLv3 §7
forbids the added restriction each of them carries. They are not part of any
published ref: this repository's history was squashed to a single commit before
it was made public, so no snapshot distributed from here contains them. (Objects
from a force-pushed history can linger in a host's storage until it collects
them; only a fresh repository guarantees otherwise.) Oddfish's own Staunton set
was retired at the same time, by choice rather than by licence.

[cc-gpl]: https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/

## App Store distribution

Publishing corresponding source is necessary, but it does not by itself settle
whether Apple's distribution terms are compatible with every relevant
copyright holder's GPLv3 grant. Oddfish's original code and Stockfish have
different copyright holders. Obtain qualified legal advice—and any additional
permissions that advice identifies—before distributing through the App Store.

Nothing in this document is legal advice.
