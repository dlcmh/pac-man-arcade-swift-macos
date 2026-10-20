import Foundation
import PacManCore

var checks = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() {
        print("FAIL: \(message)")
        exit(1)
    }
}

func step(_ game: PacManGame, seconds: Double) {
    var elapsed = 0.0
    while elapsed < seconds {
        game.update(dt: 1.0 / 60.0)
        elapsed += 1.0 / 60.0
    }
}

func startPlaying(_ game: PacManGame) {
    game.requestStart()
    step(game, seconds: 2.1)
    check(game.phase == .playing, "game reaches playing phase")
}

// Maze integrity.
let maze = Maze()
check(Maze.rows == 31 && Maze.columns == 28, "maze dimensions")
check(Maze.layout.allSatisfy { $0.count == 28 }, "all maze rows have 28 columns")
check(maze.dotCount == 240, "240 regular dots")
check(maze.powerPelletCount == 4, "4 power pellets")
check(maze.initialPellets.count == 244, "244 total pellets")

// Every pellet must be reachable.
var reachable: Set<GridPoint> = [GridPoint(x: 13, y: 23)]
var queue = [GridPoint(x: 13, y: 23)]
var head = 0
while head < queue.count {
    let current = queue[head]
    head += 1
    for direction in Direction.allCases {
        let next = maze.neighbor(of: current, in: direction)
        guard (0..<Maze.rows).contains(next.y), maze.isWalkable(next, allowDoor: false) else {
            continue
        }
        if reachable.insert(next).inserted {
            queue.append(next)
        }
    }
}
check(maze.initialPellets.isSubset(of: reachable), "all pellets are reachable")

// Tunnel wrap and the eyes' path back into the house.
check(maze.isWalkable(column: -1, row: Maze.tunnelRow, allowDoor: false), "left tunnel is open")
check(maze.isWalkable(column: 28, row: Maze.tunnelRow, allowDoor: false), "right tunnel is open")
check(maze.houseDistance(at: GridPoint(x: 1, y: 1)) != .max, "ghost eyes can path home")
check(maze.houseDistance(at: Maze.ghostHouseReturnTile) == 0, "house return tile has zero distance")

// Attract mode and start.
let game = PacManGame(highScore: 1_234)
check(game.phase == .attract, "starts in attract mode")
check(game.remainingPellets == 244, "starts with all pellets")
check(game.lives == 3, "starts with three lives")
check(game.highScore == 1_234, "loads the supplied high score")

game.requestStart()
check(game.phase == .ready, "inserting a credit enters READY")
check(game.level == 1 && game.score == 0, "new game resets level and score")
step(game, seconds: 2.1)
check(game.phase == .playing, "READY reaches PLAYING")

// Moving left from the start must eat dots and raise both scores.
step(game, seconds: 0.25)
check(game.remainingPellets < 244, "Pac-Man eats dots")
check(game.score > 0, "eating dots increases score")
check(game.highScore >= game.score, "high score never falls below score")

// Pac-Man stops at the wall to the left of the start corridor.
step(game, seconds: 1.0)
let stoppedX = game.pac.position.x
check(abs(stoppedX - 6.5) < 0.001, "Pac-Man stops at the wall at x=6.5")
step(game, seconds: 0.4)
check(abs(game.pac.position.x - stoppedX) < 0.001, "Pac-Man stays stopped against the wall")

// Buffered turn: at the wall, up is open.
game.setDirection(.up)
step(game, seconds: 0.15)
check(game.pac.position.y < 23.5, "Pac-Man turns up after buffered input")

// Pause freezes the simulation.
let pausedPosition = game.pac.position
game.togglePause()
check(game.isPaused, "pause flag set")
step(game, seconds: 0.5)
check(game.pac.position == pausedPosition, "pause freezes Pac-Man")
game.togglePause()
check(!game.isPaused, "resume clears pause flag")

// Ghost house release.
let releaseGame = PacManGame()
startPlaying(releaseGame)
step(releaseGame, seconds: 6.0)
check(
    releaseGame.ghosts.contains { $0.kind == .pinky && $0.state != .house },
    "Pinky leaves the house")
check(
    releaseGame.ghosts.contains { $0.kind == .inky && $0.state != .house }, "Inky leaves the house")

