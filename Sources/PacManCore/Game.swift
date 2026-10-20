import Foundation

public enum GamePhase: Equatable, Sendable {
    case attract
    case ready
    case playing
    case dying
    case levelComplete
    case gameOver
}

public enum GhostMode: Equatable, Sendable {
    case scatter
    case chase
}

public enum GhostKind: Int, CaseIterable, Sendable {
    case blinky
    case pinky
    case inky
    case clyde
}

public enum GhostState: Equatable, Sendable {
    case house
    case leaving
    case roam
    case eyes
}

public struct PacManState: Sendable {
    public var position: Vec2
    public var direction: Direction
    public var desiredDirection: Direction?
}

public struct Ghost: Sendable {
    public var kind: GhostKind
    public var position: Vec2
    public var direction: Direction
    public var state: GhostState
    public var homePosition: Vec2
    public var releaseDelay: Double
    public var forceReverse: Bool
}

public enum FruitKind: Int, CaseIterable, Sendable {
    case cherry
    case strawberry
    case orange
    case apple
    case melon
    case galaxian
    case bell
    case key

    public var points: Int {
        switch self {
        case .cherry: return 100
        case .strawberry: return 300
        case .orange: return 500
        case .apple: return 700
        case .melon: return 1_000
        case .galaxian: return 2_000
        case .bell: return 3_000
        case .key: return 5_000
        }
    }

    public var label: String {
        switch self {
        case .cherry: return "CHERRY"
        case .strawberry: return "STRAWBERRY"
        case .orange: return "ORANGE"
        case .apple: return "APPLE"
        case .melon: return "MELON"
        case .galaxian: return "GALAXIAN"
        case .bell: return "BELL"
        case .key: return "KEY"
        }
    }

    public static func forLevel(_ level: Int) -> FruitKind {
        switch level {
        case 1: return .cherry
        case 2: return .strawberry
        case 3, 4: return .orange
        case 5, 6: return .apple
        case 7, 8: return .melon
        case 9, 10: return .galaxian
        case 11, 12: return .bell
        default: return .key
        }
    }
}

public struct ActiveFruit: Sendable {
    public var kind: FruitKind
    public var position: Vec2
    public var remaining: Double
}

public struct ScorePopup: Sendable {
    public var position: Vec2
    public var text: String
    public var remaining: Double
    public var duration: Double

    public var progress: Double {
        guard duration > 0 else { return 1 }
        return 1 - max(0, min(1, remaining / duration))
    }
}

public enum GameEvent: Equatable, Sendable {
    case gameStart
    case chomp
    case powerPellet
    case ghostEaten(combo: Int)
    case fruitEaten(FruitKind)
    case extraLife
    case pacDeath
    case levelComplete
    case gameOver
}

public final class PacManGame {
    public let maze: Maze

    public private(set) var pac: PacManState
    public private(set) var ghosts: [Ghost]
    public private(set) var pellets: Set<GridPoint>
    public private(set) var phase: GamePhase = .attract
    public private(set) var score = 0
    public private(set) var highScore: Int
    public private(set) var level = 1
    public private(set) var lives = 3
    public private(set) var elapsed = 0.0
    public private(set) var readyRemaining = 0.0
    public private(set) var frightenedRemaining = 0.0
    public private(set) var ghostMode: GhostMode = .scatter
    public private(set) var activeFruit: ActiveFruit?
    public private(set) var popups: [ScorePopup] = []
    public private(set) var isPaused = false
    public private(set) var deathFraction = 0.0
    public private(set) var levelClearFraction = 0.0

    private var events: [GameEvent] = []
    private var directionBufferRemaining = 0.0
    private var deathElapsed = 0.0
    private var levelClearElapsed = 0.0
    private var freezeRemaining = 0.0
    private var ghostCombo = 0
    private var modeStage = 0
    private var modeTimer = 7.0
    private var dotsEatenThisLevel = 0
    private var nextFruitThresholdIndex = 0
    private var extraLifeAwarded = false
    private var rng = SplitMix64(seed: 0x5EED_CAFE_F00D_1234)

    private let deathDuration = 1.65
    private let levelClearDuration = 2.15
    private let fruitThresholds = [70, 170]

