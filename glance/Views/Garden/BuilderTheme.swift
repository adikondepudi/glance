import SwiftUI

struct BuilderTheme: GardenTheme {

    // MARK: - Color Palette

    private let skin = Color(red: 0.93, green: 0.75, blue: 0.60)
    private let hair = Color(red: 0.35, green: 0.25, blue: 0.18)
    private let shirt = Color(red: 0.30, green: 0.55, blue: 0.75)
    private let pants = Color(red: 0.35, green: 0.30, blue: 0.50)
    private let boots = Color(red: 0.30, green: 0.22, blue: 0.15)
    private let tool = Color(red: 0.55, green: 0.50, blue: 0.45)
    private let toolHead = Color(red: 0.65, green: 0.65, blue: 0.65)

    private let dirt = Color(red: 0.35, green: 0.25, blue: 0.15)
    private let dirtLight = Color(red: 0.42, green: 0.32, blue: 0.20)
    private let grass = Color(red: 0.25, green: 0.50, blue: 0.20)
    private let grassDark = Color(red: 0.18, green: 0.38, blue: 0.15)

    private let brick = Color(red: 0.65, green: 0.35, blue: 0.25)
    private let brickDark = Color(red: 0.50, green: 0.28, blue: 0.18)
    private let wood = Color(red: 0.55, green: 0.40, blue: 0.25)
    private let woodDark = Color(red: 0.42, green: 0.30, blue: 0.18)
    private let roof = Color(red: 0.50, green: 0.25, blue: 0.20)
    private let roofDark = Color(red: 0.40, green: 0.18, blue: 0.15)
    private let window = Color(red: 0.55, green: 0.75, blue: 0.90)
    private let windowFrame = Color(red: 0.42, green: 0.30, blue: 0.20)
    private let door = Color(red: 0.45, green: 0.32, blue: 0.20)
    private let doorKnob = Color(red: 0.75, green: 0.65, blue: 0.30)
    private let chimney = Color(red: 0.55, green: 0.30, blue: 0.22)
    private let smoke = Color(white: 0.85, opacity: 0.5)
    private let fence = Color(red: 0.60, green: 0.48, blue: 0.32)

    // Grid: 32 wide x 24 tall

    func pixelGrid(for stage: GardenStage, mood: CharacterMood) -> PixelGrid {
        var grid = makeEmptyGrid()
        drawGround(&grid)

        switch stage {
        case .empty:
            drawPersonIdle(&grid, mood: mood)
        case .started:
            drawFoundation(&grid)
            drawPersonHammering(&grid)
        case .building:
            drawFoundation(&grid)
            drawWallsPartial(&grid)
            drawPersonCarrying(&grid)
        case .shaping:
            drawFoundation(&grid)
            drawWallsFull(&grid)
            drawWindow(&grid)
            drawPersonOnLadder(&grid)
        case .almostDone:
            drawFoundation(&grid)
            drawWallsFull(&grid)
            drawWindow(&grid)
            drawDoor(&grid)
            drawRoof(&grid)
            drawPersonProud(&grid)
        case .complete:
            drawFoundation(&grid)
            drawWallsFull(&grid)
            drawWindow(&grid)
            drawDoor(&grid)
            drawRoof(&grid)
            drawChimney(&grid)
            drawSmoke(&grid)
            drawFence(&grid)
            drawPersonWaving(&grid)
        }

        return grid
    }

    // MARK: - Grid Setup

    private func makeEmptyGrid() -> PixelGrid {
        Array(repeating: Array(repeating: nil as Color?, count: 32), count: 24)
    }

    private func drawGround(_ grid: inout PixelGrid) {
        // Grass strip at row 19
        for col in 0..<32 {
            grid[19][col] = (col % 3 == 0) ? grassDark : grass
        }
        // Dirt rows 20-23
        for row in 20..<24 {
            for col in 0..<32 {
                grid[row][col] = (row + col) % 4 == 0 ? dirtLight : dirt
            }
        }
    }

    // MARK: - Building Stages

    private func drawFoundation(_ grid: inout PixelGrid) {
        // Stone foundation: rows 17-18, cols 10-23
        for row in 17...18 {
            for col in 10...23 {
                grid[row][col] = (row + col) % 2 == 0 ? brickDark : brick
            }
        }
    }

    private func drawWallsPartial(_ grid: inout PixelGrid) {
        // Half walls: rows 13-16, cols 10-23
        for row in 13...16 {
            for col in 10...23 {
                if col == 10 || col == 23 {
                    grid[row][col] = brickDark
                } else {
                    grid[row][col] = (row + col) % 3 == 0 ? brickDark : brick
                }
            }
        }
    }

    private func drawWallsFull(_ grid: inout PixelGrid) {
        // Full walls: rows 9-16, cols 10-23
        for row in 9...16 {
            for col in 10...23 {
                if col == 10 || col == 23 {
                    grid[row][col] = brickDark
                } else {
                    grid[row][col] = (row + col) % 3 == 0 ? brickDark : brick
                }
            }
        }
    }

