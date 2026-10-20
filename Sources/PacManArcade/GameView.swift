import AppKit
import MetalKit
import PacManCore
import QuartzCore

final class GameView: MTKView, MTKViewDelegate {
    private(set) var game: PacManGame!
    private var renderer: Renderer!
    private let sound = SoundEngine()

    private var lastFrameTime: CFTimeInterval = 0
    private var accumulator: Double = 0
    private var lastSavedHighScore: Int
    private var lastHighScoreSaveTime: CFTimeInterval = 0
    private var resignObserver: NSObjectProtocol?
    private let autoPauseOnResign: Bool

    private let highScoreKey = "PacManArcadeHighScore"
    private let mutedKey = "PacManArcadeMuted"

    private let fixedTimeStep = 1.0 / 60.0

    init(arcadeFrame frame: CGRect) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.noMetalDevice
        }

        let savedHighScore = UserDefaults.standard.integer(forKey: "PacManArcadeHighScore")
        lastSavedHighScore = savedHighScore
        autoPauseOnResign = ProcessInfo.processInfo.environment["PACMAN_AUTOPAUSE"] != "0"
        game = PacManGame(highScore: savedHighScore)

        super.init(frame: frame, device: device)

        colorPixelFormat = .bgra8Unorm
        sampleCount = device.supportsTextureSampleCount(4) ? 4 : 1
        clearColor = MTLClearColor(red: 0.006, green: 0.008, blue: 0.020, alpha: 1.0)
        framebufferOnly = true
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60

        renderer = try Renderer(view: self)
        delegate = self
        wantsLayer = true

        sound.isMuted = UserDefaults.standard.bool(forKey: mutedKey)
        renderer.isMuted = sound.isMuted

        if ProcessInfo.processInfo.environment["PACMAN_AUTOSTART"] == "1" {
            game.startNewGame()
        }

        if autoPauseOnResign {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.game.pause()
            }
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        saveHighScore()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.backgroundColor = .black
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // The renderer derives its letterbox transform from the drawable size.
    }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        if lastFrameTime == 0 {
            lastFrameTime = now
        }
        let frameDelta = min(max(now - lastFrameTime, 0), 0.1)
        lastFrameTime = now
        accumulator += frameDelta

        var steps = 0
        while accumulator >= fixedTimeStep, steps < 8 {
            game.update(dt: fixedTimeStep)
            processEvents()
            accumulator -= fixedTimeStep
            steps += 1
        }
        if steps == 8 {
            accumulator = 0
        }

        renderer.isMuted = sound.isMuted
        renderer.render(game: game, in: view)

        if game.highScore != lastSavedHighScore {
            let current = CACurrentMediaTime()
            if game.phase == .gameOver || current - lastHighScoreSaveTime > 1.5 {
                lastHighScoreSaveTime = current
                saveHighScore()
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123:
            game.setDirection(.left)
        case 124:
            game.setDirection(.right)
        case 125:
            game.setDirection(.down)
        case 126:
            game.setDirection(.up)
        case 0:
            game.setDirection(.left)
        case 1:
            game.setDirection(.down)
        case 2:
            game.setDirection(.right)
        case 13:
            game.setDirection(.up)
        case 36, 49, 76:
            if game.phase == .attract || game.phase == .gameOver {
                game.requestStart()
            }
        case 35:
            game.togglePause()
        case 46:
            toggleMute()
        case 53:
            game.pause()
        default:
            if let characters = event.charactersIgnoringModifiers?.lowercased() {
                if characters == "p" {
                    game.togglePause()
                } else if characters == "m" {
                    toggleMute()
                } else if game.phase == .attract || game.phase == .gameOver,
                          characters == "\r" || characters == " " {
                    game.requestStart()
                }
            }
        }
    }

    func saveHighScore() {
        if game.highScore > lastSavedHighScore {
            UserDefaults.standard.set(game.highScore, forKey: highScoreKey)
            lastSavedHighScore = game.highScore
        }
    }

    func toggleMute() {
        sound.isMuted.toggle()
        renderer.isMuted = sound.isMuted
        UserDefaults.standard.set(sound.isMuted, forKey: mutedKey)
        if !sound.isMuted {
            sound.play(.powerPellet)
        }
    }

    private func processEvents() {
        for event in game.drainEvents() {
            switch event {
            case .gameStart:
                sound.play(.start)
            case .chomp:
                sound.playChomp()
            case .powerPellet:
                sound.play(.powerPellet)
            case .ghostEaten(let combo):
                sound.play(.ghostEaten(combo: combo))
            case .fruitEaten:
                sound.play(.fruit)
            case .extraLife:
                sound.play(.extraLife)
            case .pacDeath:
                sound.play(.death)
            case .levelComplete:
                sound.play(.levelComplete)
            case .gameOver:
                sound.play(.gameOver)
                saveHighScore()
            }
        }
    }
}
