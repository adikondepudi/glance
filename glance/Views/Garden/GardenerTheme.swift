import SwiftUI

struct GardenerTheme: GardenTheme {

    // MARK: - Color Palette

    private let skin = Color(red: 0.93, green: 0.75, blue: 0.60)
    private let hair = Color(red: 0.60, green: 0.35, blue: 0.18)
    private let shirt = Color(red: 0.40, green: 0.65, blue: 0.40)
    private let pants = Color(red: 0.35, green: 0.30, blue: 0.45)
    private let boots = Color(red: 0.30, green: 0.22, blue: 0.15)
    private let tool = Color(red: 0.50, green: 0.42, blue: 0.30)
    private let toolHead = Color(red: 0.60, green: 0.60, blue: 0.60)
    private let waterCan = Color(red: 0.45, green: 0.55, blue: 0.65)
    private let water = Color(red: 0.45, green: 0.65, blue: 0.85)

    private let dirt = Color(red: 0.35, green: 0.25, blue: 0.15)
    private let dirtLight = Color(red: 0.42, green: 0.32, blue: 0.20)
    private let soilDark = Color(red: 0.28, green: 0.18, blue: 0.10)
    private let grass = Color(red: 0.25, green: 0.50, blue: 0.20)
    private let grassDark = Color(red: 0.18, green: 0.38, blue: 0.15)

    private let stem = Color(red: 0.20, green: 0.45, blue: 0.15)
    private let stemDark = Color(red: 0.15, green: 0.35, blue: 0.10)
    private let leaf = Color(red: 0.30, green: 0.60, blue: 0.25)
    private let leafDark = Color(red: 0.22, green: 0.48, blue: 0.18)
    private let flowerRed = Color(red: 0.85, green: 0.25, blue: 0.25)
    private let flowerYellow = Color(red: 0.90, green: 0.80, blue: 0.20)
    private let flowerPink = Color(red: 0.85, green: 0.50, blue: 0.60)
    private let flowerPurple = Color(red: 0.60, green: 0.35, blue: 0.70)
    private let sunflowerCenter = Color(red: 0.45, green: 0.30, blue: 0.15)

    private let fence = Color(red: 0.60, green: 0.48, blue: 0.32)
    private let fenceDark = Color(red: 0.48, green: 0.38, blue: 0.25)
    private let bench = Color(red: 0.50, green: 0.38, blue: 0.25)
    private let butterfly1 = Color(red: 0.85, green: 0.55, blue: 0.20)
    private let butterfly2 = Color(red: 0.90, green: 0.70, blue: 0.30)

    // Grid: 32 wide x 24 tall

    func pixelGrid(for stage: GardenStage, mood: CharacterMood) -> PixelGrid {
        var grid = makeEmptyGrid()
        drawGround(&grid)

        switch stage {
        case .empty:
            drawSoilPlot(&grid)
            drawPersonWithShovel(&grid, mood: mood)
        case .started:
            drawSoilPlot(&grid)
            drawSeeds(&grid)
            drawPersonKneeling(&grid)
        case .building:
            drawSoilPlot(&grid)
            drawSprouts(&grid)
            drawPersonWatering(&grid)
        case .shaping:
            drawSoilPlot(&grid)
            drawGrowingPlants(&grid)
            drawSmallFence(&grid)
            drawPersonTending(&grid)
        case .almostDone:
            drawSoilPlot(&grid)
            drawFlowers(&grid)
            drawSmallFence(&grid)
            drawPersonPicking(&grid)
        case .complete:
            drawSoilPlot(&grid)
            drawFullGarden(&grid)
            drawSmallFence(&grid)
            drawBench(&grid)
            drawButterfly(&grid)
            drawPersonOnBench(&grid)
        }

        return grid
    }

    // MARK: - Grid Setup

    private func makeEmptyGrid() -> PixelGrid {
        Array(repeating: Array(repeating: nil as Color?, count: 32), count: 24)
    }

    private func drawGround(_ grid: inout PixelGrid) {
        for col in 0..<32 {
            grid[19][col] = (col % 3 == 0) ? grassDark : grass
        }
        for row in 20..<24 {
            for col in 0..<32 {
                grid[row][col] = (row + col) % 4 == 0 ? dirtLight : dirt
            }
        }
    }

    // MARK: - Garden Elements

