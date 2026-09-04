# Oddfish brand system

Oddfish uses one mark everywhere: **Split O**, a precise rounded `O` divided along a diagonal current. Its two halves sit slightly off-axis and a single coral diamond occupies the center. The construction expresses an intelligent system with one intentional rule break; it does not rely on a fish mascot or a literal chess piece.

## Core assets

- `OddfishMark.svg` — primary full-colour mark on a transparent background.
- `OddfishMark-Monochrome.svg` — ivory single-colour mark for dark backgrounds.
- `OddfishMark-Monochrome-Dark.svg` — midnight single-colour mark for light backgrounds.
- `OddfishLogo-Horizontal.svg` — horizontal mark and wordmark lockup for dark backgrounds.
- `OddfishLogo-Horizontal-Light.svg` — horizontal lockup for light backgrounds.
- `OddfishLogo-Vertical.svg` — centered mark and wordmark lockup for dark backgrounds.
- `OddfishLogo-Vertical-Light.svg` — centered lockup for light backgrounds.
- `OddfishAppIcon.svg` — opaque 1024×1024 app-icon master.

The `Explorations/V2` directory preserves the three concepts reviewed before Split O was selected. It is design history, not a source for production exports.

## Colour

| Role | Hex | Use |
| --- | --- | --- |
| Midnight | `#0E1620` | Primary background and dark monochrome mark |
| Sea glass | `#4FE0DD` | Primary mark and primary actions |
| Ivory | `#F2F6F8` | Wordmark and reversed monochrome mark |
| Coral | `#FF665C` | Split O's center tile, urgency, and loss |
| Deep sea glass | `#1C7D8C` | Full-colour mark on light backgrounds |
| Deep coral | `#D94841` | Center tile on light backgrounds |

Gold remains exclusive to Gil and crown rewards; it is not part of the corporate mark.

## Typography

Use the system display sans at black weight for the `ODDFISH` wordmark. In the iOS app, launch screen, and supplied SVG lockups this is the Apple system face with a neutral—not rounded—construction. Supporting interface text continues to use the existing rounded system family.

## Usage

- Keep clear space around the mark at least equal to the width of its center diamond.
- Use the primary full-colour mark only on midnight or another solid dark surface.
- Use the deep full-colour lockup on light surfaces and a monochrome mark when only one ink is available.
- Keep the coral center tile with the full-colour mark. In monochrome, the tile uses the same colour as the split ring.
- The icon-only mark may be used down to 20 points or 20 pixels. Do not use a wordmark lockup below 140 pixels wide.
- The app icon uses only the mark on an opaque midnight field; never add text inside the icon.
- Do not rotate, close, or realign the two halves. The diagonal displacement is part of the mark.
- Do not add fish anatomy, chess pieces, gradients, gloss, shadows, outlines, or enclosing rings.
- Do not recreate the mark from text glyphs or separate geometric approximations.

The production PNGs in the Xcode asset catalogue are exports of these SVG masters.

## Exporting production assets

Run `./Brand/export-assets.sh` on macOS. It exports square 1×, 2×, and 3× copies of the shared mark and flattens the app-icon master into an opaque RGB PNG. Do not use `pngcrush -c 2` to remove icon alpha; it discards channel information instead of compositing the SVG export.
