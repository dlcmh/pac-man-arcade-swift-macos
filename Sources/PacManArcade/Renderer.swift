import Foundation
import MetalKit
import PacManCore

final class Renderer {
    static let designWidth: CGFloat = 896
    static let designHeight: CGFloat = 1092
    static let tileSize: CGFloat = 28
    static let mazeOrigin = CGPoint(x: 56, y: 112)

    private struct Uniforms {
        var viewportSize: SIMD2<Float>
        var scale: SIMD2<Float>
        var offset: SIMD2<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let canvas = Canvas(reservedVertices: 90_000)
    private lazy var font = PixelFont(canvas: canvas)
    private var vertexBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let inFlightSemaphore = DispatchSemaphore(value: 3)

    var isMuted = false

    init(view: MTKView) throws {
        guard let device = view.device else {
            throw RendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.couldNotCreateCommandQueue
        }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: MetalShaderSource.source, options: nil)
        } catch {
            print("Metal shader compilation failed:\n\(error)")
            throw RendererError.shaderCompilationFailed
        }
        guard let vertexFunction = library.makeFunction(name: "vertex_main"),
              let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            throw RendererError.shaderCompilationFailed
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Arcade 2D Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            throw RendererError.pipelineCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipelineState = pipeline

        let initialCapacity = 100_000 * Canvas.floatsPerVertex * MemoryLayout<Float>.stride
        for _ in 0..<3 {
            guard let buffer = device.makeBuffer(length: initialCapacity, options: .storageModeShared) else {
                throw RendererError.couldNotCreateVertexBuffer
            }
            vertexBuffers.append(buffer)
        }
    }

    func render(game: PacManGame, in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.006, green: 0.008, blue: 0.020, alpha: 1.0)

        canvas.reset()
        drawBackdrop()
        let wallFlash = game.phase == .levelComplete && Int(game.elapsed * 12) % 2 == 0
        drawMaze(game: game, flash: wallFlash)
        drawPellets(game: game)
        drawActiveFruit(game: game)
        drawActors(game: game)
        drawScorePopups(game: game)
        drawHUD(game: game)
        drawOverlays(game: game)
        drawScanlines()

        let vertexCount = canvas.vertexCount
        guard vertexCount > 0 else { return }

        inFlightSemaphore.wait()

        let byteCount = canvas.vertices.count * MemoryLayout<Float>.stride
        if byteCount > vertexBuffers[frameIndex].length {
            let newLength = max(byteCount, vertexBuffers[frameIndex].length * 2)
            guard let largerBuffer = device.makeBuffer(length: newLength, options: .storageModeShared) else {
                inFlightSemaphore.signal()
                return
            }
            vertexBuffers[frameIndex] = largerBuffer
        }
        let buffer = vertexBuffers[frameIndex]
        frameIndex = (frameIndex + 1) % vertexBuffers.count

        canvas.vertices.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                buffer.contents().copyMemory(from: baseAddress, byteCount: byteCount)
            }
        }

        let drawableSize = view.drawableSize
        let scale = min(Float(drawableSize.width) / Float(Self.designWidth),
                        Float(drawableSize.height) / Float(Self.designHeight))
        let offsetX = (Float(drawableSize.width) - Float(Self.designWidth) * scale) * 0.5
        let offsetY = (Float(drawableSize.height) - Float(Self.designHeight) * scale) * 0.5

        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
            scale: SIMD2<Float>(scale, scale),
            offset: SIMD2<Float>(offsetX, offsetY)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            inFlightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [inFlightSemaphore] _ in
            inFlightSemaphore.signal()
        }

        encoder.label = "Arcade Frame"
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertexCount)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Coordinate helpers

    private func screenPoint(_ position: Vec2) -> CGPoint {
        CGPoint(x: Self.mazeOrigin.x + CGFloat(position.x) * Self.tileSize,
                y: Self.mazeOrigin.y + CGFloat(position.y) * Self.tileSize)
    }

    private func tileScreenPoint(column: Int, row: Int) -> CGPoint {
        CGPoint(x: Self.mazeOrigin.x + (CGFloat(column) + 0.5) * Self.tileSize,
                y: Self.mazeOrigin.y + (CGFloat(row) + 0.5) * Self.tileSize)
    }

    private var playfieldRect: CGRect {
        CGRect(x: Self.mazeOrigin.x,
               y: Self.mazeOrigin.y,
               width: CGFloat(Maze.columns) * Self.tileSize,
               height: CGFloat(Maze.rows) * Self.tileSize)
    }

    // MARK: - Background and maze

    private func drawBackdrop() {
        canvas.addRect(x: 0, y: 0, width: Self.designWidth, height: Self.designHeight, color: Palette.background)
        canvas.addRect(x: playfieldRect.minX,
                       y: playfieldRect.minY,
                       width: playfieldRect.width,
                       height: playfieldRect.height,
                       color: Palette.playfield)

        let centerGlow = CGPoint(x: Self.designWidth * 0.5,
                                 y: Self.mazeOrigin.y + CGFloat(Maze.rows) * 0.5 * Self.tileSize)
        canvas.addCircle(center: centerGlow, radius: 250, color: Color(0.05, 0.10, 0.36, 0.035), segments: 42)
        canvas.addCircle(center: centerGlow, radius: 160, color: Color(0.08, 0.15, 0.48, 0.035), segments: 36)

        // A restrained cabinet frame around the playfield.
        let frameInset: CGFloat = 9
        let frame = playfieldRect.insetBy(dx: -frameInset, dy: -frameInset)
        strokeRect(frame, color: Color(0.16, 0.24, 0.70, 0.28), thickness: 1)
        strokeRect(frame.insetBy(dx: 4, dy: 4), color: Color(0.30, 0.42, 1.0, 0.12), thickness: 1)

        // Corner brackets give the panel a subtle physical-arcade feel.
        let bracketLength: CGFloat = 26
        let bracketInset: CGFloat = 21
        let corners = [
            (CGPoint(x: frame.minX + bracketInset, y: frame.minY + bracketInset), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)),
            (CGPoint(x: frame.maxX - bracketInset, y: frame.minY + bracketInset), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1)),
            (CGPoint(x: frame.minX + bracketInset, y: frame.maxY - bracketInset), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: -1)),
            (CGPoint(x: frame.maxX - bracketInset, y: frame.maxY - bracketInset), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1))
        ]
        for (origin, horizontal, vertical) in corners {
            let hEnd = CGPoint(x: origin.x + horizontal.x * bracketLength, y: origin.y + horizontal.y * bracketLength)
            let vEnd = CGPoint(x: origin.x + vertical.x * bracketLength, y: origin.y + vertical.y * bracketLength)
            canvas.addLine(from: origin, to: hEnd, thickness: 2, color: Color(0.40, 0.54, 1.0, 0.45), rounded: false)
            canvas.addLine(from: origin, to: vEnd, thickness: 2, color: Color(0.40, 0.54, 1.0, 0.45), rounded: false)
        }

        // HUD divider.
        canvas.addRect(x: 48, y: 94, width: Self.designWidth - 96, height: 1, color: Color(0.25, 0.35, 0.85, 0.22))
    }

    private func drawMaze(game: PacManGame, flash: Bool) {
        let wallFillColor: Color = flash
            ? Color(0.16, 0.22, 0.58, 1)
            : Palette.wallFill
        let wallCoreColor: Color = flash ? Color(0.9, 0.95, 1.0, 1) : Palette.wall
        let wallGlowColor: Color = flash
            ? Color(0.6, 0.78, 1.0, 0.18)
            : Palette.wallGlow
        let wallMidColor: Color = flash
            ? Color(0.9, 0.95, 1.0, 0.4)
            : Palette.wallMidGlow

        for row in 0..<Maze.rows {
            for column in 0..<Maze.columns {
                guard game.maze.grid[row][column].isWall else { continue }
                canvas.addRect(
                    x: Self.mazeOrigin.x + CGFloat(column) * Self.tileSize,
                    y: Self.mazeOrigin.y + CGFloat(row) * Self.tileSize,
                    width: Self.tileSize,
                    height: Self.tileSize,
                    color: wallFillColor
                )
            }
        }

        let top = Self.mazeOrigin.y
        let left = Self.mazeOrigin.x
        let tile = Self.tileSize

        func isWall(_ column: Int, _ row: Int) -> Bool {
            guard column >= 0, column < Maze.columns, row >= 0, row < Maze.rows else { return false }
            return game.maze.grid[row][column].isWall
        }

        func drawEdge(_ start: CGPoint, _ end: CGPoint) {
            canvas.addLine(from: start, to: end, thickness: 7.2, color: wallGlowColor, rounded: false)
            canvas.addLine(from: start, to: end, thickness: 3.5, color: wallMidColor, rounded: false)
            canvas.addLine(from: start, to: end, thickness: 1.45, color: wallCoreColor, rounded: false)
        }

        for row in 0..<Maze.rows {
            for column in 0..<Maze.columns {
                guard game.maze.grid[row][column].isWall else { continue }
                let x = left + CGFloat(column) * tile
                let y = top + CGFloat(row) * tile

                if !isWall(column, row - 1) {
                    drawEdge(CGPoint(x: x, y: y), CGPoint(x: x + tile, y: y))
                }
                if !isWall(column, row + 1) {
                    drawEdge(CGPoint(x: x, y: y + tile), CGPoint(x: x + tile, y: y + tile))
                }
                if !isWall(column - 1, row) {
                    drawEdge(CGPoint(x: x, y: y), CGPoint(x: x, y: y + tile))
                }
                if !isWall(column + 1, row) {
                    drawEdge(CGPoint(x: x + tile, y: y), CGPoint(x: x + tile, y: y + tile))
                }
            }
        }

        // Ghost-house door.
        let doorY = top + 12.5 * tile
        let doorStart = CGPoint(x: left + 13 * tile, y: doorY)
        let doorEnd = CGPoint(x: left + 15 * tile, y: doorY)
        canvas.addLine(from: doorStart, to: doorEnd, thickness: 9, color: Color(1.0, 0.45, 0.8, 0.10), rounded: false)
        canvas.addLine(from: doorStart, to: doorEnd, thickness: 3.0, color: Palette.door, rounded: false)
    }

    private func drawPellets(game: PacManGame) {
        for point in game.pellets {
            let mazeTile = game.maze.tile(at: point)
            let center = tileScreenPoint(column: point.x, row: point.y)
            switch mazeTile {
            case .dot:
                canvas.addCircle(center: center, radius: 4.0, color: Palette.pelletGlow, segments: 10)
                canvas.addCircle(center: center, radius: 2.15, color: Palette.pellet, segments: 10)
            case .powerPellet:
                let pulse = 0.82 + 0.18 * abs(sin(game.elapsed * 5.0 + Double(point.x) * 0.7))
                let radius = 6.4 * pulse
                canvas.addCircle(center: center, radius: radius * 2.25, color: Palette.pelletGlow, segments: 18)
                canvas.addCircle(center: center, radius: radius + 2.0, color: Color(1.0, 0.75, 0.45, 0.25), segments: 18)
                canvas.addCircle(center: center, radius: radius, color: Palette.pellet, segments: 18)
                canvas.addCircle(center: CGPoint(x: center.x - radius * 0.25, y: center.y - radius * 0.3),
                                 radius: radius * 0.34,
                                 color: Color(1, 0.98, 0.88, 0.55),
                                 segments: 12)
            default:
                break
            }
        }
    }

    // MARK: - Actors

    private func drawActors(game: PacManGame) {
        guard game.phase != .gameOver else { return }

        if game.phase != .dying {
            for ghost in game.ghosts {
                drawGhost(ghost: ghost, game: game)
            }
        }

        drawPacman(game: game)
    }

    private func drawPacman(game: PacManGame) {
        let center = screenPoint(game.pac.position)
        let radius: CGFloat = 12.3
        let directionAngle = CGFloat(game.pac.direction.angle)

        if game.phase == .dying {
            let progress = CGFloat(game.deathFraction)
            guard progress < 0.995 else { return }
            let mouth = 0.18 + progress * (.pi - 0.18)
            let spin = progress * .pi * 1.15
            let bodyRadius = radius * (1.0 - progress * 0.32)
            var bodyColor = Palette.pacman
            bodyColor.w = Float(1.0 - progress * 0.55)
            var glowColor = Palette.pacmanGlow
            glowColor.w *= Float(1.0 - progress * 0.6)
            canvas.addCircle(center: center, radius: bodyRadius * 1.55, color: glowColor, segments: 24)
            canvas.addPie(center: center,
                          radius: bodyRadius,
                          startAngle: directionAngle + spin + mouth,
                          endAngle: directionAngle + spin + .pi * 2 - mouth,
                          color: bodyColor,
                          segments: 48)
            return
        }

        let mouth = CGFloat(0.10 + 0.33 * abs(sin(game.elapsed * 11.2)))
        canvas.addCircle(center: center,
                         radius: radius * 1.62,
                         color: Palette.pacmanGlow,
                         segments: 26)
        canvas.addCircle(center: center,
                         radius: radius * 1.26,
                         color: Color(1.0, 0.72, 0.04, 0.08),
                         segments: 22)
        canvas.addPie(center: center,
                      radius: radius,
                      startAngle: directionAngle + mouth,
                      endAngle: directionAngle + .pi * 2 - mouth,
                      color: Palette.pacman,
                      segments: 52)
        canvas.addCircle(center: CGPoint(x: center.x - 3.0, y: center.y - 3.2),
                         radius: 4.2,
                         color: Color(1, 0.98, 0.75, 0.12),
                         segments: 14)

        let eyeLocal = CGPoint(x: 2.2, y: -4.2)
        let cosA = cos(directionAngle)
        let sinA = sin(directionAngle)
        let eyeCenter = CGPoint(
            x: center.x + eyeLocal.x * cosA - eyeLocal.y * sinA,
            y: center.y + eyeLocal.x * sinA + eyeLocal.y * cosA
        )
        canvas.addCircle(center: eyeCenter, radius: 1.85, color: Color(0.06, 0.05, 0.03, 1), segments: 12)
        canvas.addCircle(center: CGPoint(x: eyeCenter.x - 0.45, y: eyeCenter.y - 0.5),
                         radius: 0.55,
                         color: Color(1, 1, 0.9, 0.75),
                         segments: 8)
    }

    private func drawGhost(ghost: Ghost, game: PacManGame) {
        let center = screenPoint(ghost.position)
        let frightened = game.isFrightened && ghost.state != .eyes
        let flashing = frightened && game.frightenedFlashOn
        let bodyColor: Color
        if ghost.state == .eyes {
            bodyColor = Color(0, 0, 0, 0)
        } else if frightened {
            bodyColor = flashing ? Palette.frightenedFlash : Palette.frightened
        } else {
            bodyColor = ghostColor(for: ghost.kind)
        }

        if ghost.state == .eyes {
            canvas.addCircle(center: center, radius: 18, color: Color(0.25, 0.55, 1.0, 0.05), segments: 18)
        } else {
            var glow = bodyColor
            glow.w = 0.13
            canvas.addCircle(center: center, radius: 18.5, color: glow, segments: 22)
            drawGhostBody(center: center, color: bodyColor)
            canvas.addEllipse(center: CGPoint(x: center.x - 3.5, y: center.y - 4.5),
                              radiusX: 4.2,
                              radiusY: 2.4,
                              color: Color(1, 1, 1, 0.075),
                              segments: 16)
        }

        if frightened {
            drawFrightenedFace(center: center, flashing: flashing)
        } else {
            drawGhostEyes(center: center, direction: ghost.direction, large: ghost.state == .eyes)
        }
    }

    private func drawGhostBody(center: CGPoint, color: Color) {
        let radius: CGFloat = 11.7
        let headCenterY = center.y - 1.0
        let baseY = center.y + 8.0
        let waveY = center.y + 12.2
        let notchY = center.y + 8.7

        var points: [CGPoint] = []
        points.append(CGPoint(x: center.x - radius, y: baseY))
        for index in 0...18 {
            let angle = CGFloat.pi + CGFloat(index) / 18.0 * CGFloat.pi
            points.append(CGPoint(x: center.x + cos(angle) * radius,
                                  y: headCenterY + sin(angle) * radius))
        }
        points.append(CGPoint(x: center.x + radius, y: baseY))
        points.append(CGPoint(x: center.x + radius * 0.66, y: waveY))
        points.append(CGPoint(x: center.x + radius * 0.33, y: notchY))
        points.append(CGPoint(x: center.x, y: waveY))
        points.append(CGPoint(x: center.x - radius * 0.33, y: notchY))
        points.append(CGPoint(x: center.x - radius * 0.66, y: waveY))
        points.append(CGPoint(x: center.x - radius, y: baseY))

        canvas.addPolygon(points: points, color: color)
    }

    private func drawGhostEyes(center: CGPoint, direction: Direction, large: Bool) {
        let eyeOffsetX: CGFloat = large ? 5.0 : 4.5
        let eyeOffsetY: CGFloat = large ? -2.8 : -3.3
        let eyeRadius: CGFloat = large ? 4.2 : 3.45
        let pupilRadius: CGFloat = large ? 2.2 : 1.8
        let look = CGPoint(x: CGFloat(direction.dx) * 1.55, y: CGFloat(direction.dy) * 1.55)

        for side in [-1.0, 1.0] {
            let eyeCenter = CGPoint(x: center.x + CGFloat(side) * eyeOffsetX, y: center.y + eyeOffsetY)
            canvas.addCircle(center: eyeCenter, radius: eyeRadius, color: Palette.ghostEye, segments: 18)
            let pupilCenter = CGPoint(x: eyeCenter.x + look.x, y: eyeCenter.y + look.y)
            canvas.addCircle(center: pupilCenter, radius: pupilRadius, color: Palette.ghostPupil, segments: 14)
            canvas.addCircle(center: CGPoint(x: pupilCenter.x - 0.55, y: pupilCenter.y - 0.55),
                             radius: 0.7,
                             color: Color(0.8, 0.95, 1, 0.65),
                             segments: 8)
        }
    }

    private func drawFrightenedFace(center: CGPoint, flashing: Bool) {
        let featureColor = flashing ? Palette.frightened : Palette.ghostEye
        for side in [-1.0, 1.0] {
            canvas.addCircle(center: CGPoint(x: center.x + CGFloat(side) * 4.1, y: center.y - 2.3),
                             radius: 2.3,
                             color: featureColor,
                             segments: 12)
        }
        let mouthPoints: [CGPoint] = [
            CGPoint(x: center.x - 5.4, y: center.y + 5.0),
            CGPoint(x: center.x - 3.2, y: center.y + 3.4),
            CGPoint(x: center.x - 1.0, y: center.y + 5.0),
            CGPoint(x: center.x + 1.2, y: center.y + 3.4),
            CGPoint(x: center.x + 3.4, y: center.y + 5.0),
            CGPoint(x: center.x + 5.4, y: center.y + 3.4)
        ]
        canvas.addPolyline(mouthPoints, thickness: 1.5, color: featureColor)
    }

    private func ghostColor(for kind: GhostKind) -> Color {
        switch kind {
        case .blinky: return Palette.red
        case .pinky: return Palette.pink
        case .inky: return Palette.cyan
        case .clyde: return Palette.orange
        }
    }

    private func drawScorePopups(game: PacManGame) {
        for popup in game.popups {
            let center = screenPoint(popup.position)
            var color = Palette.scoreCyan
            color.w = Float(max(0, 1 - popup.progress))
            let y = center.y - 12 - CGFloat(popup.progress) * 20
            let value = popup.text
            font.draw(value, x: center.x, y: y, pixelSize: 2.0, color: color, alignment: .center)
        }
    }

    // MARK: - Fruit

    private func drawActiveFruit(game: PacManGame) {
        guard let fruit = game.activeFruit else { return }
        let center = screenPoint(fruit.position)
        canvas.addCircle(center: center, radius: 24, color: Color(1.0, 0.55, 0.2, 0.055), segments: 20)
        drawFruit(kind: fruit.kind, center: center, scale: 1.0, alpha: 1.0)
    }

    private func drawFruit(kind: FruitKind, center: CGPoint, scale: CGFloat, alpha: Float) {
        func tinted(_ color: Color) -> Color {
            var result = color
            result.w *= alpha
            return result
        }

        let red = tinted(Color(0.96, 0.18, 0.27, 1))
        let deepRed = tinted(Color(0.73, 0.06, 0.16, 1))
        let green = tinted(Color(0.27, 0.83, 0.35, 1))
        let darkGreen = tinted(Color(0.11, 0.53, 0.28, 1))
        let orange = tinted(Color(1.0, 0.55, 0.16, 1))
        let yellow = tinted(Color(1.0, 0.82, 0.17, 1))
        let gold = tinted(Color(0.96, 0.66, 0.12, 1))
        let stem = tinted(Color(0.52, 0.30, 0.12, 1))
        let cyan = tinted(Color(0.30, 0.85, 1.0, 1))
        let shine = tinted(Color(1, 1, 0.9, 0.52))

        switch kind {
        case .cherry:
            let left = CGPoint(x: center.x - 5.5 * scale, y: center.y + 4.0 * scale)
            let right = CGPoint(x: center.x + 5.5 * scale, y: center.y + 3.0 * scale)
            canvas.addLine(from: CGPoint(x: left.x + 1, y: left.y - 4 * scale),
                           to: CGPoint(x: center.x + 2 * scale, y: center.y - 11 * scale),
                           thickness: 1.5 * scale, color: green)
            canvas.addLine(from: CGPoint(x: right.x - 1, y: right.y - 4 * scale),
                           to: CGPoint(x: center.x + 2 * scale, y: center.y - 11 * scale),
                           thickness: 1.5 * scale, color: green)
            canvas.addEllipse(center: CGPoint(x: center.x + 8 * scale, y: center.y - 10 * scale),
                              radiusX: 5 * scale, radiusY: 2.5 * scale, color: green)
            canvas.addCircle(center: left, radius: 5.5 * scale, color: deepRed)
            canvas.addCircle(center: right, radius: 5.5 * scale, color: red)
            canvas.addCircle(center: CGPoint(x: left.x - 1.8 * scale, y: left.y - 2 * scale),
                             radius: 1.4 * scale, color: shine)
            canvas.addCircle(center: CGPoint(x: right.x - 1.8 * scale, y: right.y - 2 * scale),
                             radius: 1.4 * scale, color: shine)

        case .strawberry:
            var body = [CGPoint]()
            body.append(CGPoint(x: center.x - 8 * scale, y: center.y - 2 * scale))
            body.append(CGPoint(x: center.x - 6 * scale, y: center.y + 5 * scale))
            body.append(CGPoint(x: center.x, y: center.y + 11 * scale))
            body.append(CGPoint(x: center.x + 6 * scale, y: center.y + 5 * scale))
            body.append(CGPoint(x: center.x + 8 * scale, y: center.y - 2 * scale))
            body.append(CGPoint(x: center.x + 5 * scale, y: center.y - 7 * scale))
            body.append(CGPoint(x: center.x - 5 * scale, y: center.y - 7 * scale))
            canvas.addPolygon(points: body, color: red)
            for side in [-1.0, 0.0, 1.0] {
                canvas.addEllipse(center: CGPoint(x: center.x + CGFloat(side) * 3.5 * scale, y: center.y - 7 * scale),
                                  radiusX: 4.3 * scale, radiusY: 2.1 * scale, color: green)
            }
            canvas.addLine(from: CGPoint(x: center.x, y: center.y - 8 * scale),
                           to: CGPoint(x: center.x + 2 * scale, y: center.y - 12 * scale),
                           thickness: 1.4 * scale, color: darkGreen)
            for point in [CGPoint(x: -3, y: 0), CGPoint(x: 3, y: 1), CGPoint(x: 0, y: 5), CGPoint(x: -2, y: 7), CGPoint(x: 4, y: 6)] {
                canvas.addCircle(center: CGPoint(x: center.x + point.x * scale, y: center.y + point.y * scale),
                                 radius: 0.8 * scale, color: yellow, segments: 6)
            }

        case .orange:
            canvas.addCircle(center: CGPoint(x: center.x, y: center.y + 2 * scale), radius: 8.5 * scale, color: orange)
            canvas.addEllipse(center: CGPoint(x: center.x + 5 * scale, y: center.y - 7.5 * scale),
                              radiusX: 5 * scale, radiusY: 2.4 * scale, color: green)
            canvas.addLine(from: CGPoint(x: center.x, y: center.y - 6 * scale),
                           to: CGPoint(x: center.x + 1 * scale, y: center.y - 11 * scale),
                           thickness: 1.5 * scale, color: stem)
            canvas.addCircle(center: CGPoint(x: center.x - 2.8 * scale, y: center.y - 1 * scale),
                             radius: 1.9 * scale, color: shine)

        case .apple:
            canvas.addCircle(center: CGPoint(x: center.x - 3.7 * scale, y: center.y + 1 * scale), radius: 6.3 * scale, color: red)
            canvas.addCircle(center: CGPoint(x: center.x + 3.7 * scale, y: center.y + 1 * scale), radius: 6.3 * scale, color: red)
            canvas.addLine(from: CGPoint(x: center.x, y: center.y - 5 * scale),
                           to: CGPoint(x: center.x + 1 * scale, y: center.y - 12 * scale),
                           thickness: 1.8 * scale, color: stem)
            canvas.addEllipse(center: CGPoint(x: center.x + 5 * scale, y: center.y - 9 * scale),
                              radiusX: 4.5 * scale, radiusY: 2.2 * scale, color: green)
            canvas.addCircle(center: CGPoint(x: center.x - 4 * scale, y: center.y - 1 * scale),
                             radius: 1.5 * scale, color: shine)

        case .melon:
            canvas.addCircle(center: center, radius: 9 * scale, color: tinted(Color(0.52, 0.86, 0.27, 1)))
            for offset in [-4.0, 0.0, 4.0] {
                canvas.addLine(from: CGPoint(x: center.x + CGFloat(offset) * scale, y: center.y - 8 * scale),
                               to: CGPoint(x: center.x + CGFloat(offset) * scale, y: center.y + 8 * scale),
                               thickness: 1.2 * scale,
                               color: darkGreen)
            }
            canvas.addEllipse(center: CGPoint(x: center.x + 5 * scale, y: center.y - 7 * scale),
                              radiusX: 4.5 * scale, radiusY: 2.0 * scale, color: darkGreen)

        case .galaxian:
            let wingPoints = [
                CGPoint(x: center.x, y: center.y - 10 * scale),
                CGPoint(x: center.x + 11 * scale, y: center.y + 6 * scale),
                CGPoint(x: center.x + 3 * scale, y: center.y + 3 * scale),
                CGPoint(x: center.x, y: center.y + 9 * scale),
                CGPoint(x: center.x - 3 * scale, y: center.y + 3 * scale),
                CGPoint(x: center.x - 11 * scale, y: center.y + 6 * scale)
            ]
            canvas.addPolygon(points: wingPoints, color: cyan)
            canvas.addTriangle(CGPoint(x: center.x, y: center.y - 9 * scale),
                               CGPoint(x: center.x + 4 * scale, y: center.y + 4 * scale),
                               CGPoint(x: center.x - 4 * scale, y: center.y + 4 * scale),
                               color: yellow)
            canvas.addCircle(center: CGPoint(x: center.x, y: center.y - 1 * scale),
                             radius: 2.4 * scale, color: red)

        case .bell:
            let bellPoints = [
                CGPoint(x: center.x - 8 * scale, y: center.y + 4 * scale),
                CGPoint(x: center.x - 6 * scale, y: center.y - 5 * scale),
                CGPoint(x: center.x, y: center.y - 10 * scale),
                CGPoint(x: center.x + 6 * scale, y: center.y - 5 * scale),
                CGPoint(x: center.x + 8 * scale, y: center.y + 4 * scale)
            ]
            canvas.addPolygon(points: bellPoints, color: gold)
            canvas.addRect(x: center.x - 10 * scale, y: center.y + 4 * scale,
                           width: 20 * scale, height: 3 * scale, color: yellow)
            canvas.addCircle(center: CGPoint(x: center.x, y: center.y + 8.5 * scale),
                             radius: 2.2 * scale, color: yellow)
            canvas.addEllipse(center: CGPoint(x: center.x - 5 * scale, y: center.y - 3 * scale),
                              radiusX: 1.8 * scale, radiusY: 4.0 * scale, color: shine)

        case .key:
            canvas.addRing(center: CGPoint(x: center.x - 5 * scale, y: center.y - 5 * scale),
                           radius: 5 * scale,
                           thickness: 2.2 * scale,
                           color: cyan)
            canvas.addLine(from: CGPoint(x: center.x - 1.5 * scale, y: center.y - 1.5 * scale),
                           to: CGPoint(x: center.x + 7 * scale, y: center.y + 8 * scale),
                           thickness: 2.3 * scale,
                           color: cyan)
            canvas.addLine(from: CGPoint(x: center.x + 4 * scale, y: center.y + 5 * scale),
                           to: CGPoint(x: center.x + 8 * scale, y: center.y + 1 * scale),
                           thickness: 1.8 * scale,
                           color: cyan)
            canvas.addLine(from: CGPoint(x: center.x + 6.5 * scale, y: center.y + 7.5 * scale),
                           to: CGPoint(x: center.x + 10.5 * scale, y: center.y + 3.5 * scale),
                           thickness: 1.8 * scale,
                           color: cyan)
        }
    }

    // MARK: - HUD

    private func drawHUD(game: PacManGame) {
        font.draw("1UP", x: 150, y: 27, pixelSize: 2.4, color: Palette.dimBlue, alignment: .center)
        font.draw(paddedScore(game.score), x: 150, y: 49, pixelSize: 3.0, color: Palette.white, alignment: .center)

        font.draw("HIGH SCORE", x: Self.designWidth * 0.5, y: 27, pixelSize: 2.4, color: Palette.scoreCyan, alignment: .center)
        font.draw(paddedScore(game.highScore), x: Self.designWidth * 0.5, y: 49, pixelSize: 3.0, color: Palette.white, alignment: .center)

        font.draw("LEVEL", x: 746, y: 27, pixelSize: 2.4, color: Palette.dimBlue, alignment: .center)
        font.draw(String(format: "%02d", min(game.level, 99)), x: 746, y: 49, pixelSize: 3.0, color: Palette.white, alignment: .center)

        // Lives in the lower-left corner.
        font.draw("LIVES", x: 62, y: 1002, pixelSize: 1.55, color: Palette.faintBlue)
        let shownLives = min(game.displayedLives, 4)
        for index in 0..<shownLives {
            let center = CGPoint(x: 76 + CGFloat(index) * 29, y: 1034)
            drawLifePacman(center: center)
        }
        if game.displayedLives > 4 {
            font.draw("+\(game.displayedLives - 4)", x: 76 + 4 * 29, y: 1028, pixelSize: 1.7, color: Palette.pellet)
        }

        // Level fruit in the lower-right corner.
        let fruitCenter = CGPoint(x: 818, y: 1028)
        drawFruit(kind: game.currentFruitKind, center: fruitCenter, scale: 0.85, alpha: 0.9)
        let pointLabel = "\(game.currentFruitKind.points)"
        font.draw(pointLabel, x: 818, y: 1054, pixelSize: 1.5, color: Palette.faintBlue, alignment: .center)

        // Controls.
        font.draw("ARROWS / WASD", x: Self.designWidth * 0.5, y: 1006, pixelSize: 1.65, color: Palette.dimBlue, alignment: .center)
        let muteLabel = isMuted ? "M SOUND OFF" : "M MUTE"
        font.draw("P PAUSE    \(muteLabel)", x: Self.designWidth * 0.5, y: 1041, pixelSize: 1.45, color: Palette.faintBlue, alignment: .center)

        font.draw("A METAL TRIBUTE TO THE 1980 ARCADE", x: Self.designWidth * 0.5, y: 1072, pixelSize: 1.1, color: Color(0.20, 0.27, 0.50, 0.9), alignment: .center)
    }

    private func drawLifePacman(center: CGPoint) {
        canvas.addCircle(center: center, radius: 11.5, color: Palette.pacmanGlow, segments: 16)
        canvas.addPie(center: center,
                      radius: 8.4,
                      startAngle: 0.42,
                      endAngle: .pi * 2 - 0.42,
                      color: Palette.pacman,
                      segments: 28)
    }

    private func paddedScore(_ value: Int) -> String {
        let clamped = max(0, min(value, 999_999))
        return String(format: "%06d", clamped)
    }

    // MARK: - Overlays

    private func drawOverlays(game: PacManGame) {
        switch game.phase {
        case .attract:
            drawAttractOverlay(game: game)
        case .ready:
            drawReadyOverlay(game: game)
        case .levelComplete:
            drawLevelCompleteOverlay(game: game)
        case .gameOver:
            drawGameOverOverlay(game: game)
        case .playing, .dying:
            break
        }

        if game.isPaused {
            drawPausedOverlay()
        }
    }

    private func drawAttractOverlay(game: PacManGame) {
        canvas.addRect(x: playfieldRect.minX, y: playfieldRect.minY,
                       width: playfieldRect.width, height: playfieldRect.height,
                       color: Color(0, 0, 0, 0.58))

        let panel = CGRect(x: 112, y: 244, width: 672, height: 520)
        drawPanel(panel: panel, fillAlpha: 0.93, borderColor: Color(0.28, 0.46, 1.0, 0.6))

        drawLargeTitle("PAC-MAN", centerX: Self.designWidth * 0.5, y: 294)

        font.draw("THE ORIGINAL ARCADE", x: Self.designWidth * 0.5, y: 382,
                  pixelSize: 2.05, color: Palette.scoreCyan, alignment: .center)

        canvas.addLine(from: CGPoint(x: 244, y: 415), to: CGPoint(x: 652, y: 415),
                       thickness: 1, color: Color(0.32, 0.52, 1.0, 0.36), rounded: false)

        let gallery: [(GhostKind, String, CGFloat)] = [
            (.blinky, "BLINKY", 310),
            (.pinky, "PINKY", 402),
            (.inky, "INKY", 494),
            (.clyde, "CLYDE", 586)
        ]
        for (kind, name, x) in gallery {
            let center = CGPoint(x: x, y: 466)
            let color = ghostColor(for: kind)
            var glow = color
            glow.w = 0.17
            canvas.addCircle(center: center, radius: 21, color: glow, segments: 20)
            drawGhostBody(center: center, color: color)
            drawGhostEyes(center: center, direction: .left, large: false)
            font.draw(name, x: x, y: 493, pixelSize: 1.45, color: Palette.dimBlue, alignment: .center)
        }

        // Pac-Man chasing the lineup.
        let pacCenter = CGPoint(x: 448, y: 538)
        let mascotMouth = 0.32 + 0.28 * abs(sin(game.elapsed * 5.5))
        canvas.addCircle(center: pacCenter, radius: 18, color: Palette.pacmanGlow, segments: 20)
        canvas.addPie(center: pacCenter, radius: 12.5,
                      startAngle: mascotMouth,
                      endAngle: .pi * 2 - mascotMouth,
                      color: Palette.pacman,
                      segments: 36)

        let promptPulse = 0.68 + 0.32 * abs(sin(game.elapsed * 2.1))
        var promptColor = Palette.white
        promptColor.w = Float(promptPulse)
        font.drawGlow("PRESS ENTER TO PLAY", x: Self.designWidth * 0.5, y: 596,
                      pixelSize: 2.7, color: promptColor,
                      alignment: .center, glowColor: Color(0.40, 0.55, 1.0, Float(0.35 * promptPulse)))

        font.draw("ARROWS OR WASD TO MOVE", x: Self.designWidth * 0.5, y: 650,
                  pixelSize: 1.65, color: Palette.dimBlue, alignment: .center)
        font.draw("EAT EVERY DOT  -  AVOID THE GHOSTS", x: Self.designWidth * 0.5, y: 678,
                  pixelSize: 1.45, color: Palette.faintBlue, alignment: .center)
        font.draw("POWER PELLETS TURN THE TABLES", x: Self.designWidth * 0.5, y: 701,
                  pixelSize: 1.45, color: Palette.faintBlue, alignment: .center)

        font.draw("1 CREDIT", x: 150, y: 730, pixelSize: 1.55, color: Palette.pellet)
        if game.highScore > 0 {
            font.draw("BEST \(paddedScore(game.highScore))", x: 746, y: 730,
                      pixelSize: 1.35, color: Palette.dimBlue, alignment: .right)
        }
    }

    private func drawReadyOverlay(game: PacManGame) {
        let x = Self.designWidth * 0.5
        let y = Self.mazeOrigin.y + 17.15 * Self.tileSize
        font.drawGlow("READY!", x: x, y: y, pixelSize: 3.4, color: Palette.ready,
                      alignment: .center, glowColor: Color(1.0, 0.45, 0.05, 0.30))
    }

    private func drawLevelCompleteOverlay(game: PacManGame) {
        let x = Self.designWidth * 0.5
        let y = Self.mazeOrigin.y + 17.0 * Self.tileSize
        font.drawGlow("LEVEL \(game.level) CLEAR", x: x, y: y, pixelSize: 2.8,
                      color: Palette.white, alignment: .center,
                      glowColor: Color(0.35, 0.65, 1.0, 0.35))
    }

    private func drawGameOverOverlay(game: PacManGame) {
        canvas.addRect(x: playfieldRect.minX, y: playfieldRect.minY,
                       width: playfieldRect.width, height: playfieldRect.height,
                       color: Color(0, 0, 0, 0.70))
        let panel = CGRect(x: 162, y: 322, width: 572, height: 348)
        drawPanel(panel: panel, fillAlpha: 0.95, borderColor: Color(0.8, 0.18, 0.35, 0.58))

        font.drawGlow("GAME OVER", x: Self.designWidth * 0.5, y: 368, pixelSize: 5.2,
                      color: Palette.red, alignment: .center,
                      glowColor: Color(0.75, 0.08, 0.18, 0.35))

        font.draw("FINAL SCORE", x: Self.designWidth * 0.5, y: 470,
                  pixelSize: 1.8, color: Palette.dimBlue, alignment: .center)
        font.draw(paddedScore(game.score), x: Self.designWidth * 0.5, y: 493,
                  pixelSize: 3.6, color: Palette.white, alignment: .center)
        font.draw("HIGH SCORE  \(paddedScore(game.highScore))", x: Self.designWidth * 0.5, y: 546,
                  pixelSize: 1.55, color: Palette.scoreCyan, alignment: .center)

        let promptPulse = 0.68 + 0.32 * abs(sin(game.elapsed * 2.1))
        var promptColor = Palette.white
        promptColor.w = Float(promptPulse)
        font.draw("PRESS ENTER TO PLAY AGAIN", x: Self.designWidth * 0.5, y: 604,
                  pixelSize: 2.05, color: promptColor, alignment: .center)
    }

    private func drawPausedOverlay() {
        canvas.addRect(x: 0, y: 0, width: Self.designWidth, height: Self.designHeight,
                       color: Color(0.002, 0.004, 0.014, 0.72))
        let panel = CGRect(x: 218, y: 390, width: 460, height: 248)
        drawPanel(panel: panel, fillAlpha: 0.93, borderColor: Color(0.3, 0.6, 1.0, 0.6))
        font.drawGlow("PAUSED", x: Self.designWidth * 0.5, y: 434, pixelSize: 5.0,
                      color: Palette.scoreCyan, alignment: .center,
                      glowColor: Color(0.15, 0.55, 1.0, 0.25))
        font.draw("PRESS P TO RESUME", x: Self.designWidth * 0.5, y: 550,
                  pixelSize: 2.0, color: Palette.white, alignment: .center)
        font.draw("M TOGGLE SOUND", x: Self.designWidth * 0.5, y: 581,
                  pixelSize: 1.55, color: Palette.dimBlue, alignment: .center)
    }

    private func drawLargeTitle(_ text: String, centerX: CGFloat, y: CGFloat) {
        font.draw(text, x: centerX + 4, y: y + 5, pixelSize: 8.4,
                  color: Color(0.72, 0.12, 0.52, 0.40), alignment: .center)
        font.draw(text, x: centerX, y: y, pixelSize: 8.4, color: Palette.pacman, alignment: .center)
        font.draw(text, x: centerX - 1.5, y: y - 1.5, pixelSize: 8.4,
                  color: Color(1.0, 0.96, 0.55, 0.50), alignment: .center)
    }

    private func drawPanel(panel: CGRect, fillAlpha: Float, borderColor: Color) {
        canvas.addRect(x: panel.minX + 3, y: panel.minY + 5,
                       width: panel.width, height: panel.height,
                       color: Color(0, 0, 0, 0.55))
        canvas.addRect(x: panel.minX, y: panel.minY, width: panel.width, height: panel.height,
                       color: Color(0.010, 0.016, 0.048, fillAlpha))
        strokeRect(panel, color: borderColor, thickness: 1.4)
        strokeRect(panel.insetBy(dx: 5, dy: 5), color: Color(0.16, 0.28, 0.75, 0.30), thickness: 1)
    }

    private func strokeRect(_ rect: CGRect, color: Color, thickness: CGFloat) {
        canvas.addLine(from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.minY),
                       thickness: thickness, color: color, rounded: false)
        canvas.addLine(from: CGPoint(x: rect.maxX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY),
                       thickness: thickness, color: color, rounded: false)
        canvas.addLine(from: CGPoint(x: rect.maxX, y: rect.maxY), to: CGPoint(x: rect.minX, y: rect.maxY),
                       thickness: thickness, color: color, rounded: false)
        canvas.addLine(from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.minX, y: rect.minY),
                       thickness: thickness, color: color, rounded: false)
    }

    private func drawScanlines() {
        var y: CGFloat = 0
        while y < Self.designHeight {
            canvas.addRect(x: 0, y: y, width: Self.designWidth, height: 1,
                           color: Color(0, 0, 0, 0.055))
            y += 4
        }
    }
}

enum RendererError: Error {
    case noMetalDevice
    case couldNotCreateCommandQueue
    case shaderCompilationFailed
    case pipelineCreationFailed
    case couldNotCreateVertexBuffer
}
