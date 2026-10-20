import Foundation

public enum Tile: UInt8, Sendable {
    case wall
    case empty
    case dot
    case powerPellet
    case ghostDoor

    public var isWall: Bool { self == .wall }
    public var isPellet: Bool { self == .dot || self == .powerPellet }
}

/// The canonical 28 x 31 Pac-Man playfield, with four power pellets,
/// 240 regular dots, a ghost house, and two tunnel mouths.
public final class Maze: @unchecked Sendable {
    public static let columns = 28
    public static let rows = 31
    public static let tunnelRow = 14
    public static let ghostHouseReturnTile = GridPoint(x: 13, y: 14)

    public static let layout: [String] = [
        "############################",
        "#............##............#",
        "#.####.#####.##.#####.####.#",
        "#o####.#####.##.#####.####o#",
        "#.####.#####.##.#####.####.#",
        "#..........................#",
        "#.####.##.########.##.####.#",
        "#.####.##.########.##.####.#",
        "#......##....##....##......#",
        "######.##### ## #####.######",
        "     #.##### ## #####.#     ",
        "     #.##          ##.#     ",
        "     #.## ###--### ##.#     ",
        "######.## #      # ##.######",
        "      .   #      #   .      ",
        "######.## #      # ##.######",
        "     #.## ######## ##.#     ",
        "     #.##          ##.#     ",
        "     #.## ######## ##.#     ",
        "######.## ######## ##.######",
        "#............##............#",
        "#.####.#####.##.#####.####.#",
        "#.####.#####.##.#####.####.#",
        "#o..##.......  .......##..o#",
        "###.##.##.########.##.##.###",
        "###.##.##.########.##.##.###",
        "#......##....##....##......#",
        "#.##########.##.##########.#",
        "#.##########.##.##########.#",
        "#..........................#",
        "############################"
    ]

    public static let pacmanStart = Vec2(x: 13.5, y: 23.5)
    public static let blinkyStart = Vec2(x: 13.5, y: 11.5)
    public static let pinkyStart = Vec2(x: 13.5, y: 14.5)
    public static let inkyStart = Vec2(x: 11.5, y: 14.5)
    public static let clydeStart = Vec2(x: 15.5, y: 14.5)
    public static let ghostHouseCenter = Vec2(x: 13.5, y: 14.5)
    public static let fruitPosition = Vec2(x: 13.5, y: 17.5)

    public let grid: [[Tile]]
    public let initialPellets: Set<GridPoint>
    public let dotCount: Int
    public let powerPelletCount: Int

    /// Breadth-first distance to the ghost house, used by returning eyes.
    /// The table wraps through both tunnel mouths and treats the house door
    /// as walkable.
    public let houseDistance: [Int]

    public init() {
        var parsedGrid: [[Tile]] = []
        var pellets: Set<GridPoint> = []
        var dots = 0
        var powers = 0

        for (row, line) in Self.layout.enumerated() {
            var parsedRow: [Tile] = []
            for (column, character) in line.enumerated() {
                let tile: Tile
                switch character {
                case "#":
                    tile = .wall
                case ".":
                    tile = .dot
                    dots += 1
                    pellets.insert(GridPoint(x: column, y: row))
                case "o":
                    tile = .powerPellet
                    powers += 1
                    pellets.insert(GridPoint(x: column, y: row))
                case "-":
                    tile = .ghostDoor
                default:
                    tile = .empty
                }
                parsedRow.append(tile)
            }
            parsedGrid.append(parsedRow)
        }

        grid = parsedGrid
        initialPellets = pellets
        dotCount = dots
        powerPelletCount = powers
        houseDistance = Self.computeHouseDistances(for: parsedGrid)
    }

    public func tile(column: Int, row: Int) -> Tile {
        guard row >= 0, row < Self.rows else { return .wall }
        let wrappedColumn = ((column % Self.columns) + Self.columns) % Self.columns
        guard wrappedColumn >= 0, wrappedColumn < Self.columns else { return .wall }
        return grid[row][wrappedColumn]
    }

    public func tile(at point: GridPoint) -> Tile {
        tile(column: point.x, row: point.y)
    }

    public func isWalkable(column: Int, row: Int, allowDoor: Bool) -> Bool {
        let candidate = tile(column: column, row: row)
        if candidate.isWall { return false }
        if candidate == .ghostDoor && !allowDoor { return false }
        return true
    }

    public func isWalkable(_ point: GridPoint, allowDoor: Bool) -> Bool {
        isWalkable(column: point.x, row: point.y, allowDoor: allowDoor)
    }

    public func neighbor(of point: GridPoint, in direction: Direction) -> GridPoint {
        GridPoint(x: point.x + direction.dx, y: point.y + direction.dy)
            .wrapped(columns: Self.columns)
    }

    public func gridPoint(for position: Vec2) -> GridPoint {
        GridPoint(x: Int(floor(position.x)), y: Int(floor(position.y)))
    }

    public func isTunnel(column: Int, row: Int) -> Bool {
        row == Self.tunnelRow && (column < 6 || column > 21)
    }

    public func houseDistance(at point: GridPoint) -> Int {
        let wrapped = point.wrapped(columns: Self.columns)
        guard wrapped.y >= 0, wrapped.y < Self.rows else { return .max }
        return houseDistance[wrapped.y * Self.columns + wrapped.x]
    }

    private static func computeHouseDistances(for grid: [[Tile]]) -> [Int] {
        let count = columns * rows
        var distances = [Int](repeating: .max, count: count)
        var queue: [GridPoint] = [ghostHouseReturnTile]
        var head = 0
        distances[ghostHouseReturnTile.y * columns + ghostHouseReturnTile.x] = 0

        while head < queue.count {
            let current = queue[head]
            head += 1
            let currentDistance = distances[current.y * columns + current.x]

            for direction in Direction.allCases {
                var next = GridPoint(x: current.x + direction.dx, y: current.y + direction.dy)
                if !(0..<rows).contains(next.y) { continue }
                next = next.wrapped(columns: columns)
                let tile = grid[next.y][next.x]
                if tile.isWall { continue }
                let index = next.y * columns + next.x
                if distances[index] != .max { continue }
                distances[index] = currentDistance + 1
                queue.append(next)
            }
        }

        return distances
    }
}
