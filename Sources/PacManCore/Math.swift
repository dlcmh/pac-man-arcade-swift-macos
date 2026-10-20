import Foundation

/// A position in continuous tile space. Tile (0, 0) spans x/y from 0 to 1,
/// so every tile center is at (column + 0.5, row + 0.5).
public struct Vec2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(x: 0, y: 0)

    public var lengthSquared: Double {
        x * x + y * y
    }

    public func distanceSquared(to other: Vec2) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }

    public func distance(to other: Vec2) -> Double {
        sqrt(distanceSquared(to: other))
    }

    public static func + (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: Vec2, rhs: Double) -> Vec2 {
        Vec2(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

public struct GridPoint: Hashable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public func wrapped(columns: Int) -> GridPoint {
        var wrappedX = x % columns
        if wrappedX < 0 { wrappedX += columns }
        return GridPoint(x: wrappedX, y: y)
    }

    public func squaredDistance(to other: Vec2) -> Double {
        let dx = Double(x) + 0.5 - other.x
        let dy = Double(y) + 0.5 - other.y
        return dx * dx + dy * dy
    }

    public var center: Vec2 {
        Vec2(x: Double(x) + 0.5, y: Double(y) + 0.5)
    }
}

public enum Direction: Int, CaseIterable, Sendable {
    case up
    case left
    case down
    case right

    public var dx: Int {
        switch self {
        case .left: return -1
        case .right: return 1
        case .up, .down: return 0
        }
    }

    public var dy: Int {
        switch self {
        case .up: return -1
        case .down: return 1
        case .left, .right: return 0
        }
    }

    public var vector: Vec2 {
        Vec2(x: Double(dx), y: Double(dy))
    }

    public var opposite: Direction {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }

    /// Angle in screen space (y grows downwards).
    public var angle: Double {
        switch self {
        case .right: return 0
        case .down: return .pi * 0.5
        case .left: return .pi
        case .up: return -.pi * 0.5
        }
    }

    public var isHorizontal: Bool {
        self == .left || self == .right
    }

    /// The original game resolves equally-good ghost choices in this order.
    public static let decisionOrder: [Direction] = [.up, .left, .down, .right]
}

public func isApproximatelyEqual(_ a: Double, _ b: Double, epsilon: Double = 1e-7) -> Bool {
    abs(a - b) <= epsilon
}

/// A tiny deterministic random number generator so ghost decisions are
/// consistent and testable without pulling in system randomness.
public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func index(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }

    public mutating func unitDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