    private static let modeSchedule: [(mode: GhostMode, duration: Double)] = [
        (.scatter, 7.0),
        (.chase, 20.0),
        (.scatter, 7.0),
        (.chase, 20.0),
        (.scatter, 5.0),
        (.chase, 20.0),
        (.scatter, 5.0),
        (.chase, .infinity)
    ]

    public init(highScore: Int = 0) {
        let maze = Maze()
        self.maze = maze
        self.highScore = max(0, highScore)
        self.pellets = maze.initialPellets
        self.pac = PacManState(position: Maze.pacmanStart, direction: .left, desiredDirection: nil)
        self.ghosts = []
        resetActors()
    }

    // MARK: - Public state

    public var remainingPellets: Int {
        pellets.count
    }

    public var isFrightened: Bool {
        frightenedRemaining > 0
    }

    public var frightenedFlashOn: Bool {
        guard frightenedRemaining > 0, frightenedRemaining <= 2.0 else { return false }
        return Int(elapsed * 8) % 2 == 0
    }

    public var currentFruitKind: FruitKind {
        FruitKind.forLevel(level)
    }

    public var displayedLives: Int {
        max(0, lives - 1)
    }

    public var dotsEaten: Int {
        dotsEatenThisLevel
    }

    public var pacSpeed: Double {
        let base = 7.35 + min(Double(level - 1) * 0.11, 0.9)
        return frightenedRemaining > 0 ? base + 0.28 : base
    }

    public var ghostSpeed: Double {
        min(6.55 + Double(level - 1) * 0.14, 8.1)
    }

    public var frightenedDuration: Double {
        max(2.0, 7.0 - Double(level - 1) * 0.42)
    }

    // MARK: - Commands

    public func requestStart() {
        guard phase == .attract || phase == .gameOver else { return }
        startNewGame()
    }

    public func startNewGame() {
        score = 0
        level = 1
        lives = 3
        extraLifeAwarded = false
        pellets = maze.initialPellets
        dotsEatenThisLevel = 0
        nextFruitThresholdIndex = 0
        activeFruit = nil
        popups.removeAll()
        events.removeAll()
        isPaused = false
        deathElapsed = 0
        deathFraction = 0
        levelClearElapsed = 0
        levelClearFraction = 0
        readyRemaining = 2.0
        resetActors()
        phase = .ready
        events.append(.gameStart)
    }

    public func togglePause() {
        guard phase == .playing else { return }
        isPaused.toggle()
    }

    public func pause() {
        if phase == .playing {
            isPaused = true
        }
    }

    public func setDirection(_ direction: Direction) {
        guard phase == .playing, !isPaused else { return }
        pac.desiredDirection = direction
        directionBufferRemaining = 0.32
    }

    public func drainEvents() -> [GameEvent] {
        let drained = events
        events.removeAll()
        return drained
    }

    // MARK: - Update loop

    public func update(dt rawDeltaTime: Double) {
        guard rawDeltaTime > 0, !isPaused else { return }
        let deltaTime = min(rawDeltaTime, 0.05)
        elapsed += deltaTime
        updatePopups(deltaTime)

        switch phase {
        case .attract, .gameOver:
            break
        case .ready:
            readyRemaining -= deltaTime
            if readyRemaining <= 0 {
                readyRemaining = 0
                phase = .playing
            }
        case .playing:
            updatePlaying(deltaTime)
        case .dying:
            deathElapsed += deltaTime
            deathFraction = min(1, deathElapsed / deathDuration)
            if deathElapsed >= deathDuration {
                finishDeath()
            }
        case .levelComplete:
            levelClearElapsed += deltaTime
            levelClearFraction = min(1, levelClearElapsed / levelClearDuration)
            if levelClearElapsed >= levelClearDuration {
                advanceLevel()
            }
        }
    }

    private func updatePlaying(_ deltaTime: Double) {
        if freezeRemaining > 0 {
            freezeRemaining = max(0, freezeRemaining - deltaTime)
            return
        }

        if frightenedRemaining > 0 {
            frightenedRemaining = max(0, frightenedRemaining - deltaTime)
            if frightenedRemaining == 0 {
                ghostCombo = 0
            }
        } else {
            updateGhostMode(deltaTime)
        }

        updateFruit(deltaTime)
        updateDirectionBuffer(deltaTime)
        movePac(deltaTime)

        guard phase == .playing else { return }

        updateGhosts(deltaTime)
        collectFruitIfTouching()
        resolveCollisions()

        if phase == .playing, pellets.isEmpty {
            beginLevelComplete()
        }
    }

