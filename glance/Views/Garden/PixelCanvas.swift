import SwiftUI

struct PixelCanvas: View {
    let grid: PixelGrid
    var pixelSize: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            let rows = grid.count
            guard rows > 0 else { return }
            let cols = grid[0].count

            let totalWidth = CGFloat(cols) * pixelSize
            let totalHeight = CGFloat(rows) * pixelSize
            let offsetX = (size.width - totalWidth) / 2
            let offsetY = (size.height - totalHeight) / 2

            for row in 0..<rows {
                for col in 0..<grid[row].count {
                    guard let color = grid[row][col] else { continue }
                    let rect = CGRect(
                        x: offsetX + CGFloat(col) * pixelSize,
                        y: offsetY + CGFloat(row) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(
            width: grid.isEmpty ? 0 : CGFloat(grid[0].count) * pixelSize,
            height: CGFloat(grid.count) * pixelSize
        )
    }
}
