# Piece artwork

Everything the app draws it draws in code. This directory holds the piece set
Oddfish renders, together with the converter that turns it into that code — so
the artwork in the app is derived from the artist's own file rather than traced
from a picture of it.

## Caliente

| | |
|---|---|
| Author | avi — <https://github.com/avi-0/caliente> |
| Licence | CC BY-SA 4.0 — `LICENSE-caliente.txt`, copied unmodified from upstream |
| Obtained from | <https://deverac.github.io/piece-packager/out/svg/caliente.svg> |
| Stored as | `caliente.svg`, byte-for-byte as downloaded |

CC BY-SA 4.0 is [one-way compatible][cc-gpl] with GPLv3, so the set can ship
inside a GPLv3 app. **Attribution travels with it**, which is why the artist is
named in `COPYRIGHT.md`, in the header of the generated table, and in the app —
Settings → Licence, and the footer under Settings → Board. Caliente is now the
app's only set, so that credit cannot be dropped without breaching the licence.

> lichess's `COPYING.md` lists Caliente as CC BY-NC-SA 4.0, but the artist's own
> `LICENSE.txt` — reproduced unmodified in `LICENSE-caliente.txt` — says
> CC BY-SA 4.0, and that is what is relied on here. If it ever needs settling,
> ask the artist rather than either table.

`caliente.svg` is a [piece-packager][packager] sprite sheet: one `<svg>` holding
twelve `<g id="wp">`-style groups, one per colour and kind, each a stack of flat
`<path>` layers, authored to a 40-unit frame that is one board square.

[cc-gpl]: https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/
[packager]: https://github.com/deverac/piece-packager

## Regenerating

```sh
swift Pieces/GeneratePieceArt.swift
```

Run from the repository root; add a set name to convert just one. It writes
`ios/Oddfish/DesignSystem/PieceArt/<Set>PieceArt.swift` and prints one line per
piece — box, foot line, layer count — so a regeneration that quietly changed a
set shows up in the run, not just in the diff.

The converter does four things worth knowing about:

1. **It normalises to the 40-unit frame**, baking in group transforms. That
   frame is what puts a set on one floor and one size ramp before the app scales
   anything.
2. **It derives the silhouette** by expanding every stroke into the area it
   covers and unioning the whole stack. This is not tidiness: Caliente draws the
   king's cross and the rook's battlements *only* as strokes, so a fills-only
   outline would lose both. The silhouette is what the app fills for the flat
   style and tints for the mode glyphs.
3. **It measures facets rather than copying them.** A lighter face painted as
   solid `#8C8C8C` and one painted as white at a quarter opacity reduce to the
   same signed number — *this face is a third of the way lighter than the body* —
   which is what lets the app restate them in any board theme's inks.
4. **It maps every colour to one of four roles** — body, outline, facet, ground
   shadow — declared per set and per army in `specs` at the top of the file.

It refuses to guess. An undeclared colour, an unsupported command, a non-uniform
transform, or a layer that resolves to painting nothing at all stops the run
with an error naming the set, the piece and the layer.

## Adding another set

The reader is deliberately more capable than Caliente needs. Three other sets
were converted through it and then removed for their licences, not their
geometry, and it kept what they taught it: relative commands, elliptical arcs,
smooth and quadratic curves, `<rect>` with rounded corners, CSS `style`
attributes, fill/stroke/opacity inherited through nested groups, and even-odd
fills. Most sets will need some of that.

1. Drop `<name>.svg` in this directory.
2. Add a `SetSpec` to `specs` naming each colour's role. Run the generator; it
   will tell you about any colour you missed.
3. Add a `PieceSet` case with a `title`, a `detail` and a `credit` — the credit
   is what the app shows on its licence screen, so it is not optional in
   practice. Restore the set picker in `BoardAppearanceView`, which was removed
   when the app dropped to one set.
4. Record the licence in `COPYRIGHT.md`.

Nothing needs adding to `PieceMetrics`: it reads each set's drawing boxes rather
than tabulating them, because a drawing box is a fact about the drawing.

**Check the licence first.** `piece-packager` carries over 80 sets and most of
them cannot ship in a GPLv3 app. GPL-compatible ones include Chessnut
(Apache 2.0), Fantasy, Spatial and Celtic (MIT), Cburnett, Merida and Mono
(GPLv2+), Shapes (CC BY-SA 4.0), Kiwen-suwi (CC BY 4.0) and RhosGFX (CC0).
Anything marked non-commercial, "freeware", or carrying no licence at all is
not usable here, however good it looks.