    private func drawWindow(_ grid: inout PixelGrid) {
        // Window at rows 11-13, cols 19-21
        for row in 11...13 {
            for col in 19...21 {
                if row == 11 || row == 13 || col == 19 || col == 21 {
                    grid[row][col] = windowFrame
                } else {
                    grid[row][col] = window
                }
            }
        }
    }

    private func drawDoor(_ grid: inout PixelGrid) {
        // Door at rows 13-16, cols 13-15
        for row in 13...16 {
            for col in 13...15 {
                grid[row][col] = door
            }
        }
        grid[15][15] = doorKnob
    }

    private func drawRoof(_ grid: inout PixelGrid) {
        // Triangular roof: rows 4-8
        let roofData: [(row: Int, startCol: Int, endCol: Int)] = [
            (8, 9, 24),
            (7, 11, 22),
            (6, 13, 20),
            (5, 15, 18),
            (4, 16, 17),
        ]
        for (row, startCol, endCol) in roofData {
            for col in startCol...endCol {
                grid[row][col] = (col == startCol || col == endCol) ? roofDark : roof
            }
        }
    }

    private func drawChimney(_ grid: inout PixelGrid) {
        // Chimney at cols 20-21, rows 3-7
        for row in 3...7 {
            grid[row][20] = chimney
            grid[row][21] = chimney
        }
    }

    private func drawSmoke(_ grid: inout PixelGrid) {
        grid[2][21] = smoke
        grid[1][20] = smoke
        grid[0][21] = smoke
    }

    private func drawFence(_ grid: inout PixelGrid) {
        // Small fence on the right: cols 25-30, rows 17-18
        for col in stride(from: 25, through: 30, by: 2) {
            grid[16][col] = fence
            grid[17][col] = fence
            grid[18][col] = fence
        }
        // Horizontal rail
        for col in 25...30 {
            grid[17][col] = fence
        }
    }

    // MARK: - Character Poses

    private func drawPersonIdle(_ grid: inout PixelGrid, mood: CharacterMood) {
        let x = 4 // left side of lot
        let y = 12 // standing on ground (feet at row 18)
        drawPersonBase(&grid, x: x, y: y)
        if mood == .sad {
            // Head down
            grid[y][x + 1] = hair
            grid[y + 1][x + 1] = skin
        } else {
            // Normal standing
            grid[y][x + 1] = hair
            grid[y][x + 2] = hair
            grid[y + 1][x + 1] = skin
            grid[y + 1][x + 2] = skin
        }
        // Blueprint in hand
        if mood != .sad {
            grid[y + 4][x + 3] = Color.white.opacity(0.8)
            grid[y + 5][x + 3] = Color.white.opacity(0.8)
        }
    }

    private func drawPersonHammering(_ grid: inout PixelGrid) {
        let x = 6
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
        // Arm with hammer raised
        grid[y + 3][x + 3] = skin
        grid[y + 2][x + 3] = tool
        grid[y + 1][x + 3] = toolHead
    }

    private func drawPersonCarrying(_ grid: inout PixelGrid) {
        let x = 6
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
        // Carrying a brick above head
        grid[y + 3][x + 3] = skin
        grid[y - 1][x + 1] = brick
        grid[y - 1][x + 2] = brick
    }

    private func drawPersonOnLadder(_ grid: inout PixelGrid) {
        let x = 7
        let y = 8 // higher up
        // Ladder
        for row in 9...18 {
            grid[row][8] = wood
            grid[row][9] = wood
        }
        for row in stride(from: 10, through: 18, by: 2) {
            grid[row][8] = woodDark
            grid[row][9] = woodDark
        }
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
    }

    private func drawPersonProud(_ grid: inout PixelGrid) {
        let x = 4
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
        // Hands on hips
        grid[y + 3][x] = skin
        grid[y + 3][x + 3] = skin
    }

    private func drawPersonWaving(_ grid: inout PixelGrid) {
        let x = 2
        let y = 12
        drawPersonBase(&grid, x: x, y: y)
        drawPersonHead(&grid, x: x, y: y)
        // Waving arm
        grid[y + 2][x + 3] = skin
        grid[y + 1][x + 4] = skin
        grid[y][x + 4] = skin
    }

    // MARK: - Character Parts

    private func drawPersonHead(_ grid: inout PixelGrid, x: Int, y: Int) {
        grid[y][x + 1] = hair
        grid[y][x + 2] = hair
        grid[y + 1][x + 1] = skin
        grid[y + 1][x + 2] = skin
    }

    private func drawPersonBase(_ grid: inout PixelGrid, x: Int, y: Int) {
        // Neck
        grid[y + 2][x + 1] = skin
        // Torso
        grid[y + 3][x + 1] = shirt
        grid[y + 3][x + 2] = shirt
        grid[y + 4][x + 1] = shirt
        grid[y + 4][x + 2] = shirt
        // Legs
        grid[y + 5][x + 1] = pants
        grid[y + 5][x + 2] = pants
        grid[y + 6][x + 1] = pants
        grid[y + 6][x + 2] = pants
        // Boots
        grid[y + 7][x + 1] = boots
        grid[y + 7][x + 2] = boots
    }
}