    private func updateDirectionBuffer(_ deltaTime: Double) {
        guard directionBufferRemaining > 0 else { return }
        directionBufferRemaining = max(0, directionBufferRemaining - deltaTime)
        if directionBufferRemaining == 0 {
            pac.desiredDirection = nil
        }
    }

    // MARK: - Pac-Man movement

    private func movePac(_ deltaTime: Double) {
        if let desired = pac.desiredDirection, desired == pac.direction.opposite {
            pac.direction = desired
            pac.desiredDirection = nil
            directionBufferRemaining = 0
        }

        var speed = pacSpeed
        let row = Int(floor(pac.position.y))
        let column = Int(floor(pac.position.x))
        if maze.isTunnel(column: column, row: row) {
            speed *= 0.72
        }

        var remaining = speed * deltaTime
        var iterations = 0

        while remaining > 1e-9, iterations < 10 {
            iterations += 1

            if isAtTileCenter(pac.position) {
                wrapAndSnapToCenter(&pac.position)
                let tile = maze.gridPoint(for: pac.position)

                if let desired = pac.desiredDirection {
                    if canPacMove(from: tile, direction: desired) {
                        pac.direction = desired
                        pac.desiredDirection = nil
                        directionBufferRemaining = 0
                    } else if desired == pac.direction {
                        pac.desiredDirection = nil
                        directionBufferRemaining = 0
                    }
                }

                if !canPacMove(from: tile, direction: pac.direction) {
                    break
                }
            }

            let axisValue = pac.direction.isHorizontal ? pac.position.x : pac.position.y
            let movingPositive = pac.direction.dx + pac.direction.dy > 0
            let nextCenter = nextTileCenter(from: axisValue, movingPositive: movingPositive)
            let distance = abs(nextCenter - axisValue)
            guard distance > 1e-9 else { break }

            let travel = min(remaining, distance)
            pac.position.x += Double(pac.direction.dx) * travel
            pac.position.y += Double(pac.direction.dy) * travel
            remaining -= travel

            if travel >= distance - 1e-9 {
                if pac.direction.isHorizontal {
                    pac.position.x = nextCenter
                } else {
                    pac.position.y = nextCenter
                }
                wrapAndSnapToCenter(&pac.position)
                eatPelletAtPacPosition()

                if phase != .playing || pellets.isEmpty {
                    return
                }
            } else {
                break
            }
        }
    }

    private func canPacMove(from tile: GridPoint, direction: Direction) -> Bool {
        let target = maze.neighbor(of: tile, in: direction)
        return maze.isWalkable(target, allowDoor: false)
    }

    private func eatPelletAtPacPosition() {
        let tile = maze.gridPoint(for: pac.position).wrapped(columns: Maze.columns)
        guard pellets.contains(tile) else { return }
        let mazeTile = maze.tile(at: tile)
        guard mazeTile.isPellet else { return }

        pellets.remove(tile)
        dotsEatenThisLevel += 1

        if mazeTile == .powerPellet {
            addScore(50)
            frightenedRemaining = frightenedDuration
            ghostCombo = 0
            for index in ghosts.indices where ghosts[index].state == .roam {
                ghosts[index].forceReverse = true
            }
            events.append(.powerPellet)
        } else {
            addScore(10)
            events.append(.chomp)
        }

        maybeSpawnFruit()
    }

    // MARK: - Ghost movement

    private func updateGhosts(_ deltaTime: Double) {
        for index in ghosts.indices {
            updateGhost(at: index, deltaTime: deltaTime)
        }
    }

    private func updateGhost(at index: Int, deltaTime: Double) {
        var ghost = ghosts[index]

        switch ghost.state {
        case .house:
            ghost.releaseDelay -= deltaTime
            if ghost.releaseDelay <= 0 {
                ghost.state = .leaving
                ghost.position = ghost.homePosition
                ghost.direction = .up
                ghost.forceReverse = false
            } else {
                let bob = sin(elapsed * 4.2 + Double(ghost.kind.rawValue) * 1.7) * 0.075
                ghost.position = Vec2(x: ghost.homePosition.x, y: ghost.homePosition.y + bob)
            }

        case .leaving:
            updateLeavingGhost(&ghost, deltaTime: deltaTime)

        case .roam:
            if ghost.forceReverse {
                ghost.direction = ghost.direction.opposite
                ghost.forceReverse = false
            }
            advanceGhost(&ghost, deltaTime: deltaTime, allowDoor: false)

        case .eyes:
            advanceGhost(&ghost, deltaTime: deltaTime, allowDoor: true)
        }

        ghosts[index] = ghost
    }

