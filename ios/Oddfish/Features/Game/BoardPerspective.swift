import Foundation

/// Converts immutable chess coordinates to and from the board's visual grid.
/// Keeping this out of SwiftUI makes the Black-side flip exact and testable.
nonisolated struct BoardPerspective: Hashable, Sendable {
    let color: PieceColor

    func visualCoordinates(for square: Square) -> (file: Int, rank: Int) {
        if color == .white {
            return (square.file, 7 - square.rank)
        }
        return (7 - square.file, square.rank)
    }

    func square(visualFile: Int, visualRank: Int) -> Square? {
        guard (0..<8).contains(visualFile), (0..<8).contains(visualRank) else { return nil }
        if color == .white {
            return Square(file: visualFile, rank: 7 - visualRank)
        }
        return Square(file: 7 - visualFile, rank: visualRank)
    }

    var bottomRank: Int { color == .white ? 0 : 7 }
    var leftFile: Int { color == .white ? 0 : 7 }
}
