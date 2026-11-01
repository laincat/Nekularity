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

    /// Wide blocks take the whole width and reset the column heights, so a full
    /// width strip never sits beside a half block.
    private func arrange(width: CGFloat, subviews: Subviews) -> ([CGRect], CGFloat) {
        let columnWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        var heights = Array(repeating: CGFloat.zero, count: columns)
        var frames: [CGRect] = []

        for subview in subviews {
            let wide = subview[WideBlockKey.self]
            if wide {
                let top = heights.max() ?? 0
                let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
                frames.append(CGRect(x: 0, y: top, width: width, height: size.height))
                heights = Array(repeating: top + size.height + spacing, count: columns)
                continue
            }
            let column = heights.enumerated().min { $0.element < $1.element }?.offset ?? 0
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            frames.append(CGRect(x: CGFloat(column) * (columnWidth + spacing),
                                 y: heights[column], width: columnWidth, height: size.height))
            heights[column] += size.height + spacing
        }
        return (frames, max(0, (heights.max() ?? spacing) - spacing))
    }
}

/// Whether a block wants the full width.
struct WideBlockKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// Marks a block as full width inside `MasonryLayout`.
    func wideBlock(_ wide: Bool = true) -> some View {
        layoutValue(key: WideBlockKey.self, value: wide)
    }
}