    private func updateLeavingGhost(_ ghost: inout Ghost, deltaTime: Double) {
        let speed = 4.4
        let doorX = 13.5
        let corridorY = 14.5
        let exitY = 11.5

        if abs(ghost.position.x - doorX) > 0.0001 {
            let direction: Double = ghost.position.x < doorX ? 1 : -1
            ghost.position.x = min(max(ghost.position.x + direction * speed * deltaTime, min(doorX, ghost.position.x)), max(doorX, ghost.position.x))
            ghost.direction = direction > 0 ? .right : .left
        } else if ghost.position.y > corridorY + 0.0001 {
            ghost.position.y = max(corridorY, ghost.position.y - speed * deltaTime)
            ghost.direction = .up
        } else if ghost.position.y > exitY + 0.0001 {
            ghost.position.y = max(exitY, ghost.position.y - speed * deltaTime)
            ghost.direction = .up
        } else {
            ghost.position = Vec2(x: doorX, y: exitY)
            ghost.state = .roam
            ghost.direction = .left
        }
    }

    private func advanceGhost(_ ghost: inout Ghost, deltaTime: Double, allowDoor: Bool) {
        var speed: Double
        if ghost.state == .eyes {
            speed = 13.0
        } else if frightenedRemaining > 0 {
            speed = ghostSpeed * 0.61
        } else {
            speed = ghostSpeed
        }

        let column = Int(floor(ghost.position.x))
        let row = Int(floor(ghost.position.y))
        if maze.isTunnel(column: column, row: row) {
            speed *= 0.55
        }

        var remaining = speed * deltaTime
        var iterations = 0

        while remaining > 1e-9, iterations < 12 {
            iterations += 1

            if isAtTileCenter(ghost.position) {
                wrapAndSnapToCenter(&ghost.position)
                var tile = maze.gridPoint(for: ghost.position)
                tile = tile.wrapped(columns: Maze.columns)

                if ghost.state == .eyes, tile == Maze.ghostHouseReturnTile {
                    ghost.state = .house
                    ghost.position = Maze.ghostHouseCenter
                    ghost.homePosition = Maze.ghostHouseCenter
                    ghost.releaseDelay = 1.0
                    ghost.direction = .up
                    ghost.forceReverse = false
                    return
                }

                let available = Direction.decisionOrder.filter { direction in
                    let target = maze.neighbor(of: tile, in: direction)
                    return maze.isWalkable(target, allowDoor: allowDoor)
                }

                var options = available.filter { $0 != ghost.direction.opposite }
                if options.isEmpty {
                    options = available
                }

                if options.isEmpty {
                    return
                }

                ghost.direction = chooseGhostDirection(ghost: ghost, options: options)
            }

            let axisValue = ghost.direction.isHorizontal ? ghost.position.x : ghost.position.y
            let movingPositive = ghost.direction.dx + ghost.direction.dy > 0
            let nextCenter = nextTileCenter(from: axisValue, movingPositive: movingPositive)
            let distance = abs(nextCenter - axisValue)
            guard distance > 1e-9 else { break }

            let travel = min(remaining, distance)
            ghost.position.x += Double(ghost.direction.dx) * travel
            ghost.position.y += Double(ghost.direction.dy) * travel
            remaining -= travel

            if travel >= distance - 1e-9 {
                if ghost.direction.isHorizontal {
                    ghost.position.x = nextCenter
                } else {
                    ghost.position.y = nextCenter
                }
                wrapAndSnapToCenter(&ghost.position)
            } else {
                break
            }
        }
    }