// Soak test: random turns for one simulated minute. This catches degenerate
// movement loops, non-finite positions, and state-machine crashes.
let soak = PacManGame()
startPlaying(soak)
var rng = SplitMix64(seed: 0xA11CE_5EED)
var elapsed = 0.0
while elapsed < 60.0 {
    if Int(elapsed * 60) % 25 == 0 {
        let directions: [Direction] = [.up, .left, .down, .right]
        soak.setDirection(directions[rng.index(upperBound: directions.count)])
    }
    soak.update(dt: 1.0 / 60.0)
    elapsed += 1.0 / 60.0
    check(
        soak.pac.position.x.isFinite && soak.pac.position.y.isFinite,
        "Pac-Man position remains finite")
    check(
        soak.pac.position.x > -1.5 && soak.pac.position.x < 29.5,
        "Pac-Man stays within the tunnel bounds")
    check(
        soak.pac.position.y >= 0 && soak.pac.position.y < 31, "Pac-Man stays within the maze rows")
    let pacTile = soak.maze.gridPoint(for: soak.pac.position)
    check(soak.maze.isWalkable(pacTile, allowDoor: false), "Pac-Man remains on a walkable tile")
    check(
        soak.ghosts.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite },
        "ghost positions remain finite")
    check(soak.remainingPellets >= 0, "pellet count never becomes negative")
}
check(soak.phase != .attract, "soak simulation left attract mode")

print("PASS: \(checks) checks")

// Drive Pac-Man toward a power pellet using only the public input API.

func firstDirection(from start: GridPoint, to target: (GridPoint) -> Bool) -> Direction? {
    var queue: [(GridPoint, Direction?)] = [(start, nil)]
    var visited: Set<GridPoint> = [start]
    var head = 0
    while head < queue.count {
        let (point, first) = queue[head]
        head += 1
        if target(point) {
            return first
        }
        for direction in Direction.decisionOrder {
            let next = maze.neighbor(of: point, in: direction)
            guard (0..<Maze.rows).contains(next.y), maze.isWalkable(next, allowDoor: false) else {
                continue
            }
            if visited.insert(next).inserted {
                queue.append((next, first ?? direction))
            }
        }
    }
    return nil
}

var reachedPowerPellet = false
for _ in 0..<4 where !reachedPowerPellet {
    let run = PacManGame()
    startPlaying(run)
    var powerSteps = 0
    while powerSteps < 60 * 30 {
        if run.phase == .dying || run.phase == .gameOver {
            break
        }
        let currentTile = run.maze.gridPoint(for: run.pac.position).wrapped(columns: Maze.columns)
        let canContinue = run.maze.isWalkable(
            run.maze.neighbor(of: currentTile, in: run.pac.direction), allowDoor: false)
        let planningTile =
            canContinue ? run.maze.neighbor(of: currentTile, in: run.pac.direction) : currentTile
        let targetDirection = firstDirection(from: planningTile) { point in
            point.y > 20 && run.pellets.contains(point) && run.maze.tile(at: point) == .powerPellet
        }
        if let targetDirection, targetDirection != run.pac.direction.opposite {
            run.setDirection(targetDirection)
        }
        run.update(dt: 1.0 / 60.0)
        powerSteps += 1
        if run.frightenedRemaining > 0 {
            reachedPowerPellet = true

            break
        }
    }
}
check(reachedPowerPellet, "autopilot reaches a power pellet and triggers frightened mode")

// A ghost should eventually catch an idle Pac-Man, and a life should be lost.
let deathGame = PacManGame()
startPlaying(deathGame)
var deathWait = 0
while deathGame.phase == .playing, deathWait < 60 * 60 {
    deathGame.update(dt: 1.0 / 60.0)
    deathWait += 1
}
check(deathGame.phase == .dying, "a ghost can catch Pac-Man")
step(deathGame, seconds: 2.0)
check(deathGame.lives == 2, "a lost life is deducted after the death animation")
check(deathGame.phase == .ready || deathGame.phase == .playing, "play resumes after a death")

// Keep letting the ghosts catch the idle player until the game ends.
var gameOverWait = 0
while deathGame.phase != .gameOver, gameOverWait < 60 * 300 {
    deathGame.update(dt: 1.0 / 60.0)
    gameOverWait += 1
}
check(deathGame.phase == .gameOver, "the third death reaches game over")
check(deathGame.lives == 0, "game over leaves no lives")
deathGame.requestStart()
check(deathGame.phase == .ready && deathGame.lives == 3, "game over can be restarted")

print("PASS: \(checks) checks (including power-pellet autopilot, ghost collision, and game over)")
