import NekularityKit
import SwiftUI

/// Places blocks down the shortest column.
///
/// The alternative is a two-column grid, which lines up rows and leaves ragged
/// holes whenever two blocks differ in height. A home screen made of blocks of
/// different heights is exactly that case, so the small amount of layout code is
/// worth it.
struct MasonryLayout: Layout {
    var spacing: CGFloat = 12
    var columns: Int = 2

    struct Cached {
        var sizes: [CGSize] = []
        var frames: [CGRect] = []
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cached {
        Cached()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cached) -> CGSize {
        let width = proposal.width ?? 0
        let (frames, height) = arrange(width: width, subviews: subviews)
        cache.frames = frames
        cache.height = height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Cached) {
        let (frames, _) = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in frames.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    /// A block spans one or more adjacent columns; other columns remain available.
    private func arrange(width: CGFloat, subviews: Subviews) -> ([CGRect], CGFloat) {
        let count = max(1, columns)
        let columnWidth = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        var heights = Array(repeating: CGFloat.zero, count: count)
        var frames: [CGRect] = []

        for subview in subviews {
            let span = min(count, max(1, subview[BlockSpanKey.self]))
            let column = HomeGrid.startColumn(heights: heights.map(Double.init), span: span)
            let top = heights[column..<(column + span)].max() ?? 0
            let blockWidth = columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
            let size = subview.sizeThatFits(ProposedViewSize(width: blockWidth, height: nil))
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing),
                                 y: top, width: blockWidth, height: size.height))
            for index in column..<(column + span) {
                heights[index] = top + size.height + spacing
            }
        }
        return (frames, max(0, (heights.max() ?? spacing) - spacing))
    }
}

struct BlockSpanKey: LayoutValueKey {
    static let defaultValue = 1
}

extension View {
    func blockSpan(_ span: Int) -> some View {
        layoutValue(key: BlockSpanKey.self, value: span)
    }
}