    private func chooseGhostDirection(ghost: Ghost, options: [Direction]) -> Direction {
        guard let first = options.first else { return ghost.direction.opposite }

        let tile = maze.gridPoint(for: ghost.position).wrapped(columns: Maze.columns)

        if ghost.state == .eyes {
            var best = first
            var bestDistance = Int.max
            for direction in options {
                let neighbor = maze.neighbor(of: tile, in: direction)
                let distance = maze.houseDistance(at: neighbor)
                if distance < bestDistance {
                    bestDistance = distance
                    best = direction
                }
            }
            return best
        }

        if frightenedRemaining > 0 {
            return options[rng.index(upperBound: options.count)]
        }

        let target = ghostTarget(for: ghost.kind)
        var best = first
        var bestDistance = Double.greatestFiniteMagnitude
        for direction in options {
            let neighbor = maze.neighbor(of: tile, in: direction)
            let distance = neighbor.squaredDistance(to: target)
            if distance < bestDistance {
                bestDistance = distance
                best = direction
            }
        }
        return best
    }

    private func ghostTarget(for kind: GhostKind) -> Vec2 {
        if ghostMode == .scatter {
            switch kind {
            case .blinky: return Vec2(x: 26, y: -3)
            case .pinky: return Vec2(x: 1, y: -3)
            case .inky: return Vec2(x: 27, y: 32)
            case .clyde: return Vec2(x: 0, y: 32)
            }
        }

        switch kind {
        case .blinky:
            return pac.position

        case .pinky:
            var target = pac.position + pac.direction.vector * 4
            // Preserve the original game's famous "Pinky points up" overflow.
            if pac.direction == .up {
                target.x -= 4
            }
            return target

        case .inky:
            let pivot = pac.position + pac.direction.vector * 2
            let blinky = ghosts.first { $0.kind == .blinky }?.position ?? Maze.blinkyStart
            return pivot * 2 - blinky

        case .clyde:
            if ghostPosition(for: .clyde).distanceSquared(to: pac.position) > 8 * 8 {
                return pac.position
            }
            return Vec2(x: 0, y: 32)
        }
    }

    private func ghostPosition(for kind: GhostKind) -> Vec2 {
        ghosts.first { $0.kind == kind }?.position ?? .zero
    }

    private func updateGhostMode(_ deltaTime: Double) {
        guard modeTimer.isFinite else { return }
        modeTimer -= deltaTime
        guard modeTimer <= 0 else { return }

        modeStage = min(modeStage + 1, Self.modeSchedule.count - 1)
        let stage = Self.modeSchedule[modeStage]
        ghostMode = stage.mode
        modeTimer = stage.duration

        for index in ghosts.indices where ghosts[index].state == .roam {
            ghosts[index].forceReverse = true
        }
    }

    // MARK: - Collisions and scoring

    private func resolveCollisions() {
        for index in ghosts.indices {
            let ghost = ghosts[index]
            guard ghost.state == .roam else { continue }
            let collisionRadius = 0.68
            guard pac.position.distanceSquared(to: ghost.position) < collisionRadius * collisionRadius else {
                continue
            }

            if frightenedRemaining > 0 {
                eatGhost(at: index)
            } else {
                beginDeath()
                return
            }
        }
    }

    private func eatGhost(at index: Int) {
        guard frightenedRemaining > 0 else { return }
        let points = 200 << min(ghostCombo, 3)
        ghostCombo += 1
        addScore(points)
        ghosts[index].state = .eyes
        ghosts[index].forceReverse = false
        popups.append(ScorePopup(position: ghosts[index].position, text: "\(points)", remaining: 1.2, duration: 1.2))
        events.append(.ghostEaten(combo: min(ghostCombo - 1, 3)))
        freezeRemaining = 0.5
    }

    private func addScore(_ points: Int) {
        score += points
        if score > highScore {
            highScore = score
        }
        if !extraLifeAwarded, score >= 10_000 {
            extraLifeAwarded = true
            lives += 1
            events.append(.extraLife)
        }
    }

    private func beginDeath() {
        phase = .dying
        deathElapsed = 0
        deathFraction = 0
        frightenedRemaining = 0
        ghostCombo = 0
        pac.desiredDirection = nil
        directionBufferRemaining = 0
        activeFruit = nil
        events.append(.pacDeath)
    }

    private func finishDeath() {
        deathFraction = 1
        lives -= 1
        if lives <= 0 {
            lives = 0
            phase = .gameOver
            isPaused = false
            events.append(.gameOver)
        } else {
            resetActors()
            phase = .ready
            readyRemaining = 1.75
            deathElapsed = 0
            deathFraction = 0
        }
    }