    private func drawSoilPlot(_ grid: inout PixelGrid) {
        // Garden plot: rows 17-18, cols 10-26
        for row in 17...18 {
            for col in 10...26 {
                grid[row][col] = (row + col) % 3 == 0 ? soilDark : dirt
            }
        }
    }

    private func drawSeeds(_ grid: inout PixelGrid) {
        // Small seed dots in the soil
        let seedCols = [12, 15, 18, 21, 24]
        for col in seedCols {
            grid[17][col] = Color(red: 0.50, green: 0.38, blue: 0.20)
        }
    }

    private func drawSprouts(_ grid: inout PixelGrid) {
        let sproutCols = [12, 15, 18, 21, 24]
        for col in sproutCols {
            grid[16][col] = stem
            grid[15][col] = leaf
        }
    }

    private func drawGrowingPlants(_ grid: inout PixelGrid) {
        // Taller plants with leaves
        let plantCols = [12, 15, 18, 21, 24]
        for (i, col) in plantCols.enumerated() {
            // Stem
            grid[14][col] = stem
            grid[15][col] = stem
            grid[16][col] = stem
            // Leaves alternate sides
            if i % 2 == 0 {
                grid[14][col - 1] = leaf
                grid[15][col + 1] = leafDark
            } else {
                grid[14][col + 1] = leaf
                grid[15][col - 1] = leafDark
            }
        }
    }

    private func drawFlowers(_ grid: inout PixelGrid) {
        let flowers: [(col: Int, color: Color)] = [
            (12, flowerRed), (15, flowerYellow), (18, flowerPink),
            (21, flowerPurple), (24, flowerRed)
        ]
        for (col, color) in flowers {
            // Stem
            grid[14][col] = stem
            grid[15][col] = stem
            grid[16][col] = stem
            // Leaves
            grid[15][col - 1] = leaf
            grid[15][col + 1] = leafDark
            // Flower head
            grid[13][col] = color
            grid[12][col] = color
            grid[13][col - 1] = color
            grid[13][col + 1] = color
        }
    }

    private func drawFullGarden(_ grid: inout PixelGrid) {
        // Sunflower on the left
        grid[11][12] = flowerYellow
        grid[10][12] = flowerYellow
        grid[10][11] = flowerYellow
        grid[10][13] = flowerYellow
        grid[11][11] = flowerYellow
        grid[11][13] = flowerYellow
        grid[10][12] = sunflowerCenter
        grid[12][12] = stemDark
        grid[13][12] = stem
        grid[14][12] = stem
        grid[15][12] = stem
        grid[16][12] = stem
        grid[14][11] = leaf
        grid[15][13] = leafDark

        // Various flowers
        let flowers: [(col: Int, color: Color, height: Int)] = [
            (15, flowerPink, 3), (18, flowerRed, 4),
            (21, flowerPurple, 3), (24, flowerYellow, 4)
        ]
        for (col, color, height) in flowers {
            for h in 0..<height {
                grid[16 - h][col] = stem
            }
            let top = 16 - height
            grid[top][col] = color
            grid[top - 1][col] = color
            grid[top][col - 1] = color
            grid[top][col + 1] = color
            // Leaf
            grid[16 - height / 2][col - 1] = leaf
            grid[16 - height / 2 + 1][col + 1] = leafDark
        }

        // Bush on the right
        for row in 15...17 {
            for col in 26...28 {
                grid[row][col] = (row + col) % 2 == 0 ? leafDark : leaf
            }
        }
        grid[14][27] = leaf
    }

    private func drawSmallFence(_ grid: inout PixelGrid) {
        // Fence posts
        for col in stride(from: 9, through: 27, by: 3) {
            grid[16][col] = fence
            grid[17][col] = fence
            grid[18][col] = fenceDark
        }
        // Horizontal rail
        for col in 9...27 {
            grid[17][col] = grid[17][col] ?? fence
        }
    }

    private func drawBench(_ grid: inout PixelGrid) {
        // Small bench: cols 2-6, row 17-18
        for col in 2...6 {
            grid[17][col] = bench
        }
        grid[18][2] = bench
        grid[18][6] = bench
    }

    private func drawButterfly(_ grid: inout PixelGrid) {
        // Butterfly near the flowers
        grid[8][20] = butterfly1
        grid[8][22] = butterfly1
        grid[9][21] = butterfly2
    }

