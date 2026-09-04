import SwiftUI

/// Choosing how the board looks, with the board shown while you choose.
///
/// A swatch cannot answer the only question that matters here — whether the
/// pieces read against the squares — so every control is above a real board
/// drawn with the real piece shapes at a real size.
struct BoardAppearanceView: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                BoardPreview(
                    theme: settings.boardTheme,
                    set: settings.pieceSet,
                    style: settings.pieceStyle,
                    decoration: settings.boardDecoration
                )
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .accessibilityIdentifier("appearance-preview")
            } header: {
                Text("Preview")
            } footer: {
                Text("Both armies share one silhouette, so a style change never makes the two sides look like different sets.")
            }
            .listRowBackground(OddfishTheme.surface)

            Section("Board") {
                // A navigation-link picker rather than a menu: the rows carry
                // swatches, and a menu shrinks them to the point where the
                // colours they exist to show are no longer legible.
                Picker("Theme", selection: $settings.boardThemeID) {
                    ForEach(BoardTheme.all) { theme in
                        HStack(spacing: 10) {
                            ThemeSwatch(theme: theme)
                            Text(theme.title)
                        }
                        .tag(theme.id)
                        .accessibilityIdentifier("theme-\(theme.id)")
                    }
                }
                .pickerStyle(.navigationLink)
                .accessibilityIdentifier("appearance-theme")
            }

            Section {
                // No set picker: the app ships one set, and a picker with one
                // option is a control that cannot be operated. The footer still
                // names the set, which is also how its artist is credited.
                Picker("Style", selection: $settings.pieceStyle) {
                    ForEach(PieceStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("appearance-piece-style")
            } header: {
                Text("Pieces")
            } footer: {
                // Names the set and its artist. Caliente is CC BY-SA 4.0, so
                // the credit is a licence term rather than a courtesy — see
                // Settings → Licence for the full attribution.
                Text(settings.pieceSet.detail)
            }
            .listRowBackground(OddfishTheme.surface)

            Section {
                Toggle(isOn: $settings.showsCoordinates) {
                    Label("Coordinates", systemImage: "textformat.abc")
                }
                Toggle(isOn: $settings.highlightsLastMove) {
                    Label("Highlight last move", systemImage: "square.dashed")
                }
            } header: {
                Text("Detail")
            } footer: {
                Text("Legal-move markers are controlled by Move hints, under Feedback.")
            }
            .listRowBackground(OddfishTheme.surface)
        }
        .navigationTitle("Board")
        .navigationBarTitleDisplayMode(.inline)
        // The parent settings screen wears the app's palette on its Form rows;
        // a pushed screen left on the system grouped background reads as a
        // different app. Same treatment, same row surface.
        .scrollContentBackground(.hidden)
        .background(OddfishTheme.canvas)
    }
}

/// A three-colour chip: the two squares and the accent the theme uses for
/// markers, which is the part a plain two-square swatch would hide.
private struct ThemeSwatch: View {
    let theme: BoardTheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(theme.lightSquare)
            Rectangle().fill(theme.darkSquare)
            Rectangle().fill(theme.indicator)
        }
        .frame(width: 36, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(theme.frame.opacity(0.6), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Four files of a real board, with both armies and the markers a game actually
/// draws, so a choice can be judged before it is committed.
struct BoardPreview: View {
    let theme: BoardTheme
    var set: PieceSet = .caliente
    let style: PieceStyle
    var decoration: BoardDecoration = .default
    var square: CGFloat = 46

    private let layout: [[PieceKind?]] = [
        [.rook, .queen, .king, .knight],
        [.pawn, nil, .pawn, .bishop]
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { visualRow in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { column in
                        // The lower half mirrors the layout so the white army
                        // faces the black one, but the square colour and the
                        // rank label must follow the *visual* row or the board
                        // numbers itself 4, 3, 1, 2.
                        cell(
                            visualRow: visualRow,
                            layoutRow: visualRow < 2 ? visualRow : 3 - visualRow,
                            column: column,
                            isTopArmy: visualRow < 2
                        )
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: OddfishTheme.Radius.board, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OddfishTheme.Radius.board, style: .continuous)
                .strokeBorder(theme.frame.opacity(0.55), lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Board preview: \(theme.title), \(set.title) pieces, \(style.title) style")
    }

    @ViewBuilder
    private func cell(visualRow: Int, layoutRow: Int, column: Int, isTopArmy: Bool) -> some View {
        let isLight = !(visualRow + column).isMultiple(of: 2)
        let kind = layout[layoutRow][column]

        ZStack {
            Rectangle().fill(isLight ? theme.lightSquare : theme.darkSquare)

            // One square of each marker, so the accent colour is judged in place
            // rather than as an abstract swatch.
            if decoration.highlightsLastMove, visualRow == 1, column == 1 {
                Rectangle().fill(theme.indicator.opacity(0.24))
            }
            if visualRow == 2, column == 2 {
                Circle()
                    .fill(theme.moveDot(onLight: isLight))
                    .frame(width: square * 0.26, height: square * 0.26)
            }

            if let kind {
                ChessPieceView(
                    piece: Piece(color: isTopArmy ? .black : .white, kind: kind),
                    square: square,
                    themeOverride: theme,
                    setOverride: set,
                    styleOverride: style
                )
            }

            if decoration.showsCoordinates, column == 0 {
                Text("\(4 - visualRow)")
                    .font(.system(size: max(7, square * 0.16), weight: .bold, design: .rounded))
                    .foregroundStyle(theme.coordinate(onLight: isLight))
                    .padding(square * 0.055)
                    .frame(width: square, height: square, alignment: .topLeading)
            }
        }
        .frame(width: square, height: square)
    }
}

#Preview("Every theme") {
    ScrollView {
        VStack(spacing: 20) {
            ForEach(BoardTheme.all) { theme in
                VStack(spacing: 6) {
                    Text(theme.title).font(.oddfishCaption)
                    HStack(spacing: 12) {
                        ForEach(PieceStyle.allCases) { style in
                            BoardPreview(theme: theme, style: style, square: 34)
                        }
                    }
                }
            }
        }
        .padding()
    }
    .background(OddfishTheme.canvas)
}