    private func beginLevelComplete() {
        guard phase == .playing else { return }
        phase = .levelComplete
        levelClearElapsed = 0
        levelClearFraction = 0
        activeFruit = nil
        frightenedRemaining = 0
        pac.desiredDirection = nil
        events.append(.levelComplete)
    }

    private func advanceLevel() {
        level += 1
        pellets = maze.initialPellets
        dotsEatenThisLevel = 0
        nextFruitThresholdIndex = 0
        activeFruit = nil
        popups.removeAll()
        resetActors()
        phase = .ready
        readyRemaining = 2.0
        levelClearElapsed = 0
        levelClearFraction = 0
    }

    // MARK: - Fruit

    private func maybeSpawnFruit() {
        while nextFruitThresholdIndex < fruitThresholds.count,
              dotsEatenThisLevel >= fruitThresholds[nextFruitThresholdIndex] {
            activeFruit = ActiveFruit(
                kind: FruitKind.forLevel(level),
                position: Maze.fruitPosition,
                remaining: 9.5
            )
            nextFruitThresholdIndex += 1
        }
    }

    private func updateFruit(_ deltaTime: Double) {
        guard var fruit = activeFruit else { return }
        fruit.remaining -= deltaTime
        activeFruit = fruit.remaining > 0 ? fruit : nil
    }

    private func collectFruitIfTouching() {
        guard let fruit = activeFruit else { return }
        let radius = 0.78
        guard pac.position.distanceSquared(to: fruit.position) < radius * radius else { return }

        addScore(fruit.kind.points)
        popups.append(ScorePopup(position: fruit.position, text: "\(fruit.kind.points)", remaining: 1.3, duration: 1.3))
        events.append(.fruitEaten(fruit.kind))
        activeFruit = nil
    }

    // MARK: - Helpers

    private func resetActors() {
        pac = PacManState(position: Maze.pacmanStart, direction: .left, desiredDirection: nil)
        directionBufferRemaining = 0
        frightenedRemaining = 0
        ghostCombo = 0
        freezeRemaining = 0
        ghostMode = .scatter
        modeStage = 0
        modeTimer = Self.modeSchedule[0].duration

        let releaseScale = max(0.45, 1.0 - Double(level - 1) * 0.055)

        ghosts = [
            Ghost(
                kind: .blinky,
                position: Maze.blinkyStart,
                direction: .left,
                state: .roam,
                homePosition: Maze.blinkyStart,
                releaseDelay: 0,
                forceReverse: false
            ),
            Ghost(
                kind: .pinky,
                position: Maze.pinkyStart,
                direction: .up,
                state: .house,
                homePosition: Maze.pinkyStart,
                releaseDelay: 0.85 * releaseScale,
                forceReverse: false
            ),
            Ghost(
                kind: .inky,
                position: Maze.inkyStart,
                direction: .up,
                state: .house,
                homePosition: Maze.inkyStart,
                releaseDelay: 4.4 * releaseScale,
                forceReverse: false
            ),
            Ghost(
                kind: .clyde,
                position: Maze.clydeStart,
                direction: .up,
                state: .house,
                homePosition: Maze.clydeStart,
                releaseDelay: 8.2 * releaseScale,
                forceReverse: false
            )
        ]
    }

    private func updatePopups(_ deltaTime: Double) {
        guard !popups.isEmpty else { return }
        for index in popups.indices {
            popups[index].remaining -= deltaTime
        }
        popups.removeAll { $0.remaining <= 0 }
    }

    private func isAtTileCenter(_ position: Vec2) -> Bool {
        let centerX = floor(position.x) + 0.5
        let centerY = floor(position.y) + 0.5
        return abs(position.x - centerX) < 1e-6 && abs(position.y - centerY) < 1e-6
    }

    private func wrapAndSnapToCenter(_ position: inout Vec2) {
        if position.x < 0 {
            position.x += Double(Maze.columns)
        } else if position.x >= Double(Maze.columns) {
            position.x -= Double(Maze.columns)
        }
        position.x = floor(position.x) + 0.5
        position.y = floor(position.y) + 0.5
    }

    private func nextTileCenter(from value: Double, movingPositive: Bool) -> Double {
        if movingPositive {
            return floor(value + 0.5) + 0.5
        } else {
            return ceil(value - 0.5) - 0.5
        }
    }
}