    // MARK: - Character Poses

    private func drawPersonWithShovel(_ grid: inout PixelGrid, mood: CharacterMood) {
        let x = 3
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        if mood == .sad {
            grid[y][x + 1] = hair
            grid[y + 1][x + 1] = skin
            // Leaning on shovel
            grid[y + 3][x + 3] = tool
            grid[y + 4][x + 3] = tool
            grid[y + 5][x + 3] = tool
            grid[y + 6][x + 3] = tool
            grid[y + 7][x + 3] = toolHead
        } else {
            drawPersonHead(&grid, x: x, y: y)
            // Holding shovel upright
            grid[y + 3][x + 3] = skin
            grid[y + 4][x + 4] = tool
            grid[y + 5][x + 4] = tool
            grid[y + 6][x + 4] = tool
            grid[y + 7][x + 4] = toolHead
        }
    }

    private func drawPersonKneeling(_ grid: inout PixelGrid) {
        let x = 3
        let y = 14 // lower since kneeling
        // Head
        grid[y][x + 1] = hair
        grid[y][x + 2] = hair
        grid[y + 1][x + 1] = skin
        grid[y + 1][x + 2] = skin
        // Neck + torso
        grid[y + 2][x + 1] = skin
        grid[y + 3][x + 1] = shirt
        grid[y + 3][x + 2] = shirt
        // Arm reaching to soil
        grid[y + 3][x + 3] = skin
        grid[y + 3][x + 4] = skin
        // Kneeling legs
        grid[y + 4][x + 1] = pants
        grid[y + 4][x + 2] = pants
        grid[y + 4][x] = boots
    }

    private func drawPersonWatering(_ grid: inout PixelGrid) {
        let x = 3
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
        // Watering can
        grid[y + 3][x + 3] = skin
        grid[y + 3][x + 4] = waterCan
        grid[y + 3][x + 5] = waterCan
        grid[y + 4][x + 5] = water
        grid[y + 5][x + 5] = water
    }

    private func drawPersonTending(_ grid: inout PixelGrid) {
        let x = 3
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
        // Arm out tending
        grid[y + 3][x + 3] = skin
        grid[y + 3][x + 4] = skin
    }

    private func drawPersonPicking(_ grid: inout PixelGrid) {
        let x = 3
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
        // Arm reaching up (picking flower)
        grid[y + 2][x + 3] = skin
        grid[y + 1][x + 3] = skin
        grid[y][x + 3] = flowerRed
    }

    private func drawPersonOnBench(_ grid: inout PixelGrid) {
        let x = 3
        let y = 11 // sitting height
        // Head
        grid[y][x + 1] = hair
        grid[y][x + 2] = hair
        grid[y + 1][x + 1] = skin
        grid[y + 1][x + 2] = skin
        // Neck
        grid[y + 2][x + 1] = skin
        // Torso
        grid[y + 3][x + 1] = shirt
        grid[y + 3][x + 2] = shirt
        grid[y + 4][x + 1] = shirt
        grid[y + 4][x + 2] = shirt
        // Sitting — legs horizontal on bench
        grid[y + 5][x + 1] = pants
        grid[y + 5][x + 2] = pants
        grid[y + 5][x + 3] = pants
        // Feet
        grid[y + 6][x + 3] = boots
        grid[y + 6][x + 4] = boots
    }

    // MARK: - Character Parts

    private func drawPersonHead(_ grid: inout PixelGrid, x: Int, y: Int) {
        grid[y][x + 1] = hair
        grid[y][x + 2] = hair
        grid[y + 1][x + 1] = skin
        grid[y + 1][x + 2] = skin
    }

    private func drawPersonBase(_ grid: inout PixelGrid, x: Int, y: Int) {
        grid[y + 2][x + 1] = skin
        grid[y + 3][x + 1] = shirt
        grid[y + 3][x + 2] = shirt
        grid[y + 4][x + 1] = shirt
        grid[y + 4][x + 2] = shirt
        grid[y + 5][x + 1] = pants
        grid[y + 5][x + 2] = pants
        grid[y + 6][x + 1] = pants
        grid[y + 6][x + 2] = pants
        grid[y + 7][x + 1] = boots
        grid[y + 7][x + 2] = boots
    }
}
